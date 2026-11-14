package com.blue.qingniao

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import android.telephony.SubscriptionManager

/**
 * 定时短信到点发送。普通短信走系统 SmsManager；失败时发通知而不是静默丢弃。
 */
class ScheduledSendReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getLongExtra("id", -1)
        if (id < 0) return
        val pending = goAsync()
        MessageIo.receiverExecutor.execute {
            try {
                AuroraStore(context).use { store ->
                    val row = store.scheduled(id) ?: return@use
                    if (Telephony.Sms.getDefaultSmsPackage(context) != context.packageName) {
                        MessageNotifications.show(context, row.address, "定时短信未发送：青鸟不是默认短信应用", 8100 + id.toInt())
                        return@use
                    }
                    try {
                        val subscription = if (row.subId >= 0) row.subId else SubscriptionManager.getDefaultSmsSubscriptionId()
                        MessageStore(context).use { messages ->
                            SmsTransport.send(context, messages, row.address, row.body, subscription)
                        }
                        store.cancelScheduled(id)
                    } catch (_: Exception) {
                        MessageNotifications.show(context, row.address, "定时短信发送失败，可在会话中重发", 8100 + id.toInt())
                    }
                }
            } catch (_: Exception) {
                // 后台任务不应崩溃；下一次打开应用仍能看到待发送项。
            } finally {
                pending.finish()
            }
        }
    }
}
