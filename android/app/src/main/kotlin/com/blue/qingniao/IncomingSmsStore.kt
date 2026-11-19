package com.blue.qingniao

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

/** Private, backup-excluded journal. Pending message bodies are never evicted on retry failure. */
internal class IncomingSmsStore(context: Context) : SQLiteOpenHelper(context, "incoming_sms.db", null, 2) {
    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL("""
            CREATE TABLE incoming_sms (
                receipt_key TEXT PRIMARY KEY,
                address TEXT, body TEXT,
                received_at INTEGER NOT NULL, sent_at INTEGER NOT NULL,
                sub_id INTEGER NOT NULL, service_center TEXT,
                protocol INTEGER NOT NULL, reply_path INTEGER NOT NULL,
                attempted_at INTEGER NOT NULL DEFAULT 0,
                completed_at INTEGER
            )
        """.trimIndent())
        createPendingIndex(db)
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        if (oldVersion < 2) createPendingIndex(db)
    }

    private fun createPendingIndex(db: SQLiteDatabase) {
        db.execSQL("CREATE INDEX IF NOT EXISTS incoming_sms_pending " +
            "ON incoming_sms(completed_at,attempted_at,received_at)")
    }

    fun enqueue(message: IncomingSms) {
        val db = writableDatabase
        db.beginTransaction()
        try {
            val exists = db.rawQuery("SELECT 1 FROM incoming_sms WHERE receipt_key=?", arrayOf(message.key))
                .use { it.moveToFirst() }
            if (!exists) {
                db.insertOrThrow("incoming_sms", null, ContentValues().apply {
                    put("receipt_key", message.key)
                    put("address", message.address)
                    put("body", message.body)
                    put("received_at", message.receivedAt)
                    put("sent_at", message.sentAt)
                    put("sub_id", message.subscriptionId)
                    put("service_center", message.serviceCenter)
                    put("protocol", message.protocol)
                    put("reply_path", if (message.replyPathPresent) 1 else 0)
                })
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    fun pending(limit: Int): List<IncomingSms> = readableDatabase.rawQuery(
        "SELECT receipt_key,address,body,received_at,sent_at,sub_id,service_center,protocol,reply_path " +
            "FROM incoming_sms WHERE completed_at IS NULL ORDER BY attempted_at,received_at LIMIT ?",
        arrayOf(limit.toString()),
    ).use { cursor -> buildList { while (cursor.moveToNext()) add(cursor.message()) } }

    fun hasPending(): Boolean = readableDatabase.rawQuery(
        "SELECT 1 FROM incoming_sms WHERE completed_at IS NULL LIMIT 1", null,
    ).use { it.moveToFirst() }

    fun hasUnattempted(): Boolean = readableDatabase.rawQuery(
        "SELECT 1 FROM incoming_sms WHERE completed_at IS NULL AND attempted_at=0 LIMIT 1", null,
    ).use { it.moveToFirst() }

    fun attempted(key: String) {
        writableDatabase.update("incoming_sms", ContentValues().apply {
            put("attempted_at", System.currentTimeMillis())
        }, "receipt_key=?", arrayOf(key))
    }

    fun complete(key: String) {
        writableDatabase.update("incoming_sms", ContentValues().apply {
            putNull("address")
            putNull("body")
            putNull("service_center")
            put("completed_at", System.currentTimeMillis())
        }, "receipt_key=?", arrayOf(key))
    }

    fun pruneReceipts() {
        val db = writableDatabase
        db.delete("incoming_sms", "completed_at IS NOT NULL AND completed_at<?",
            arrayOf((System.currentTimeMillis() - 7 * 24 * 60 * 60 * 1000L).toString()))
        db.execSQL("DELETE FROM incoming_sms WHERE receipt_key IN (" +
            "SELECT receipt_key FROM incoming_sms WHERE completed_at IS NOT NULL " +
            "ORDER BY completed_at DESC LIMIT -1 OFFSET 1024)")
    }

    private fun Cursor.message() = IncomingSms(
        getString(0), getString(1), getString(2), getLong(3), getLong(4), getInt(5),
        getString(6), getInt(7), getInt(8) != 0,
    )
}
