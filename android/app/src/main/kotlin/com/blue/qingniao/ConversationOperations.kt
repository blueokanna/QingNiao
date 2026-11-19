package com.blue.qingniao

import android.app.NotificationManager
import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.provider.Telephony

class ConversationOperations(private val context: Context) {
    private val resolver = context.contentResolver

    fun markRead(ids: List<Long>?): Int {
        var changed = 0
        for (chunk in ids?.chunked(300) ?: listOf(null)) {
            val where = if (chunk == null) "read=0" else "read=0 AND thread_id IN (${chunk.joinToString { "?" }})"
            val args = chunk?.map(Long::toString)?.toTypedArray()
            for (uri in listOf(Telephony.Sms.CONTENT_URI, Telephony.Mms.CONTENT_URI)) {
                changed += resolver.update(uri, ContentValues().apply { put("read", 1); put("seen", 1) }, where, args)
            }
            if (chunk != null) {
                resolver.query(Telephony.Sms.CONTENT_URI, arrayOf("address"),
                    "thread_id IN (${chunk.joinToString { "?" }})", args, null)?.use { cursor ->
                    val addresses = mutableSetOf<String>()
                    while (cursor.moveToNext()) cursor.getString(0)?.let(addresses::add)
                    addresses.forEach { Notifications.cancelForAddress(context, it) }
                }
            }
        }
        if (ids == null) {
            val manager = context.getSystemService(NotificationManager::class.java)
            manager.activeNotifications.filter { it.notification.group == Notifications.GROUP }
                .forEach { Notifications.cancel(context, it.id, it.tag) }
        }
        return changed
    }

    fun moveToTrash(store: AuroraStore, ids: List<Long>): Int {
        var changed = 0
        val now = System.currentTimeMillis()
        val db = store.writableDatabase
        db.beginTransaction()
        try {
            for (chunk in ids.chunked(300)) {
                val where = "thread_id IN (${chunk.joinToString { "?" }})"
                val args = chunk.map(Long::toString).toTypedArray()
                resolver.query(Telephony.Sms.CONTENT_URI,
                    arrayOf("_id", "thread_id", "address", "body", "date"), where, args, null)?.use { cursor ->
                    while (cursor.moveToNext()) {
                        store.hide(AuroraStore.Trash(MessageIdentity.sms(cursor.getLong(0)), cursor.getLong(1),
                            cursor.getString(2).orEmpty(), cursor.getString(3).orEmpty(), cursor.getLong(4), now, 0))
                        changed++
                    }
                }
                resolver.query(Telephony.Mms.CONTENT_URI,
                    arrayOf("_id", "thread_id", "sub", "date"), where, args, null)?.use { cursor ->
                    while (cursor.moveToNext()) {
                        store.hide(AuroraStore.Trash(MessageIdentity.mms(cursor.getLong(0)), cursor.getLong(1),
                            "MMS", cursor.getString(2).orEmpty(), cursor.getLong(3) * 1000, now, 1))
                        changed++
                    }
                }
            }
            db.setTransactionSuccessful()
        } finally { db.endTransaction() }
        return changed
    }

    fun copyText(store: AuroraStore, ids: List<Long>): String {
        val text = StringBuilder()
        val hidden = store.hiddenIds()
        fun append(address: String, body: String) {
            require(text.length + address.length + body.length < 120_000) { "Selection is too large to copy. Select fewer conversations." }
            if (text.isNotEmpty()) text.append("\n\n")
            text.append(address).append(":\n").append(body)
        }
        for (chunk in ids.chunked(300)) {
            val where = "thread_id IN (${chunk.joinToString { "?" }})"
            val args = chunk.map(Long::toString).toTypedArray()
            resolver.query(Telephony.Sms.CONTENT_URI, arrayOf("_id", "address", "body"), where, args, "date ASC")?.use { cursor ->
                while (cursor.moveToNext()) if (cursor.getLong(0) !in hidden) {
                    append(cursor.getString(1).orEmpty(), cursor.getString(2).orEmpty())
                }
            }
            resolver.query(Telephony.Mms.CONTENT_URI, arrayOf("_id"), where, args, "date ASC")?.use { cursor ->
                while (cursor.moveToNext()) {
                    val id = cursor.getLong(0)
                    if (MessageIdentity.mms(id) in hidden) continue
                    resolver.query(Uri.parse("content://mms/part"), arrayOf("text"),
                        "mid=? AND ct=?", arrayOf(id.toString(), "text/plain"), null)?.use { part ->
                        while (part.moveToNext()) part.getString(0)?.let { append("MMS", it) }
                    }
                }
            }
        }
        return text.toString()
    }

    companion object {
        fun threadIds(values: List<Number>?): List<Long> {
            require(values != null && values.isNotEmpty() && values.size <= 10_000)
            return values.map { it.toLong().also { id -> require(id > 0) } }.distinct()
        }
    }
}
