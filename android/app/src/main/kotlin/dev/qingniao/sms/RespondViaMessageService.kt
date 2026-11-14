package dev.qingniao.sms

import android.app.Service
import android.content.Intent
import android.os.IBinder
import android.telephony.SubscriptionManager

class RespondViaMessageService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val address = intent?.data?.schemeSpecificPart?.substringBefore('?')
        val body = intent?.getStringExtra(Intent.EXTRA_TEXT)
        if (intent?.action == Intent.ACTION_RESPOND_VIA_MESSAGE && address != null && body != null) {
            MessageIo.executor.execute {
                try { MessageStore(this).use { SmsTransport.send(this, it, address, body, SubscriptionManager.getDefaultSmsSubscriptionId()) } }
                catch (_: Exception) { MessageNotifications.show(this, address, "快捷回复发送失败，请打开应用查看", address.hashCode()) }
                finally { stopSelf(startId) }
            }
        } else stopSelf(startId)
        return START_NOT_STICKY
    }
}
