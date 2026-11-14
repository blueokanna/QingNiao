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

    fun markReplied(context: Context, address: String, notificationId: Int) {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.cancel(notificationId)
        Handler(Looper.getMainLooper()).post {
            Toast.makeText(context, "已回复 $address", Toast.LENGTH_SHORT).show()
        }
    }

    fun cancel(context: Context, notificationId: Int) {
        context.getSystemService(NotificationManager::class.java).cancel(notificationId)
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
