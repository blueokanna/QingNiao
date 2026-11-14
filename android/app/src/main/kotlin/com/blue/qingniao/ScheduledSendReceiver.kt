package com.blue.qingniao

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import android.telephony.SubscriptionManager

class ScheduledSendReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getLongExtra("id", -1)
        if (id < 0) return
        val pending = goAsync()
        MessageIo.receiverExecutor.execute {
            try {
                AuroraStore(context).use { store ->
                    val row = store.scheduled(id) ?: return@use
                    if (row.at > System.currentTimeMillis()) {
                        ScheduledMessageAlarms.arm(context, row.id, row.at)
                        return@use
                    }
                    if (!SmsAccess.isDefaultSmsApp(context)) {
                        MessageNotifications.show(context, row.address, "Scheduled message not sent: this app is not the default SMS app", 8100 + id.toInt())
                        return@use
                    }
                    try {
                        val subscription = if (row.subId >= 0) row.subId else SubscriptionManager.getDefaultSmsSubscriptionId()
                        MessageStore(context).use { messages ->
                            SmsTransport.send(context, messages, row.address, row.body, subscription)
                        }
                        store.cancelScheduled(id)
                    } catch (_: Exception) {
                        MessageNotifications.show(context, row.address, "Scheduled message failed. Retry in the conversation.", 8100 + id.toInt())
                    }
                }
            } catch (_: Exception) {
            } finally {
                pending.finish()
            }
        }
    }
}
