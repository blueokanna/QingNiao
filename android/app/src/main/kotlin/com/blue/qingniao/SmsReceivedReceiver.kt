package com.blue.qingniao

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import android.util.Log

/** SMS_RECEIVED is notification-only: the default SMS app owns provider persistence. */
class SmsReceivedReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        if (SmsAccess.isDefaultSmsApp(context)) return
        val message = decodeIncomingSms(context, intent) ?: return
        if (message.body.isEmpty()) return
        val app = context.applicationContext
        val completion = SmsBroadcastCompletion(goAsync())
        try {
            MessageIo.notificationExecutor.execute {
                try {
                    if (!SmsAccess.isDefaultSmsApp(app)) {
                        Notifications.showSms(app, message.address, message.body, message.subscriptionId, -1L)
                    }
                } catch (error: Exception) {
                    Log.w("IncomingSms", "SMS notification unavailable: ${error.javaClass.simpleName}")
                } finally {
                    completion.finish()
                }
            }
        } catch (error: Exception) {
            Log.w("IncomingSms", "SMS notification queue unavailable: ${error.javaClass.simpleName}")
            completion.finish()
        }
    }
}
