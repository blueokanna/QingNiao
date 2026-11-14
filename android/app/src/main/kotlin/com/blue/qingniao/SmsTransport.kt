package com.blue.qingniao

import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Telephony
import android.telephony.SmsManager
import java.util.concurrent.Executors

object MessageIo {
    val executor = Executors.newSingleThreadExecutor()
    val receiverExecutor = Executors.newSingleThreadExecutor()
}

object SmsTransport {
    fun send(context: Context, store: MessageStore, address: String, body: String, subscription: Int): Long {
        require(address.matches(Regex("\\+?[0-9*#][0-9*# .()-]{0,39}"))) { "请输入有效的收件号码" }
        require(body.isNotBlank() && body.length <= 10000) { "短信正文应为 1–10000 个字符" }
        check(SmsAccess.isDefaultSmsApp(context)) { "请先设置为默认短信应用" }
        val manager = context.getSystemService(SmsManager::class.java).createForSubscriptionId(subscription)
        val parts = manager.divideMessage(body)
        require(parts.size <= 100) { "短信分段过多" }
        val uri = checkNotNull(context.contentResolver.insert(Telephony.Sms.Outbox.CONTENT_URI, ContentValues().apply {
            put("address", address); put("body", body); put("date", System.currentTimeMillis()); put("read", 1); put("sub_id", subscription); put("status", Telephony.Sms.STATUS_PENDING)
        })) { "无法写入发件箱" }
        val id = ContentUris.parseId(uri)
        android.util.Log.d("QingniaoSms", "outbox id=$id parts=${parts.size} sub=$subscription address=$address")
        try {
            store.registerOutgoing(id, parts.size)
            SmsSendWatchdog.schedule(context, id)
            fun callbacks(phase: String) = ArrayList(parts.indices.map { index ->
                val intent = Intent(context, SmsReceiptReceiver::class.java).setAction(phase)
                    .setData(Uri.parse("qingniao://receipt/$id/$phase/$index"))
                    .putExtra("id", id).putExtra("part", index)
                PendingIntent.getBroadcast(context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or if (phase == "delivered") PendingIntent.FLAG_MUTABLE else PendingIntent.FLAG_IMMUTABLE)
            })
            manager.sendMultipartTextMessage(address, null, parts, callbacks("sent"), callbacks("delivered"))
        } catch (error: Exception) {
            context.contentResolver.update(uri, ContentValues().apply { put("type", Telephony.Sms.MESSAGE_TYPE_FAILED); put("status", Telephony.Sms.STATUS_FAILED) }, null, null)
            throw error
        }
        store.saveDraft(address, "")
        return id
    }
}

class SmsReceiptReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getLongExtra("id", -1)
        val part = intent.getIntExtra("part", -1)
        val phase = intent.action ?: return
        if (id < 0 || part < 0) return
        val deliveryStatus = if (phase == "delivered") intent.getByteArrayExtra("pdu")?.let { android.telephony.SmsMessage.createFromPdu(it, intent.getStringExtra("format") ?: "3gpp")?.status } else null
        if (phase == "delivered" && (deliveryStatus == null || deliveryStatus in 32..63)) return
        val success = if (phase == "delivered") deliveryStatus!! < 32 else resultCode == Activity.RESULT_OK
        val pending = goAsync()
        MessageIo.receiverExecutor.execute {
            try {
                MessageStore(context).use { store ->
                    val state = store.receipt(id, part, phase, success) ?: return@use
                    android.util.Log.d("QingniaoSms", "receipt id=$id part=$part phase=$phase success=$success type=$state")
                    if (phase == "sent") SmsSendWatchdog.cancel(context, id)
                    val values = ContentValues()
                    if (phase == "sent") values.put("type", state)
                    if (phase == "delivered") values.put("status", if (state == 2) Telephony.Sms.STATUS_COMPLETE else Telephony.Sms.STATUS_FAILED)
                    context.contentResolver.update(ContentUris.withAppendedId(Telephony.Sms.CONTENT_URI, id), values, null, null)
                }
            } catch (_: Exception) {
                MessageNotifications.show(context, "", "短信状态更新失败，请检查系统消息记录", id.toInt())
            } finally { pending.finish() }
        }
    }
}
