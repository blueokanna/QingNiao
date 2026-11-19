package com.blue.qingniao

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import android.util.Log
object SmsSendWatchdog {
    private const val TAG = "QingniaoSms"
    private const val DELAY_MS = 90_000L

    fun schedule(context: Context, id: Long, at: Long = System.currentTimeMillis() + DELAY_MS) {
        runCatching {
            val alarm = context.getSystemService(AlarmManager::class.java)
            alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending(context, id))
        }
    }

    fun cancel(context: Context, id: Long) {
        runCatching {
            context.getSystemService(AlarmManager::class.java).cancel(pending(context, id))
        }
    }

    fun failIfPending(context: Context, id: Long): Boolean = try {
        MessageStore(context).use { store -> reconcile(context, store, id) }
    } catch (_: Exception) { false }

    private fun reconcile(context: Context, store: MessageStore, id: Long): Boolean = try {
        val uri = android.content.ContentUris.withAppendedId(Telephony.Sms.CONTENT_URI, id)
        val row = checkNotNull(context.contentResolver.query(
            uri,
            arrayOf("type", "date"),
            null,
            null,
            null,
        )).use { if (it.moveToFirst()) it.getInt(0) to it.getLong(1) else null }
        if (row == null) {
            store.forgetOutgoing(id)
            false
        } else if (row.first in setOf(Telephony.Sms.MESSAGE_TYPE_OUTBOX, Telephony.Sms.MESSAGE_TYPE_QUEUED)) {
            // A receipt may be durable even if the provider write failed or the process died.
            val delivered = store.receiptState(id, "delivered")
            val sent = store.receiptState(id, "sent")
                ?: delivered?.takeIf { it == Telephony.Sms.MESSAGE_TYPE_SENT }
            if (sent == null && System.currentTimeMillis() - row.second < DELAY_MS) {
                schedule(context, id, row.second + DELAY_MS)
                false
            } else {
                val state = sent ?: Telephony.Sms.MESSAGE_TYPE_FAILED
                val updated = context.contentResolver.update(
                    uri,
                    ContentValues().apply {
                        put("type", state)
                        put("status", when {
                            state == Telephony.Sms.MESSAGE_TYPE_FAILED || delivered == Telephony.Sms.MESSAGE_TYPE_FAILED -> Telephony.Sms.STATUS_FAILED
                            delivered == Telephony.Sms.MESSAGE_TYPE_SENT -> Telephony.Sms.STATUS_COMPLETE
                            else -> Telephony.Sms.STATUS_PENDING
                        })
                    },
                    "type IN (4,6)",
                    null,
                )
                if (updated > 0) cancel(context, id)
                Log.d(TAG, "watchdog reconciled $id type=$state")
                updated > 0
            }
        } else {
            false
        }
    } catch (_: Exception) {
        false
    }

    fun sweep(context: Context) {
        try {
            MessageStore(context).use { store ->
                val tracked = store.outgoingIds().toHashSet()
                if (tracked.isEmpty()) return
                // Query only pending rows, rather than probing every historical sent message
                // on each foreground recovery tick.
                context.contentResolver.query(
                    Telephony.Sms.CONTENT_URI, arrayOf("_id"), "type IN (4,6)", null, null,
                )?.use { cursor ->
                    while (cursor.moveToNext()) {
                        val id = cursor.getLong(0)
                        if (id in tracked) reconcile(context, store, id)
                    }
                }
            }
        } catch (_: Exception) {

        }
    }

    private fun pending(context: Context, id: Long): PendingIntent = PendingIntent.getBroadcast(
        context,
        (id % Int.MAX_VALUE).toInt(),
        Intent(context, SmsSendTimeoutReceiver::class.java).putExtra("id", id),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

}

class SmsSendTimeoutReceiver : android.content.BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getLongExtra("id", -1)
        if (id < 0) return
        val pending = goAsync()
        MessageIo.receiverExecutor.execute {
            try {
                SmsSendWatchdog.failIfPending(context, id)
            } finally {
                pending.finish()
            }
        }
    }
}
