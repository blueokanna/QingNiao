package com.blue.qingniao

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import android.telephony.SubscriptionManager


class SmsReceivedReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        if (SmsAccess.isDefaultSmsApp(context)) return
        val parts = Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return
        if (parts.isEmpty()) return
        val address = parts.first().originatingAddress ?: "Unknown number"
        val body = parts.joinToString("") { it.messageBody ?: "" }
        if (body.isEmpty()) return
        val subscription = intent.getIntExtra(
            SubscriptionManager.EXTRA_SUBSCRIPTION_INDEX,
            intent.getIntExtra("subscription", -1),
        )
        try {
            Notifications.showSms(context, address, body, subscription, -1L)
        } catch (_: Exception) {
        }
    }
}
