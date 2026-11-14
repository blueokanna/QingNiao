package com.blue.qingniao

import android.content.Context
import android.net.Uri
import android.provider.Telephony

class MmsRepository(private val context: Context) {
    fun messages(before: Long): List<Map<String, Any?>> {
        val resolver = context.contentResolver
        return resolver.query(Telephony.Mms.CONTENT_URI, arrayOf("_id", "date", "msg_box", "sub", "m_type", "read"), "_id<?", arrayOf(before.toString()), "_id DESC")?.use { cursor ->
            buildList {
                while (cursor.moveToNext() && size < 50) {
                    val id = cursor.getLong(0)
                    val recipients = resolver.query(Uri.parse("content://mms/$id/addr"), arrayOf("address"), "address<>?", arrayOf("insert-address-token"), null)?.use { addresses -> buildList { while (addresses.moveToNext()) add(addresses.getString(0) ?: "") }.distinct() }.orEmpty()
                    val text = StringBuilder()
                    val attachments = mutableListOf<Map<String, String>>()
                    resolver.query(Uri.parse("content://mms/$id/part"), arrayOf("_id", "ct", "text", "cl"), null, null, null)?.use { parts ->
                        while (parts.moveToNext()) {
                            val type = parts.getString(1) ?: "application/octet-stream"
                            if (type == "text/plain") { if (text.isNotEmpty()) text.append('\n'); text.append(parts.getString(2) ?: "") }
                            else if (type != "application/smil") attachments.add(mapOf("id" to parts.getString(0), "type" to type, "name" to (parts.getString(3) ?: "Attachment")))
                        }
                    }
                    add(mapOf("id" to id, "date" to cursor.getLong(1) * 1000, "type" to cursor.getInt(2), "subject" to (cursor.getString(3) ?: ""), "pending" to (cursor.getInt(4) == 130), "address" to recipients.joinToString(", "), "body" to text.toString(), "attachments" to attachments))
                }
            }
        } ?: emptyList()
    }
    fun image(part: Long): ByteArray {
        val uri = Uri.parse("content://mms/part/$part")
        val type = context.contentResolver.query(uri, arrayOf("ct"), null, null, null)?.use { if (it.moveToFirst()) it.getString(0) else null }
        require(type in setOf("image/jpeg", "image/png", "image/webp", "image/gif")) { "Preview is unavailable for this attachment type" }
        return requireNotNull(context.contentResolver.openInputStream(uri)).use { input ->
            val output = java.io.ByteArrayOutputStream()
            val buffer = ByteArray(16384)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                require(output.size() + count <= 5 * 1024 * 1024) { "Image exceeds the preview limit" }
                output.write(buffer, 0, count)
            }
            output.toByteArray()
        }
    }
}
