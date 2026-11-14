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
    private const val STALE_MS = 5 * 60_000L

    fun schedule(context: Context, id: Long) {
        runCatching {
            val alarm = context.getSystemService(AlarmManager::class.java)
            alarm.set(AlarmManager.RTC, System.currentTimeMillis() + DELAY_MS, pending(context, id))
        }
    }

    fun cancel(context: Context, id: Long) {
        runCatching {
            context.getSystemService(AlarmManager::class.java).cancel(pending(context, id))
        }
    }

    
    fun failIfPending(context: Context, id: Long): Boolean = try {
        val row = context.contentResolver.query(
            android.content.ContentUris.withAppendedId(Telephony.Sms.CONTENT_URI, id),
            arrayOf("type"),
            null,
            null,
            null,
        )?.use { if (it.moveToFirst()) it.getInt(0) else null }
        if (row != null && row == Telephony.Sms.MESSAGE_TYPE_OUTBOX) {
            context.contentResolver.update(
                android.content.ContentUris.withAppendedId(Telephony.Sms.CONTENT_URI, id),
                ContentValues().apply {
                    put("type", Telephony.Sms.MESSAGE_TYPE_FAILED)
                    put("status", Telephony.Sms.STATUS_FAILED)
                },
                null,
                null,
            )
            Log.d(TAG, "watchdog marked $id failed")
            true
        } else {
            false
        }
    } catch (_: Exception) {
        false
    }

    
    fun sweep(context: Context) {
        try {
            MessageStore(context).use { store ->
                for (id in store.outgoingIds()) {
                    if (isStale(context, id)) failIfPending(context, id)
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

    fun isStale(context: Context, id: Long): Boolean = try {
        context.contentResolver.query(
            android.content.ContentUris.withAppendedId(Telephony.Sms.CONTENT_URI, id),
            arrayOf("date"),
            null,
            null,
            null,
        )?.use { if (it.moveToFirst()) System.currentTimeMillis() - it.getLong(0) > STALE_MS else false } ?: false
    } catch (_: Exception) {
        false
    }
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
