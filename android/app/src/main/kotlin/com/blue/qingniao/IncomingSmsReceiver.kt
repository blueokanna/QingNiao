package com.blue.qingniao

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import android.telephony.SubscriptionManager

class IncomingSmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_DELIVER_ACTION) return
        val parts = Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return
        if (parts.isEmpty()) return
        val pending = goAsync()
        MessageIo.receiverExecutor.execute {
            try {
                val address = parts.first().originatingAddress ?: "Unknown number"
                val body = parts.joinToString("") { it.messageBody ?: "" }
                val subscription = intent.getIntExtra(SubscriptionManager.EXTRA_SUBSCRIPTION_INDEX, intent.getIntExtra("subscription", -1))
                try {
                    Notifications.showSms(context, address, body, subscription, -1L)
                } catch (_: Exception) {
                }
                val saved = context.contentResolver.insert(Telephony.Sms.Inbox.CONTENT_URI, ContentValues().apply {
                    put("address", address); put("body", body); put("date", System.currentTimeMillis())
                    put("date_sent", parts.first().timestampMillis); put("read", 0); put("seen", 0)
                    put("sub_id", subscription)
                })
            } catch (_: Exception) {
                MessageNotifications.show(context, "", "Unable to save message. Check permissions and storage.", 9023)
            } finally { pending.finish() }
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
