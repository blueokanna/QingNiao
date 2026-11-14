package com.blue.qingniao

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri

object ScheduledMessageAlarms {
    private fun pending(context: Context, id: Long): PendingIntent = PendingIntent.getBroadcast(
        context, 0,
        Intent(context, ScheduledSendReceiver::class.java)
            .setData(Uri.parse("qingniao://scheduled/$id")).putExtra("id", id),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    fun cancel(context: Context, id: Long) {
        val alarm = context.getSystemService(AlarmManager::class.java)
        val current = pending(context, id)
        alarm.cancel(current)
        current.cancel()
        // Retire alarms created before URI-based identities were introduced.
        val legacy = PendingIntent.getBroadcast(context, id.toInt(),
            Intent(context, ScheduledSendReceiver::class.java),
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE)
        if (legacy != null) { alarm.cancel(legacy); legacy.cancel() }
    }

    fun arm(context: Context, id: Long, at: Long) {
        cancel(context, id)
        val alarm = context.getSystemService(AlarmManager::class.java)
        val pending = pending(context, id)
        try {
            if (alarm.canScheduleExactAlarms()) {
                alarm.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending)
            } else {
                alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending)
            }
        } catch (_: SecurityException) {
            alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending)
        }
    }

    fun restore(context: Context) {
        AuroraStore(context).use { store ->
            val now = System.currentTimeMillis()
            for (row in store.scheduled()) {
                // Missed messages remain available for review, never sent in a burst after reboot.
                if (row.at > now) arm(context, row.id, row.at)
            }
        }
    }
}

class ScheduleRecoveryReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action !in setOf(Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED,
                AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED)) return
        val pending = goAsync()
        MessageIo.executor.execute {
            try { ScheduledMessageAlarms.restore(context) }
            catch (_: Exception) { android.util.Log.w("ScheduleRecovery", "Unable to restore scheduled alarms") }
            finally { pending.finish() }
        }
    }
}
