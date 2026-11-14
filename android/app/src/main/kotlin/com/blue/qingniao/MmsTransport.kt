package com.blue.qingniao

import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Telephony
import android.telephony.SmsManager
import android.telephony.SubscriptionManager
import com.google.android.mms.pdu_alt.*
import java.io.File
import java.util.UUID

object MmsTransport {
    private const val MAX_BYTES = 5 * 1024 * 1024
    private fun file(context: Context, token: String): File {
        require(token.matches(Regex("[a-f0-9-]{36}")))
        return File(File(context.filesDir, "mms_transfers").apply { mkdirs() }, "$token.pdu")
    }
    private fun uri(context: Context, token: String) = Uri.parse("content://${context.packageName}.transfers/$token.pdu")
    private fun manager(context: Context, subscription: Int) = context.getSystemService(SmsManager::class.java).createForSubscriptionId(subscription)
    fun receive(context: Context, data: ByteArray, subscription: Int) {
        require(data.size <= MAX_BYTES)
        val notification = PduParser(data).parse() as? NotificationInd ?: return
        val location = notification.contentLocation?.toString(Charsets.ISO_8859_1) ?: return
        require(Uri.parse(location).scheme in setOf("http", "https"))
        val saved = PduPersister.getPduPersister(context).persist(notification, Telephony.Mms.Inbox.CONTENT_URI, true, true, null, subscription)
        val token = UUID.randomUUID().toString()
        val prefs = context.getSharedPreferences("mms_pending", Context.MODE_PRIVATE)
        check(prefs.edit().putString("$token.location", location).putString("$token.notification", saved.toString()).putInt("$token.subscription", subscription).commit())
        download(context, token)
    }
    fun download(context: Context, token: String) {
        val prefs = context.getSharedPreferences("mms_pending", Context.MODE_PRIVATE)
        val location = prefs.getString("$token.location", null) ?: return
        if (System.currentTimeMillis() - prefs.getLong("$token.active", 0) < 120000) return
        val subscription = prefs.getInt("$token.subscription", -1)
        file(context, token).delete()
        check(prefs.edit().putLong("$token.active", System.currentTimeMillis()).commit())
        try { manager(context, subscription).downloadMultimediaMessage(context, location, uri(context, token), null, callback(context, token, "download")) }
        catch (error: Exception) { prefs.edit().remove("$token.active").commit(); throw error }
    }
    private fun callback(context: Context, token: String, phase: String): PendingIntent = PendingIntent.getBroadcast(context, 0,
        Intent(context, MmsResultReceiver::class.java).setAction(phase).setData(Uri.parse("qingniao://mms/$token/$phase")).putExtra("token", token), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    fun complete(context: Context, token: String, phase: String, success: Boolean) {
        val prefs = context.getSharedPreferences("mms_pending", Context.MODE_PRIVATE)
        if (phase == "send") {
            val message = prefs.getString("$token.message", null) ?: return
            context.contentResolver.update(Uri.parse(message), ContentValues().apply { put("msg_box", if (success) 2 else 5) }, null, null)
            prefs.edit().remove("$token.message").commit()
            file(context, token).delete()
            if (!success) MessageNotifications.show(context, "", "彩信发送失败", token.hashCode())
            return
        }
        if (!prefs.contains("$token.location")) return
        prefs.edit().remove("$token.active").commit()
        if (!success) {
            MessageNotifications.show(context, "", "彩信下载失败，请在彩信页面重试", token.hashCode())
            return
        }
        val source = file(context, token)
        check(source.length() in 1..MAX_BYTES.toLong()) { "Invalid MMS size" }
        val pdu = PduParser(source.readBytes()).parse() as? MultimediaMessagePdu ?: error("Invalid MMS PDU")
        val saved = PduPersister.getPduPersister(context).persist(pdu, Telephony.Mms.Inbox.CONTENT_URI, true, true, null, prefs.getInt("$token.subscription", -1))
        checkNotNull(saved)
        context.contentResolver.update(saved, ContentValues().apply { put("read", 0); put("seen", 0) }, null, null)
        prefs.getString("$token.notification", null)?.let { context.contentResolver.delete(Uri.parse(it), null, null) }
        prefs.edit().remove("$token.location").remove("$token.notification").remove("$token.subscription").commit()
        source.delete()
        MessageNotifications.show(context, "", "收到新彩信", token.hashCode())
    }
    fun retry(context: Context) {
        val prefs = context.getSharedPreferences("mms_pending", Context.MODE_PRIVATE)
        prefs.all.keys.filter { it.endsWith(".location") }.forEach { download(context, it.removeSuffix(".location")) }
    }
    fun send(context: Context, recipients: List<String>, text: String, subscription: Int, attachment: Uri? = null) {
        require(recipients.isNotEmpty() && recipients.size <= 20)
        require(recipients.all { it.matches(Regex("\\+?[0-9][0-9 .()-]{0,39}")) })
        require((text.isNotBlank() || attachment != null) && text.length <= 10000)
        val sms = manager(context, subscription)
        val limit = sms.carrierConfigValues.getInt(SmsManager.MMS_CONFIG_MAX_MESSAGE_SIZE, 300 * 1024).coerceIn(1024, MAX_BYTES)
        val content = PduBody()
        if (text.isNotEmpty()) content.addPart(PduPart().apply { contentType = "text/plain".toByteArray(); contentLocation = "message.txt".toByteArray(); charset = CharacterSets.UTF_8; data = text.toByteArray() })
        if (attachment != null) {
            require(attachment.scheme == "content")
            val type = requireNotNull(context.contentResolver.getType(attachment))
            require(listOf("image/", "audio/", "video/").any(type::startsWith))
            val bytes = requireNotNull(context.contentResolver.openInputStream(attachment)).use { input ->
                val output = java.io.ByteArrayOutputStream()
                val buffer = ByteArray(16384)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    require(output.size() + count <= limit) { "附件超过运营商彩信大小限制" }
                    output.write(buffer, 0, count)
                }
                output.toByteArray()
            }
            content.addPart(PduPart().apply { contentType = type.toByteArray(); contentLocation = "attachment".toByteArray(); data = bytes })
            val tag = when { type.startsWith("image/") -> "img"; type.startsWith("audio/") -> "audio"; else -> "video" }
            val smil = "<smil><body><par><text src=\"message.txt\"/><$tag src=\"attachment\"/></par></body></smil>"
            content.addPart(0, PduPart().apply { contentType = "application/smil".toByteArray(); contentLocation = "smil.xml".toByteArray(); data = smil.toByteArray() })
        }
        val request = SendReq().apply {
            prepareFromAddress(context, null, subscription)
            recipients.forEach { addTo(EncodedStringValue(it)) }
            date = System.currentTimeMillis() / 1000
            setDeliveryReport(PduHeaders.VALUE_NO)
            setReadReport(PduHeaders.VALUE_NO)
            body = content
        }
        val bytes = checkNotNull(PduComposer(context, request).make())
        require(bytes.size <= limit) { "彩信超过运营商大小限制" }
        val token = UUID.randomUUID().toString()
        file(context, token).writeBytes(bytes)
        val saved = checkNotNull(PduPersister.getPduPersister(context).persist(request, Telephony.Mms.Outbox.CONTENT_URI, true, true, null, subscription))
        check(context.getSharedPreferences("mms_pending", Context.MODE_PRIVATE).edit().putString("$token.message", saved.toString()).commit())
        try { sms.sendMultimediaMessage(context, uri(context, token), null, null, callback(context, token, "send")) }
        catch (error: Exception) { complete(context, token, "send", false); throw error }
    }
}

class IncomingMmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.WAP_PUSH_DELIVER_ACTION) return
        val data = intent.getByteArrayExtra("data") ?: return
        val subscription = intent.getIntExtra(SubscriptionManager.EXTRA_SUBSCRIPTION_INDEX, intent.getIntExtra("subscription", -1))
        val pending = goAsync()
        MessageIo.receiverExecutor.execute {
            try { MmsTransport.receive(context, data, subscription) }
            catch (_: Exception) { MessageNotifications.show(context, "", "彩信接收未完成，请打开应用检查", 9021) }
            finally { pending.finish() }
        }
    }
}

class MmsResultReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val token = intent.getStringExtra("token") ?: return
        val phase = intent.action ?: return
        val success = resultCode == Activity.RESULT_OK
        val pending = goAsync()
        MessageIo.receiverExecutor.execute {
            try { MmsTransport.complete(context, token, phase, success) }
            catch (_: Exception) { MessageNotifications.show(context, "", "彩信处理失败，请在彩信页面重试", 9022) }
            finally { pending.finish() }
        }
    }
}
