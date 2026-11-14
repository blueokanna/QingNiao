package com.blue.qingniao

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import android.telephony.SubscriptionManager

/**
 * 非默认短信应用也会收到 SMS_RECEIVED 有序广播。
 *
 * 这条接收器保证：即使青鸟不是默认短信应用、进程被杀，短信到达时系统仍会启动
 * 本进程并立刻发通知。默认短信应用走 SMS_DELIVER，避免重复提醒。
 *
 * 这里不写系统短信库（非默认应用没有写权限），正文由系统默认短信应用写入；
 * 用户点通知进入青鸟后即可从系统库读取。
 */
class SmsReceivedReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        if (Telephony.Sms.getDefaultSmsPackage(context) == context.packageName) return
        val parts = Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return
        if (parts.isEmpty()) return
        val address = parts.first().originatingAddress ?: "未知号码"
        val body = parts.joinToString("") { it.messageBody ?: "" }
        if (body.isEmpty()) return
        val subscription = intent.getIntExtra(
            SubscriptionManager.EXTRA_SUBSCRIPTION_INDEX,
            intent.getIntExtra("subscription", -1),
        )
        // 先发通知，再考虑任何持久化；短信到达路径上不引入额外等待。
        try {
            Notifications.showSms(context, address, body, subscription, -1L)
        } catch (_: Exception) {
            // 权限或通知被关闭时静默失败。
        }
    }
}
