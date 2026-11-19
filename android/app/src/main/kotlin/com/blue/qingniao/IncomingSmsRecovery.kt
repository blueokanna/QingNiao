package com.blue.qingniao

import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import java.util.concurrent.atomic.AtomicBoolean

/** A short, coalesced drain plus persisted system retry; no resident service or polling loop. */
internal object IncomingSmsRecovery {
    private const val JOB_ID = 9024
    private const val TAG = "IncomingSms"
    private val drainQueued = AtomicBoolean(false)
    private val requests = IncomingSmsRecoveryRequests()

    fun schedule(context: Context) {
        try {
            val scheduler = context.getSystemService(JobScheduler::class.java)
            requests.request({ scheduler.getPendingJob(JOB_ID) != null }) {
                val job = JobInfo.Builder(JOB_ID, ComponentName(context, IncomingSmsRecoveryService::class.java))
                    .setPersisted(true)
                    .setMinimumLatency(15_000)
                    .setBackoffCriteria(30_000, JobInfo.BACKOFF_POLICY_EXPONENTIAL)
                    .build()
                val scheduled = scheduler.schedule(job) == JobScheduler.RESULT_SUCCESS
                if (!scheduled) Log.w(TAG, "SMS recovery could not be scheduled; journal retained")
                scheduled
            }
        } catch (error: Exception) {
            Log.w(TAG, "SMS recovery scheduling failed: ${error.javaClass.simpleName}")
        }
    }

    internal fun jobStarted(): Long = requests.started()

    internal fun jobFinished(generation: Long, retry: Boolean, finish: (Boolean) -> Unit) =
        requests.finish(generation, retry, finish)

    fun restore(context: Context) {
        val app = context.applicationContext
        MessageIo.smsIntakeExecutor.execute {
            try {
                IncomingSmsStore(app).use { store ->
                    if (store.hasPending() && SmsAccess.isDefaultSmsApp(app)) {
                        schedule(app)
                        drainSoon(app)
                    }
                }
            } catch (error: Exception) {
                Log.w(TAG, "SMS recovery unavailable: ${error.javaClass.simpleName}")
            }
        }
    }

    fun drainSoon(context: Context) {
        if (!drainQueued.compareAndSet(false, true)) return
        val app = context.applicationContext
        try {
            MessageIo.smsDeliveryExecutor.execute {
                // The executor serializes deliveries. Let arrivals during this batch enqueue
                // one successor, including arrivals after pending() took its snapshot.
                drainQueued.set(false)
                if (drain(app)) schedule(app)
            }
        } catch (error: Exception) {
            drainQueued.set(false)
            schedule(app)
            Log.w(TAG, "SMS delivery queue unavailable: ${error.javaClass.simpleName}")
        }
    }

    /** Returns whether a later job should retry. A provider call may outlive this batch budget. */
    fun drain(context: Context, stopped: () -> Boolean = { false }): Boolean {
        if (stopped() || !SmsAccess.isDefaultSmsApp(context)) return false
        val deadline = SystemClock.elapsedRealtime() + 5_000
        return try {
            IncomingSmsStore(context).use { store ->
                val delivery = IncomingSmsDelivery(object : IncomingSmsDelivery.Target {
                    override fun isDefaultSmsApp() = SmsAccess.isDefaultSmsApp(context)
                    override fun persist(message: IncomingSms) = SmsRepository.persistIncoming(context, message)
                    override fun complete(key: String) = store.complete(key)
                    override fun notify(message: IncomingSms, saved: SavedIncomingSms) {
                        // Stay inside the job lifetime until the notification attempt completes.
                        Notifications.showSms(context, message.address, message.body,
                            message.subscriptionId, saved.threadId)
                    }
                    override fun notificationFailed(error: Exception) {
                        Log.w(TAG, "SMS saved; notification unavailable: ${error.javaClass.simpleName}")
                    }
                })
                // Rotate failed rows by attempted_at, so one broken row cannot starve newer SMS.
                var delivered = false
                for (message in store.pending(20)) {
                    if (stopped() || SystemClock.elapsedRealtime() >= deadline) break
                    try {
                        store.attempted(message.key)
                        if (!delivery.deliver(message)) break
                        delivered = true
                    } catch (error: Exception) {
                        // Do not log exceptions/messages that may contain an SMS body or sender.
                        Log.w(TAG, "SMS remains journaled: ${error.javaClass.simpleName}")
                    }
                }
                store.pruneReceipts()
                val pending = store.hasPending() && SmsAccess.isDefaultSmsApp(context)
                if (pending && delivered && !stopped() && store.hasUnattempted()) drainSoon(context)
                pending
            }
        } catch (error: Exception) {
            Log.w(TAG, "SMS journal unavailable: ${error.javaClass.simpleName}")
            true
        }
    }
}

class IncomingSmsRecoveryService : JobService() {
    private val handler = Handler(Looper.getMainLooper())
    private val runs = IncomingSmsJobRuns()

    override fun onStartJob(params: JobParameters): Boolean {
        val stopped = runs.start(params.jobId)
        val generation = IncomingSmsRecovery.jobStarted()
        val app = applicationContext
        MessageIo.smsDeliveryExecutor.execute {
            val retry = IncomingSmsRecovery.drain(app, stopped::get)
            handler.post {
                // Binder supplies different JobParameters objects to start/stop callbacks.
                // An old completion must not remove a replacement job's token.
                if (runs.finish(params.jobId, stopped)) {
                    IncomingSmsRecovery.jobFinished(generation, retry) { reschedule ->
                        jobFinished(params, reschedule)
                    }
                }
            }
        }
        return true
    }

    override fun onStopJob(params: JobParameters): Boolean {
        runs.stop(params.jobId)
        return true
    }

    override fun onDestroy() {
        runs.stopAll()
        super.onDestroy()
    }
}

class IncomingSmsRecoveryReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            android.provider.Telephony.Sms.Intents.ACTION_DEFAULT_SMS_PACKAGE_CHANGED -> Unit
            else -> return
        }
        // Only request the persisted job here; there is no receiver-owned asynchronous database work.
        if (SmsAccess.isDefaultSmsApp(context)) IncomingSmsRecovery.schedule(context)
    }
}
