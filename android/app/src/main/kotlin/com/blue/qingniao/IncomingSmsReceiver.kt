package com.blue.qingniao

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.provider.Telephony
import android.util.Log
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

class IncomingSmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_DELIVER_ACTION) return
        val message = decodeIncomingSms(context, intent) ?: return
        val app = context.applicationContext
        val pending = goAsync()
        MessageIo.smsIntakeExecutor.execute {
            var fallbackStarted = false
            try {
                IncomingSmsStore(app).use { it.enqueue(message) }
                IncomingSmsRecovery.schedule(app)
                IncomingSmsRecovery.drainSoon(app)
            } catch (error: Exception) {
                Log.e("IncomingSms", "Unable to journal incoming SMS: ${error.javaClass.simpleName}")
                // A private DB error need not mean the system SMS provider is unavailable.
                // Keep this exceptional broadcast alive until that persistence attempt returns.
                MessageIo.smsDeliveryExecutor.execute {
                    try {
                        check(SmsAccess.isDefaultSmsApp(app))
                        val saved = SmsRepository.persistIncoming(app, message)
                        if (!saved.read) {
                            try {
                                Notifications.showSms(app, message.address, message.body,
                                    message.subscriptionId, saved.threadId)
                            } catch (notificationError: Exception) {
                                Log.w("IncomingSms", "SMS saved; notification unavailable: ${notificationError.javaClass.simpleName}")
                            }
                        }
                    } catch (saveError: Exception) {
                        Log.e("IncomingSms", "Both SMS storage paths failed: ${saveError.javaClass.simpleName}")
                        try {
                            MessageNotifications.show(app, "", "Unable to save message. Check permissions and storage.", 9023)
                        } catch (_: Exception) { }
                    } finally {
                        pending.finish()
                    }
                }
                fallbackStarted = true
            } finally {
                // Never finish SMS_DELIVER on a timer before the journal commits. Normal
                // receiver work is local persistence only; a provider stall belongs to the job.
                if (!fallbackStarted) pending.finish()
            }
        }
    }
}

private val receivedTimes = AtomicLong(0)

internal fun decodeIncomingSms(context: Context, intent: Intent): IncomingSms? = try {
    val parts = Telephony.Sms.Intents.getMessagesFromIntent(intent)
    if (parts.isNullOrEmpty()) null else {
        val subscription = SimSubscriptions.incomingId(context, intent)
        val first = parts.first()
        IncomingSms(
            IncomingSms.key(parts.map { requireNotNull(it.pdu) }, intent.getStringExtra("format"),
                subscription, SimSubscriptions.incomingSlot(intent)),
            first.originatingAddress ?: "Unknown number",
            parts.joinToString("") { it.messageBody.orEmpty() },
            receivedTimes.updateAndGet { maxOf(System.currentTimeMillis(), it + 1) },
            first.timestampMillis, subscription,
            first.serviceCenterAddress, first.protocolIdentifier, first.isReplyPathPresent,
        )
    }
} catch (error: Exception) {
    Log.w("IncomingSms", "Invalid SMS broadcast: ${error.javaClass.simpleName}")
    null
}

/** Only for notification-only SMS_RECEIVED; it never acknowledges the durable SMS_DELIVER handoff. */
internal class SmsBroadcastCompletion(private val pending: BroadcastReceiver.PendingResult) {
    private val finished = AtomicBoolean(false)
    private val handler = Handler(Looper.getMainLooper())
    private val timeout = Runnable {
        Log.w("IncomingSms", "SMS broadcast handoff exceeded its time budget")
        finish()
    }

    init { handler.postDelayed(timeout, 8_000) }

    fun finish() {
        if (finished.compareAndSet(false, true)) {
            handler.removeCallbacks(timeout)
            pending.finish()
        }
    }
}

object MessageNotifications {
    fun show(context: Context, address: String, text: String, id: Int) {
        val preferences = context.getSharedPreferences("appearance", Context.MODE_PRIVATE)
        if (!preferences.readFlag("notifications", true)) return
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel("incoming", LocalizedResources.text(context, R.string.notification_messages), NotificationManager.IMPORTANCE_HIGH))
        val open = Intent(context, MainActivity::class.java).putExtra("address", address)
        val action = PendingIntent.getActivity(context, id, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification = Notification.Builder(context, "incoming").setSmallIcon(R.drawable.ic_stat_message)
            .setContentTitle(LocalizedResources.text(context, R.string.app_name))
            .setContentText(if (preferences.readFlag("preview", true)) text else LocalizedResources.text(context, R.string.notification_new_message))
            .setContentIntent(action)
            .setVisibility(Notification.VISIBILITY_PRIVATE).setAutoCancel(true).build()
        try { manager.notify(id, notification) } catch (_: SecurityException) { }
    }
}
