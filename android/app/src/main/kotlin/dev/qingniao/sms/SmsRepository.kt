package dev.qingniao.sms

import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.provider.Telephony

class SmsRepository(private val context: Context, private val store: MessageStore) {
    private val resolver get() = context.contentResolver
    fun messages(thread: Long?, before: Long = Long.MAX_VALUE, limit: Int = 100, trash: Boolean = false): List<Map<String, Any?>> {
        val hidden = store.hiddenIds()
        val selection = if (thread == null) "_id < ?" else "thread_id=? AND _id < ?"
        val args = if (thread == null) arrayOf(before.toString()) else arrayOf(thread.toString(), before.toString())
        return resolver.query(Telephony.Sms.CONTENT_URI, arrayOf("_id", "thread_id", "address", "body", "date", "type", "read", "sub_id", "status"), selection, args, "_id DESC")?.use { cursor ->
            buildList {
                while (cursor.moveToNext() && size < limit) {
                    val id = cursor.getLong(0)
                    if ((id in hidden) != trash) continue
                    add(mapOf("id" to id, "threadId" to cursor.getLong(1), "address" to (cursor.getString(2) ?: "未知号码"), "body" to (cursor.getString(3) ?: ""), "date" to cursor.getLong(4), "type" to cursor.getInt(5), "read" to (cursor.getInt(6) != 0), "subscriptionId" to cursor.getInt(7), "status" to cursor.getInt(8)))
                }
            }
        } ?: emptyList()
    }
    fun conversations(query: String = ""): List<Map<String, Any?>> {
        val hidden = store.hiddenIds()
        val threads = linkedMapOf<Long, MutableMap<String, Any?>>()
        val matches = mutableSetOf<Long>()
        resolver.query(Telephony.Sms.CONTENT_URI, arrayOf("_id", "thread_id", "address", "body", "date", "read", "sub_id"), null, null, "date DESC, _id DESC")?.use { cursor ->
            while (cursor.moveToNext()) {
                if (cursor.getLong(0) in hidden) continue
                val thread = cursor.getLong(1)
                if (query.isEmpty() || (cursor.getString(2) ?: "").contains(query, ignoreCase = true) || (cursor.getString(3) ?: "").contains(query, ignoreCase = true)) matches.add(thread)
                val conversation = threads.getOrPut(thread) { mutableMapOf("threadId" to thread, "address" to (cursor.getString(2) ?: "未知号码"), "body" to (cursor.getString(3) ?: ""), "date" to cursor.getLong(4), "subscriptionId" to cursor.getInt(6), "unread" to 0) }
                if (cursor.getInt(5) == 0) conversation["unread"] = (conversation["unread"] as Int) + 1
            }
        }
        return threads.filterKeys { it in matches }.values.toList()
    }
    fun markRead(thread: Long) {
        resolver.update(Telephony.Sms.CONTENT_URI, ContentValues().apply { put("read", 1); put("seen", 1) }, "thread_id=? AND read=0", arrayOf(thread.toString()))
    }
    fun delete(id: Long) {
        require(id in store.hiddenIds()) { "Message must be in trash" }
        resolver.delete(ContentUris.withAppendedId(Telephony.Sms.CONTENT_URI, id), null, null)
        store.restore(id)
    }
}
