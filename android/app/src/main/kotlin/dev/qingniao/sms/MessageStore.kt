package dev.qingniao.sms

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

class MessageStore(context: Context) : SQLiteOpenHelper(context, "message_state.db", null, 1) {
    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL("CREATE TABLE drafts (address TEXT PRIMARY KEY, body TEXT NOT NULL)")
        db.execSQL("CREATE TABLE hidden (id INTEGER PRIMARY KEY, deleted_at INTEGER NOT NULL)")
        db.execSQL("CREATE TABLE receipts (message_id INTEGER NOT NULL, part INTEGER NOT NULL, phase TEXT NOT NULL, success INTEGER NOT NULL, PRIMARY KEY(message_id,part,phase))")
        db.execSQL("CREATE TABLE outgoing (message_id INTEGER PRIMARY KEY, parts INTEGER NOT NULL)")
    }
    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit
    fun hiddenIds(): Set<Long> = readableDatabase.rawQuery("SELECT id FROM hidden", null).use { cursor ->
        buildSet { while (cursor.moveToNext()) add(cursor.getLong(0)) }
    }
    fun hide(id: Long) { writableDatabase.execSQL("INSERT OR REPLACE INTO hidden VALUES (?,?)", arrayOf(id, System.currentTimeMillis())) }
    fun restore(id: Long) { writableDatabase.delete("hidden", "id=?", arrayOf(id.toString())) }
    fun draft(address: String): String = readableDatabase.rawQuery("SELECT body FROM drafts WHERE address=?", arrayOf(address)).use { if (it.moveToFirst()) it.getString(0) else "" }
    fun saveDraft(address: String, body: String) {
        if (body.isEmpty()) writableDatabase.delete("drafts", "address=?", arrayOf(address))
        else writableDatabase.execSQL("INSERT OR REPLACE INTO drafts VALUES (?,?)", arrayOf(address, body))
    }
    fun registerOutgoing(id: Long, parts: Int) { writableDatabase.execSQL("INSERT INTO outgoing VALUES (?,?)", arrayOf(id, parts)) }
    fun receipt(id: Long, part: Int, phase: String, success: Boolean): Int? {
        val db = writableDatabase
        val count = db.rawQuery("SELECT parts FROM outgoing WHERE message_id=?", arrayOf(id.toString())).use { if (it.moveToFirst()) it.getInt(0) else return null }
        if (part !in 0 until count || phase !in setOf("sent", "delivered")) return null
        db.execSQL("INSERT OR IGNORE INTO receipts VALUES (?,?,?,?)", arrayOf(id, part, phase, if (success) 1 else 0))
        return db.rawQuery("SELECT COUNT(*), MIN(success) FROM receipts WHERE message_id=? AND phase=?", arrayOf(id.toString(), phase)).use {
            it.moveToFirst()
            if (it.getInt(1) == 0) 5 else if (it.getInt(0) == count) 2 else null
        }
    }
}
