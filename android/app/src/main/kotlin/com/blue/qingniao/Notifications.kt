package com.blue.qingniao

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Telephony
import android.telephony.SubscriptionManager
import android.widget.Toast

/**
 * 通知栏体验：按 SIM 分渠道、会话分组、直接回复与标记已读。
 * 通知只在本机生成；正文预览可在设置中关闭。
 */
object Notifications {
    const val KEY_REPLY = "qingniao_reply"
    const val GROUP = "com.blue.qingniao.MESSAGES"
    const val SUMMARY_ID = 4100

    fun showSms(
        context: Context,
        address: String,
        body: String,
        subscriptionId: Int,
        threadId: Long,
    ) {
        val prefs = context.getSharedPreferences("appearance", Context.MODE_PRIVATE)
        if (!prefs.getBoolean("notifications", true)) return
        val preview = prefs.getBoolean("preview", true)
        val manager = context.getSystemService(NotificationManager::class.java)
        val channelId = "messages_${subscriptionId.coerceAtLeast(0)}"
        val channel = NotificationChannel(
            channelId,
            if (subscriptionId >= 0) "短信 · SIM $subscriptionId" else "短信",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "新短信、直接回复与标记已读"
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
        val remoteInput = RemoteInputBuilder.build()
        val replyAction = Notification.Action.Builder(
            Icon.createWithResource(context, android.R.drawable.ic_menu_send),
            "回复",
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
            "标为已读",
            readPending,
        ).build()

        val text = if (preview) body else "新短信"
        val builder = Notification.Builder(context, channelId)
            .setSmallIcon(android.R.drawable.stat_notify_chat)
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
            .addAction(readAction)

        // Android 16 Live Updates：ColorOS 16 / OxygenOS 16 会把它呈现在流体云。
        // 系统与 OEM 仍可拒绝；失败时自动退回普通高优先级通知。
        if (canPromote(context) && prefs.getBoolean("fluidCloud", true)) {
            try {
                builder
                    .setOngoing(true)
                    .setAutoCancel(false)
                    .setShortCriticalText(if (preview) "新短信" else "消息")
                requestPromotedOngoing(builder)
            } catch (_: Exception) {
                // 某些 ROM 在运行时移除了该能力。
            }
        }

        val summary = Notification.Builder(context, channelId)
            .setSmallIcon(android.R.drawable.stat_notify_chat)
            .setContentTitle("青鸟短信")
            .setContentText("有新短信")
            .setGroup(GROUP)
            .setGroupSummary(true)
            .setAutoCancel(true)
            .build()
        try {
            manager.notify(id, builder.build())
            manager.notify(SUMMARY_ID, summary)
        } catch (_: SecurityException) {
            // 用户关闭通知权限时静默失败。
        }
    }

    /** 彩信下载中的低打扰进度通知；完成后由富通知替换。 */
    fun showProgress(
        context: Context,
        address: String,
        text: String,
        subscriptionId: Int,
        notificationId: Int,
    ) {
        val prefs = context.getSharedPreferences("appearance", Context.MODE_PRIVATE)
        if (!prefs.getBoolean("notifications", true)) return
        val manager = context.getSystemService(NotificationManager::class.java)
        val channelId = "messages_${subscriptionId.coerceAtLeast(0)}"
        manager.createNotificationChannel(
            NotificationChannel(
                channelId,
                if (subscriptionId >= 0) "短信 · SIM $subscriptionId" else "短信",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "新短信、彩信与直接回复"
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
            .setSmallIcon(android.R.drawable.stat_notify_chat)
            .setContentTitle(address.ifBlank { "彩信" })
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
            // 通知权限关闭时静默失败。
        }
    }

    /** Android 16 起可用的 Live Updates 能力；ColorOS 16 会桥接到流体云。 */
    fun canPromote(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < 36) return false
        return try {
            val manager = context.getSystemService(NotificationManager::class.java)
            val method = NotificationManager::class.java.getMethod("canPostPromotedNotifications")
            method.invoke(manager) as? Boolean ?: false
        } catch (_: Throwable) {
            // API 36.1 才提供该能力；36.0 会抛异常。
            false
        }
    }

    /**
     * `setRequestPromotedOngoing` 位于 Android 16.1（API 36.1），
     * 而当前 compileSdk 为 36；用反射调用，避免锁死 Preview SDK。
     */
    private fun requestPromotedOngoing(builder: Notification.Builder) {
        try {
            val method = Notification.Builder::class.java
                .getMethod("setRequestPromotedOngoing", Boolean::class.javaPrimitiveType)
            method.invoke(builder, true)
        } catch (_: Throwable) {
            // 不支持时保持普通通知。
        }
    }

    fun fluidCloudEnabled(context: Context): Boolean =
        context.getSharedPreferences("appearance", Context.MODE_PRIVATE)
            .getBoolean("fluidCloud", true) && canPromote(context)

    fun markReplied(context: Context, address: String, notificationId: Int) {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.cancel(notificationId)
        Handler(Looper.getMainLooper()).post {
            Toast.makeText(context, "已回复 $address", Toast.LENGTH_SHORT).show()
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
            // activeNotifications 在极少数 ROM 上不可用。
        }
    }
}

/** 单独抽出 RemoteInput，方便在通知与回复接收器之间共享 key。 */
private object RemoteInputBuilder {
    fun build() = android.app.RemoteInput.Builder(Notifications.KEY_REPLY)
        .setLabel("直接回复")
        .setAllowFreeFormInput(true)
        .build()
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
                check(Telephony.Sms.getDefaultSmsPackage(context) == context.packageName)
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
                    "回复失败：${error.message ?: "请打开应用重试"}",
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
            // 权限撤销时忽略。
        }
    }
}
