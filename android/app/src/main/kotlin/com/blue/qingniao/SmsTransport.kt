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
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

object MessageIo {
    private fun worker(name: String) = ThreadPoolExecutor(
        0, 1, 30, TimeUnit.SECONDS, LinkedBlockingQueue(),
        { task -> Thread(task, name) },
    )

    val executor = worker("message-io")
    val receiverExecutor = worker("message-receipts")
    internal val smsSendExecutor = worker("sms-send")
    // Never queue the durable SMS handoff behind MMS transfer, provider queries or replies.
    internal val smsIntakeExecutor = worker("sms-intake")
    internal val smsDeliveryExecutor = worker("sms-delivery")
    internal val notificationExecutor = ThreadPoolExecutor(
        0, 1, 30, TimeUnit.SECONDS, ArrayBlockingQueue<Runnable>(32),
        { task -> Thread(task, "message-notifications") },
    )
}

object SmsTransport {
    fun send(context: Context, store: MessageStore, address: String, body: String, subscription: Int): Long {
        require(address.matches(Regex("\\+?[0-9*#][0-9*# .()-]{0,39}"))) { "Enter a valid recipient number" }
        require(body.isNotBlank() && body.length <= 10000) { "Message text must contain 1–10000 characters" }
        check(SmsAccess.isDefaultSmsApp(context)) { "Set this app as the default SMS app" }
        val selectedSubscription = SimSubscriptions.outgoingId(context, subscription)
        val destination = android.telephony.PhoneNumberUtils.stripSeparators(address)
        val manager = context.getSystemService(SmsManager::class.java).createForSubscriptionId(selectedSubscription)
        val parts = manager.divideMessage(body)
        require(parts.size <= 100) { "Too many message segments" }
        val uri = checkNotNull(context.contentResolver.insert(Telephony.Sms.Outbox.CONTENT_URI, ContentValues().apply {
            put("address", destination); put("body", body); put("date", System.currentTimeMillis()); put("read", 1); put("sub_id", selectedSubscription); put("status", Telephony.Sms.STATUS_PENDING)
        })) { "Unable to write to the outbox" }
        val id = ContentUris.parseId(uri)
        android.util.Log.d("QingniaoSms", "outbox id=$id parts=${parts.size} sub=$selectedSubscription")
        try {
            store.registerOutgoing(id, parts.size)
            SmsSendWatchdog.schedule(context, id)
            fun callbacks(phase: String) = ArrayList(parts.indices.map { index ->
                val intent = Intent(context, SmsReceiptReceiver::class.java).setAction(phase)
                    .setData(Uri.parse("qingniao://receipt/$id/$phase/$index"))
                    .putExtra("id", id).putExtra("part", index)
                // Telephony supplies result details/PDU via fill-in extras; the component is explicit.
                PendingIntent.getBroadcast(context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE)
            })
            val sent = callbacks("sent")
            val delivered = callbacks("delivered")
            if (parts.size == 1) manager.sendTextMessage(destination, null, parts.first(), sent.first(), delivered.first())
            else manager.sendMultipartTextMessage(destination, null, parts, sent, delivered)
        } catch (error: Exception) {
            context.contentResolver.update(uri, ContentValues().apply { put("type", Telephony.Sms.MESSAGE_TYPE_FAILED); put("status", Telephony.Sms.STATUS_FAILED) }, null, null)
            SmsSendWatchdog.cancel(context, id)
            store.forgetOutgoing(id)
            throw error
        }
        // A draft cleanup failure must not report an accepted send as failed and invite duplicates.
        runCatching { store.saveDraft(address, "") }
        return id
    }
}

class SmsReceiptReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getLongExtra("id", -1)
        val part = intent.getIntExtra("part", -1)
        val phase = intent.action ?: return
        if (id < 0 || part < 0 || phase !in setOf("sent", "delivered")) return
        val deliveryStatus = if (phase == "delivered") intent.getByteArrayExtra("pdu")?.let { android.telephony.SmsMessage.createFromPdu(it, intent.getStringExtra("format") ?: "3gpp")?.status } else null
        if (phase == "delivered" && (deliveryStatus == null || deliveryStatus in 32..63)) return
        val success = if (phase == "delivered") deliveryStatus!! < 32 else resultCode == Activity.RESULT_OK
        val errorCode = intent.getIntExtra("errorCode", resultCode)
        val pending = goAsync()
        MessageIo.receiverExecutor.execute {
            try {
                MessageStore(context).use { store ->
                    val state = store.receipt(id, part, phase, success) ?: return@use
                    android.util.Log.d("QingniaoSms", "receipt id=$id part=$part phase=$phase success=$success type=$state")
                    val values = ContentValues()
                    if (phase == "sent") {
                        values.put("type", state)
                        if (state == Telephony.Sms.MESSAGE_TYPE_FAILED) {
                            values.put("status", Telephony.Sms.STATUS_FAILED)
                            if (!success) values.put("error_code", errorCode)
                        } else {
                            // A late successful send receipt can correct a watchdog timeout.
                            values.put("status", store.receiptState(id, "delivered")?.let {
                                if (it == Telephony.Sms.MESSAGE_TYPE_SENT) Telephony.Sms.STATUS_COMPLETE else Telephony.Sms.STATUS_FAILED
                            } ?: Telephony.Sms.STATUS_PENDING)
                            values.put("error_code", 0)
                        }
                    }
                    if (phase == "delivered") {
                        values.put("status", if (state == 2) Telephony.Sms.STATUS_COMPLETE else Telephony.Sms.STATUS_FAILED)
                        if (state == 2) values.put("type", Telephony.Sms.MESSAGE_TYPE_SENT)
                    }
                    val updated = context.contentResolver.update(ContentUris.withAppendedId(Telephony.Sms.CONTENT_URI, id), values, null, null)
                    // Keep recovery armed until the provider actually contains the terminal state.
                    if ((phase == "sent" || state == 2) && updated > 0) SmsSendWatchdog.cancel(context, id)
                }
            } catch (_: Exception) {
                MessageNotifications.show(context, "", "Unable to update message status. Check system messages.", id.toInt())
            } finally { pending.finish() }
        }
    }
}
