package com.blue.qingniao

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.AlarmManager
import android.content.BroadcastReceiver
import android.content.ClipData
import android.content.ClipboardManager
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Telephony
import android.telephony.SubscriptionManager
import android.widget.Toast


object Notifications {
    const val KEY_REPLY = "qingniao_reply"
    const val GROUP = "com.blue.qingniao.MESSAGES"
    const val SUMMARY_ID = 4100
    private const val POST_PROMOTED = "android.permission.POST_PROMOTED_NOTIFICATIONS"

    fun showSms(
        context: Context,
        address: String,
        body: String,
        subscriptionId: Int,
        threadId: Long,
    ) {
        val prefs = context.getSharedPreferences("appearance", Context.MODE_PRIVATE)
        if (!AppPrefs.bool(prefs, "notifications", true)) return
        val preview = AppPrefs.bool(prefs, "preview", true)
        val manager = context.getSystemService(NotificationManager::class.java)
        val channelId = "messages_${subscriptionId.coerceAtLeast(0)}"
        val channel = NotificationChannel(
            channelId,
            if (subscriptionId >= 0) "SMS · SIM $subscriptionId" else "SMS",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = LocalizedResources.text(context, R.string.notification_messages)
            enableVibration(true)
            setShowBadge(true)
        }
        manager.createNotificationChannel(channel)

        val id = address.hashCode()
        val open = Intent(context, MainActivity::class.java)
            .putExtra("address", address)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val contentIntent = PendingIntent.getActivity(
            context,
            id,
            open,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val replyIntent = Intent(context, ReplyReceiver::class.java)
            .putExtra("address", address)
            .putExtra("sub", subscriptionId)
            .putExtra("notif", id)
        val replyPending = PendingIntent.getBroadcast(
            context,
            id,
            replyIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
        )
        val remoteInput = RemoteInputBuilder.build(context)
        val replyAction = Notification.Action.Builder(
            Icon.createWithResource(context, android.R.drawable.ic_menu_send),
            LocalizedResources.text(context, R.string.notification_reply),
            replyPending,
        ).addRemoteInput(remoteInput).build()

        val readIntent = Intent(context, MarkReadReceiver::class.java)
            .putExtra("address", address)
            .putExtra("thread", threadId)
            .putExtra("notif", id)
        val readPending = PendingIntent.getBroadcast(
            context,
            id + 1,
            readIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val readAction = Notification.Action.Builder(
            Icon.createWithResource(context, android.R.drawable.ic_menu_view),
            LocalizedResources.text(context, R.string.notification_mark_read),
            readPending,
        ).build()

        val text = if (preview) body else LocalizedResources.text(context, R.string.notification_new_message)
        val otp = if (preview) extractOtp(context, body) else null
        val copyPending = otp?.let { code ->
            PendingIntent.getBroadcast(
                context,
                id + 2,
                Intent(context, CopyOtpReceiver::class.java)
                    .putExtra("code", code)
                    .putExtra("notif", id),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
        val copyAction = copyPending?.let {
            Notification.Action.Builder(
                Icon.createWithResource(context, android.R.drawable.ic_menu_edit),
                LocalizedResources.text(context, R.string.notification_copy_code),
                it,
            ).build()
        }
        val builder = Notification.Builder(context, channelId)
            .setSmallIcon(R.drawable.ic_stat_message)
            .setContentTitle(address)
            .setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setContentIntent(contentIntent)
            .setAutoCancel(true)
            .setGroup(GROUP)
            .setCategory(Notification.CATEGORY_MESSAGE)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setOnlyAlertOnce(false)
            .addAction(replyAction)
        if (copyAction != null) builder.addAction(copyAction)
        builder.addAction(readAction)


        val promoted = canPromote(context) && AppPrefs.bool(prefs, "fluidCloud", true)
        if (promoted && Build.VERSION.SDK_INT >= 36) {
            try {
                builder
                    .setOngoing(true)
                    .setAutoCancel(false)
                    .setShortCriticalText(if (otp != null) "OTP" else "SMS")
                requestPromotedOngoing(builder)
            } catch (_: Throwable) {

            }
        }

        val summary = Notification.Builder(context, channelId)
            .setSmallIcon(R.drawable.ic_stat_message)
            .setContentTitle(LocalizedResources.text(context, R.string.app_name))
            .setContentText(LocalizedResources.text(context, R.string.notification_new_message))
            .setGroup(GROUP)
            .setGroupSummary(true)
            .setAutoCancel(true)
            .build()
        try {
            manager.notify(id, builder.build())
            manager.notify(SUMMARY_ID, summary)
            if (promoted) scheduleExpiry(context, id)
        } catch (_: SecurityException) {
        }
    }

    
    private fun scheduleExpiry(context: Context, id: Int) {
        try {
            val alarm = context.getSystemService(AlarmManager::class.java)
            val pending = PendingIntent.getBroadcast(
                context,
                id,
                Intent(context, NotificationExpiryReceiver::class.java).putExtra("id", id),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            alarm.set(AlarmManager.RTC, System.currentTimeMillis() + 15 * 60 * 1000L, pending)
        } catch (_: Exception) {

        }
    }

    
    fun showProgress(
        context: Context,
        address: String,
        text: String,
        subscriptionId: Int,
        notificationId: Int,
    ) {
        val prefs = context.getSharedPreferences("appearance", Context.MODE_PRIVATE)
        if (!AppPrefs.bool(prefs, "notifications", true)) return
        val manager = context.getSystemService(NotificationManager::class.java)
        val channelId = "messages_${subscriptionId.coerceAtLeast(0)}"
        manager.createNotificationChannel(
            NotificationChannel(
                channelId,
                if (subscriptionId >= 0) "SMS · SIM $subscriptionId" else "SMS",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = LocalizedResources.text(context, R.string.notification_messages)
                enableVibration(true)
                setShowBadge(true)
            },
        )
        val open = Intent(context, MainActivity::class.java)
            .putExtra("address", address)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val contentIntent = PendingIntent.getActivity(
            context,
            notificationId,
            open,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = Notification.Builder(context, channelId)
            .setSmallIcon(R.drawable.ic_stat_message)
            .setContentTitle(address.ifBlank { "MMS" })
            .setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setContentIntent(contentIntent)
            .setOngoing(true)
            .setAutoCancel(false)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_PROGRESS)
            .setProgress(0, 0, true)
            .setGroup(GROUP)
        try {
            manager.notify(notificationId, builder.build())
        } catch (_: SecurityException) {

        }
    }

    
    fun canPromote(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < 36) return false
        if (context.checkSelfPermission(POST_PROMOTED) != PackageManager.PERMISSION_GRANTED) return false
        return promotionApiAvailable()
    }

    
    fun promotionActive(context: Context): Boolean {
        if (!canPromote(context)) return false
        return try {
            val manager = context.getSystemService(NotificationManager::class.java)
            val method = NotificationManager::class.java.getMethod("canPostPromotedNotifications")
            method.invoke(manager) as? Boolean ?: false
        } catch (_: Throwable) {
            false
        }
    }

    private fun promotionApiAvailable(): Boolean = try {
        NotificationManager::class.java.getMethod("canPostPromotedNotifications")
        true
    } catch (_: Throwable) {

        false
    }

    
    private fun requestPromotedOngoing(builder: Notification.Builder) {
        try {
            val method = Notification.Builder::class.java
                .getMethod("setRequestPromotedOngoing", Boolean::class.javaPrimitiveType)
            method.invoke(builder, true)
        } catch (_: Throwable) {
        }
    }

    fun fluidCloudEnabled(context: Context): Boolean {
        val prefs = context.getSharedPreferences("appearance", Context.MODE_PRIVATE)
        return AppPrefs.bool(prefs, "fluidCloud", true) && canPromote(context)
    }

    fun markReplied(context: Context, address: String, notificationId: Int) {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.cancel(notificationId)
        Handler(Looper.getMainLooper()).post {
            Toast.makeText(context, "Replied to $address", Toast.LENGTH_SHORT).show()
        }
    }

    fun cancel(context: Context, notificationId: Int) {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.cancel(notificationId)
        try {
            val remaining = manager.activeNotifications.any { status ->
                status.id != SUMMARY_ID && status.notification.group == GROUP
            }
            if (!remaining) manager.cancel(SUMMARY_ID)
        } catch (_: Exception) {
        }
    }
}


private object RemoteInputBuilder {
    fun build(context: Context) = android.app.RemoteInput.Builder(Notifications.KEY_REPLY)
        .setLabel(LocalizedResources.text(context, R.string.notification_reply))
        .setAllowFreeFormInput(true)
        .build()
}


private fun extractOtp(context: Context, body: String): String? {
    val lower = body.lowercase()
    val keywords = context.resources.getStringArray(R.array.verification_keywords)
    if (keywords.none { lower.contains(it) }) return null
    val candidates = Regex("(?<!\\d)(\\d{4,8})(?!\\d)").findAll(body).toList()
    if (candidates.size != 1) return null
    val code = candidates.first().groupValues[1]
    if (code.length == 4 && (code.startsWith("19") || code.startsWith("20"))) return null
    return code
}

class CopyOtpReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val code = intent.getStringExtra("code") ?: return
        val clipboard = context.getSystemService(ClipboardManager::class.java)
        val clip = ClipData.newPlainText("Verification code", code)
        clip.description.extras = android.os.PersistableBundle().apply {
            putBoolean("android.content.extra.IS_SENSITIVE", true)
        }
        clipboard.setPrimaryClip(clip)
        Notifications.cancel(context, intent.getIntExtra("notif", code.hashCode()))
        if (Build.VERSION.SDK_INT < 33) Handler(Looper.getMainLooper()).post {
            Toast.makeText(context, LocalizedResources.text(context, R.string.notification_code_copied), Toast.LENGTH_SHORT).show()
        }
    }
}

class ReplyReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val results = android.app.RemoteInput.getResultsFromIntent(intent) ?: return
        val text = results.getCharSequence(Notifications.KEY_REPLY)?.toString()?.trim().orEmpty()
        if (text.isEmpty()) return
        val address = intent.getStringExtra("address") ?: return
        val subscriptionId = intent.getIntExtra("sub", -1)
        val notificationId = intent.getIntExtra("notif", address.hashCode())
        val pending = goAsync()
        MessageIo.receiverExecutor.execute {
            try {
                check(SmsAccess.isDefaultSmsApp(context))
                MessageStore(context).use { store ->
                    val subscription = if (subscriptionId >= 0) {
                        subscriptionId
                    } else {
                        SubscriptionManager.getDefaultSmsSubscriptionId()
                    }
                    SmsTransport.send(context, store, address, text, subscription)
                }
                Notifications.markReplied(context, address, notificationId)
            } catch (error: Exception) {
                MessageNotifications.show(
                    context,
                    address,
                    LocalizedResources.text(context, R.string.notification_failed),
                    notificationId + 9000,
                )
            } finally {
                pending.finish()
            }
        }
    }
}

class MarkReadReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val threadId = intent.getLongExtra("thread", -1)
        val address = intent.getStringExtra("address")
        val notificationId = intent.getIntExtra("notif", address?.hashCode() ?: 0)
        try {
            val values = ContentValues().apply {
                put("read", 1)
                put("seen", 1)
            }
            if (threadId >= 0) {
                context.contentResolver.update(
                    Telephony.Sms.CONTENT_URI,
                    values,
                    "thread_id=? AND read=0",
                    arrayOf(threadId.toString()),
                )
                context.contentResolver.update(
                    Telephony.Mms.CONTENT_URI,
                    values,
                    "thread_id=? AND read=0",
                    arrayOf(threadId.toString()),
                )
            } else if (address != null) {
                context.contentResolver.update(
                    Telephony.Sms.CONTENT_URI,
                    values,
                    "address=? AND read=0",
                    arrayOf(address),
                )
            }
            Notifications.cancel(context, notificationId)
        } catch (_: Exception) {
        }
    }
}
