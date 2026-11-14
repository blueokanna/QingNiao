package com.blue.qingniao

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

class AuroraStore(context: Context) : SQLiteOpenHelper(context, "aurora.db", null, 2) {
    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            "CREATE TABLE thread_state (" +
                "thread_id INTEGER PRIMARY KEY," +
                "pinned INTEGER NOT NULL DEFAULT 0," +
                "archived INTEGER NOT NULL DEFAULT 0," +
                "muted INTEGER NOT NULL DEFAULT 0)"
        )
        db.execSQL(
            "CREATE TABLE blocked (" +
                "address TEXT PRIMARY KEY," +
                "note TEXT NOT NULL DEFAULT ''," +
                "created_at INTEGER NOT NULL)"
        )
        db.execSQL(
            "CREATE TABLE trash (" +
                "id INTEGER PRIMARY KEY," +
                "thread_id INTEGER NOT NULL," +
                "address TEXT NOT NULL," +
                "body TEXT NOT NULL DEFAULT ''," +
                "date INTEGER NOT NULL," +
                "deleted_at INTEGER NOT NULL," +
                "kind INTEGER NOT NULL DEFAULT 0)"
        )
        db.execSQL(
            "CREATE TABLE drafts (" +
                "address TEXT PRIMARY KEY," +
                "body TEXT NOT NULL)"
        )
        db.execSQL(
            "CREATE TABLE scheduled (" +
                "id INTEGER PRIMARY KEY AUTOINCREMENT," +
                "address TEXT NOT NULL," +
                "body TEXT NOT NULL," +
                "at INTEGER NOT NULL," +
                "sub_id INTEGER NOT NULL DEFAULT -1)"
        )
        db.execSQL("CREATE TABLE remote (id INTEGER PRIMARY KEY)")
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        if (oldVersion < 2) {
            db.execSQL("CREATE TABLE IF NOT EXISTS remote (id INTEGER PRIMARY KEY)")
        }
    }

    data class ThreadState(val pinned: Boolean, val archived: Boolean, val muted: Boolean)

    data class Blocked(val address: String, val note: String, val createdAt: Long)

    data class Trash(
        val id: Long,
        val threadId: Long,
        val address: String,
        val body: String,
        val date: Long,
        val deletedAt: Long,
        val kind: Int,
    )

    data class Scheduled(val id: Long, val address: String, val body: String, val at: Long, val subId: Int)

    fun states(): Map<Long, ThreadState> = readableDatabase.rawQuery(
        "SELECT thread_id,pinned,archived,muted FROM thread_state",
        null,
    ).use { cursor ->
        buildMap {
            while (cursor.moveToNext()) {
                put(cursor.getLong(0), ThreadState(cursor.getInt(1) != 0, cursor.getInt(2) != 0, cursor.getInt(3) != 0))
            }
        }
    }

    fun setPinned(threadId: Long, pinned: Boolean) = setState(threadId, "pinned", pinned)

    fun setArchived(threadId: Long, archived: Boolean) = setState(threadId, "archived", archived)

    fun setMuted(threadId: Long, muted: Boolean) = setState(threadId, "muted", muted)

    private fun setState(threadId: Long, column: String, value: Boolean) {
        writableDatabase.execSQL(
            "INSERT INTO thread_state(thread_id,$column) VALUES(?,?) " +
                "ON CONFLICT(thread_id) DO UPDATE SET $column=excluded.$column",
            arrayOf(threadId, if (value) 1 else 0),
        )
    }

    fun hiddenIds(): Set<Long> = readableDatabase.rawQuery("SELECT id FROM trash", null).use { cursor ->
        buildSet { while (cursor.moveToNext()) add(cursor.getLong(0)) }
    }

    fun trashItems(): List<Trash> = readableDatabase.rawQuery(
        "SELECT id,thread_id,address,body,date,deleted_at,kind FROM trash ORDER BY deleted_at DESC",
        null,
    ).use { cursor ->
        buildList {
            while (cursor.moveToNext()) {
                add(Trash(cursor.getLong(0), cursor.getLong(1), cursor.getString(2), cursor.getString(3), cursor.getLong(4), cursor.getLong(5), cursor.getInt(6)))
            }
        }
    }

    fun trash(id: Long): Trash? = readableDatabase.rawQuery(
        "SELECT id,thread_id,address,body,date,deleted_at,kind FROM trash WHERE id=?",
        arrayOf(id.toString()),
    ).use { cursor ->
        if (cursor.moveToFirst()) Trash(cursor.getLong(0), cursor.getLong(1), cursor.getString(2), cursor.getString(3), cursor.getLong(4), cursor.getLong(5), cursor.getInt(6)) else null
    }

    fun hide(item: Trash) {
        writableDatabase.execSQL(
            "INSERT OR REPLACE INTO trash(id,thread_id,address,body,date,deleted_at,kind) VALUES(?,?,?,?,?,?,?)",
            arrayOf<Any?>(item.id, item.threadId, item.address, item.body, item.date, item.deletedAt, item.kind),
        )
    }

    fun unhide(id: Long): Boolean {
        val exists = readableDatabase.rawQuery("SELECT 1 FROM trash WHERE id=?", arrayOf(id.toString())).use { it.moveToFirst() }
        writableDatabase.delete("trash", "id=?", arrayOf(id.toString()))
        return exists
    }

    fun expiredTrash(before: Long): List<Trash> = readableDatabase.rawQuery(
        "SELECT id,thread_id,address,body,date,deleted_at,kind FROM trash WHERE deleted_at<?",
        arrayOf(before.toString()),
    ).use { cursor ->
        buildList {
            while (cursor.moveToNext()) {
                add(Trash(cursor.getLong(0), cursor.getLong(1), cursor.getString(2), cursor.getString(3), cursor.getLong(4), cursor.getLong(5), cursor.getInt(6)))
            }
        }
    }

    fun draft(address: String): String = readableDatabase.rawQuery(
        "SELECT body FROM drafts WHERE address=?",
        arrayOf(address),
    ).use { if (it.moveToFirst()) it.getString(0) else "" }

    fun saveDraft(address: String, body: String) {
        if (body.isBlank()) {
            writableDatabase.delete("drafts", "address=?", arrayOf(address))
        } else {
            writableDatabase.execSQL("INSERT OR REPLACE INTO drafts VALUES(?,?)", arrayOf(address, body))
        }
    }

    fun blocked(): List<Blocked> = readableDatabase.rawQuery(
        "SELECT address,note,created_at FROM blocked ORDER BY created_at DESC",
        null,
    ).use { cursor ->
        buildList {
            while (cursor.moveToNext()) add(Blocked(cursor.getString(0), cursor.getString(1), cursor.getLong(2)))
        }
    }

    fun block(address: String, note: String = "") {
        writableDatabase.execSQL(
            "INSERT OR REPLACE INTO blocked VALUES(?,?,?)",
            arrayOf<Any?>(address, note, System.currentTimeMillis()),
        )
    }

    fun unblock(address: String) {
        writableDatabase.delete("blocked", "address=?", arrayOf(address))
    }

    fun schedule(address: String, body: String, at: Long, subId: Int): Long = writableDatabase.insertOrThrow(
        "scheduled",
        null,
        ContentValues().apply {
            put("address", address)
            put("body", body)
            put("at", at)
            put("sub_id", subId)
        },
    )

    fun scheduled(): List<Scheduled> = readableDatabase.rawQuery(
        "SELECT id,address,body,at,sub_id FROM scheduled ORDER BY at ASC",
        null,
    ).use { cursor ->
        buildList {
            while (cursor.moveToNext()) {
                add(Scheduled(cursor.getLong(0), cursor.getString(1), cursor.getString(2), cursor.getLong(3), cursor.getInt(4)))
            }
        }
    }

    fun scheduled(id: Long): Scheduled? = readableDatabase.rawQuery(
        "SELECT id,address,body,at,sub_id FROM scheduled WHERE id=?",
        arrayOf(id.toString()),
    ).use { cursor ->
        if (cursor.moveToFirst()) Scheduled(cursor.getLong(0), cursor.getString(1), cursor.getString(2), cursor.getLong(3), cursor.getInt(4)) else null
    }

    fun cancelScheduled(id: Long) {
        writableDatabase.delete("scheduled", "id=?", arrayOf(id.toString()))
    }

    fun remoteIds(): Set<Long> = readableDatabase.rawQuery("SELECT id FROM remote", null).use { cursor ->
        buildSet { while (cursor.moveToNext()) add(cursor.getLong(0)) }
    }

    fun markRemote(id: Long) {
        writableDatabase.execSQL("INSERT OR IGNORE INTO remote VALUES(?)", arrayOf<Any?>(id))
    }
}
