package com.blue.qingniao

import android.Manifest
import android.app.Activity
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.ContactsContract
import android.provider.MediaStore
import android.provider.Telephony
import android.telephony.SubscriptionManager
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

class AuroraBridge(private val activity: Activity) {
    private val context: Context get() = activity
    private val handler = Handler(Looper.getMainLooper())
    private val prefs by lazy { context.getSharedPreferences("appearance", Context.MODE_PRIVATE) }
    private val syncPrefs by lazy { context.getSharedPreferences("aurora_sync", Context.MODE_PRIVATE) }
    @Volatile private var contactsCache: Pair<Long, Map<String, String>>? = null

    fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        if (call.method !in methods) return false
        try {
            when (call.method) {
                "dataDir" -> {
                    val dir = File(context.filesDir, "aurora").apply { mkdirs() }
                    result.success(dir.absolutePath)
                }
                "openUrl" -> {
                    val raw = call.argument<String>("url") ?: return false
                    val uri = Uri.parse(raw)
                    require(uri.scheme == "http" || uri.scheme == "https") { "只允许 http/https 链接" }
                    activity.startActivity(Intent(Intent.ACTION_VIEW, uri))
                    result.success(null)
                }
                "stats" -> result.success(stats())
                "syncState" -> result.success(syncPrefs.getString("state", "") ?: "")
                "syncStateSet" -> {
                    syncPrefs.edit().putString("state", call.argument<String>("json") ?: "").apply()
                    result.success(null)
                }
                "syncStatus" -> result.success(syncStatus())
                "syncConfigure" -> {
                    syncPrefs.edit()
                        .putBoolean("enabled", call.argument<Boolean>("enabled") == true)
                        .putString("serverUrl", call.argument<String>("serverUrl")?.trim().orEmpty())
                        .apply()
                    result.success(syncStatus())
                }
                "syncPair", "syncNow" -> result.success(syncStatus())
                "syncReset" -> {
                    syncPrefs.edit().clear().apply()
                    result.success(null)
                }
                "exportBackup" -> result.success(exportBackup())
                "importBackup" -> result.success(false)
                else -> {
                    MessageIo.executor.execute {
                        try {
                            val value = work(call)
                            handler.post { result.success(value) }
                        } catch (error: Exception) {
                            val message = when (error) {
                                is SecurityException -> "短信权限已撤销，请重新授权"
                                is IllegalArgumentException, is IllegalStateException ->
                                    error.message ?: "操作无法完成"
                                else -> "系统消息服务暂时不可用，请重试"
                            }
                            handler.post {
                                result.error("message_operation_failed", message, null)
                            }
                        }
                    }
                }
            }
            return true
        } catch (error: Exception) {
            val message = when (error) {
                is SecurityException -> "短信权限已撤销，请重新授权"
                is IllegalArgumentException, is IllegalStateException -> error.message ?: "操作无法完成"
                else -> "系统消息服务暂时不可用，请重试"
            }
            result.error("message_operation_failed", message, null)
            return true
        }
    }

    private fun work(call: MethodCall): Any? {
        requireAccess()
        return AuroraStore(context).use { store ->
            when (call.method) {
                "conversations" -> conversations(
                    store,
                    call.argument<String>("query")?.take(200) ?: "",
                    call.argument<String>("filter") ?: "all",
                )
                "messages" -> messages(
                    store,
                    requireNotNull(call.argument<Number>("threadId")).toLong(),
                    call.argument<Number>("before")?.toLong() ?: Long.MAX_VALUE,
                    (call.argument<Number>("limit")?.toInt() ?: 80).coerceIn(1, 300),
                )
                "markRead" -> {
                    markRead(requireNotNull(call.argument<Number>("threadId")).toLong())
                    null
                }
                "hide" -> {
                    val id = requireNotNull(call.argument<Number>("id")).toLong()
                    hideMessage(store, id)
                    null
                }
                "restore" -> {
                    val id = requireNotNull(call.argument<Number>("id")).toLong()
                    store.unhide(id)
                    null
                }
                "delete" -> {
                    val id = requireNotNull(call.argument<Number>("id")).toLong()
                    deleteForever(store, id)
                    null
                }
                "trash" -> store.trashItems().map {
                    mapOf(
                        "id" to it.id,
                        "threadId" to it.threadId,
                        "address" to it.address,
                        "body" to it.body,
                        "date" to it.date,
                        "deletedAt" to it.deletedAt,
                        "kind" to it.kind,
                    )
                }
                "trashRetention" -> {
                    prefs.edit().putString("trashDays", "${call.argument<Number>("days")?.toInt() ?: 30}").apply()
                    null
                }
                "purgeTrash" -> purgeTrash(store, call.argument<Number>("days")?.toInt() ?: 30)
                "subscriptions" -> subscriptions()
                "draft" -> store.draft(requireNotNull(call.argument<String>("address")))
                "saveDraft" -> {
                    store.saveDraft(
                        requireNotNull(call.argument<String>("address")),
                        requireNotNull(call.argument<String>("body")),
                    )
                    null
                }
                "pin" -> {
                    store.setPinned(
                        requireNotNull(call.argument<Number>("threadId")).toLong(),
                        call.argument<Boolean>("pinned") == true,
                    )
                    null
                }
                "archive" -> {
                    store.setArchived(
                        requireNotNull(call.argument<Number>("threadId")).toLong(),
                        call.argument<Boolean>("archived") == true,
                    )
                    null
                }
                "block" -> {
                    store.block(requireNotNull(call.argument<String>("address")))
                    null
                }
                "unblock" -> {
                    store.unblock(requireNotNull(call.argument<String>("address")))
                    null
                }
                "blocked" -> store.blocked().map {
                    mapOf("address" to it.address, "note" to it.note, "createdAt" to it.createdAt)
                }
                "attachmentData" -> attachmentData(requireNotNull(call.argument<String>("uri")))
                "schedule" -> schedule(
                    store,
                    requireNotNull(call.argument<String>("address")),
                    requireNotNull(call.argument<String>("body")),
                    requireNotNull(call.argument<Number>("at")).toLong(),
                    call.argument<Number>("subscriptionId")?.toInt() ?: -1,
                )
                "scheduled" -> store.scheduled().map {
                    mapOf("id" to it.id, "address" to it.address, "body" to it.body, "at" to it.at, "subscriptionId" to it.subId)
                }
                "cancelScheduled" -> {
                    val id = requireNotNull(call.argument<Number>("id")).toLong()
                    cancelAlarm(id)
                    store.cancelScheduled(id)
                    null
                }
                "remoteMessagesSince" -> remoteMessagesSince(
                    store,
                    call.argument<Number>("since")?.toLong() ?: 0L,
                )
                "insertRemoteMessage" -> insertRemoteMessage(
                    requireNotNull(call.argument<String>("address")),
                    requireNotNull(call.argument<String>("body")),
                    requireNotNull(call.argument<Number>("date")).toLong(),
                    call.argument<Number>("subscriptionId")?.toInt() ?: -1,
                )
                else -> throw IllegalArgumentException("不支持的操作：${call.method}")
            }
        }
    }

    private val methods = setOf(
        "conversations", "messages", "markRead", "hide", "restore", "delete",
        "trash", "trashRetention", "purgeTrash", "subscriptions", "draft", "saveDraft",
        "pin", "archive", "block", "unblock", "blocked", "attachmentData",
        "schedule", "scheduled", "cancelScheduled", "dataDir", "openUrl",
        "stats", "exportBackup", "importBackup", "syncStatus", "syncConfigure",
        "syncPair", "syncNow", "syncReset", "syncState", "syncStateSet",
        "remoteMessagesSince", "insertRemoteMessage",
    )

    private fun requireAccess() {
        val state = access()
        check(listOf("defaultApp", "readSms", "sendSms", "receiveSms").all { state[it] == true }) {
            "请设置默认短信应用并授予短信权限"
        }
    }

    private fun access(): Map<String, Boolean> = mapOf(
        "defaultApp" to (Telephony.Sms.getDefaultSmsPackage(context) == context.packageName),
        "readSms" to granted(Manifest.permission.READ_SMS),
        "sendSms" to granted(Manifest.permission.SEND_SMS),
        "receiveSms" to granted(Manifest.permission.RECEIVE_SMS),
        "readContacts" to granted(Manifest.permission.READ_CONTACTS),
        "notifications" to context.getSystemService(NotificationManager::class.java).areNotificationsEnabled(),
        "roleAvailable" to context.getSystemService(android.app.role.RoleManager::class.java).isRoleAvailable(android.app.role.RoleManager.ROLE_SMS),
    )

    private fun granted(permission: String) = context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED


    private fun conversations(store: AuroraStore, query: String, filter: String): List<Map<String, Any?>> {
        val hidden = store.hiddenIds()
        val states = store.states()
        val blocked = store.blocked().map { normalize(it.address) }.toSet()
        val contacts = contacts()
        val threads = linkedMapOf<Long, Conversation>()

        context.contentResolver.query(
            Telephony.Sms.CONTENT_URI,
            arrayOf("_id", "thread_id", "address", "body", "date", "type", "read", "sub_id"),
            null,
            null,
            "date DESC, _id DESC",
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                val id = cursor.getLong(0)
                if (id in hidden) continue
                val threadId = cursor.getLong(1)
                val address = cursor.getString(2) ?: "未知号码"
                val body = cursor.getString(3) ?: ""
                val date = cursor.getLong(4)
                val type = cursor.getInt(5)
                val read = cursor.getInt(6) != 0
                val subId = cursor.getInt(7)
                val key = normalize(address)
                if (key in blocked) continue
                val conversation = threads.getOrPut(threadId) {
                    Conversation(threadId, address, subId, date, body, type)
                }
                conversation.count += 1
                if (!read && type == 1) conversation.unread += 1
            }
        }

        context.contentResolver.query(
            Telephony.Mms.CONTENT_URI,
            arrayOf("_id", "thread_id", "date", "msg_box", "sub_id", "subject", "read"),
            null,
            null,
            "date DESC",
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                val id = cursor.getLong(0)
                if (id in hidden) continue
                val threadId = cursor.getLong(1)
                val date = cursor.getLong(2)
                val box = cursor.getInt(3)
                val subId = cursor.getInt(4)
                val subject = cursor.getString(5) ?: ""
                val read = cursor.getInt(6) != 0
                val address = mmsAddress(id) ?: "未知号码"
                if (normalize(address) in blocked) continue
                val conversation = threads.getOrPut(threadId) {
                    Conversation(threadId, address, subId, date, subject, typeForBox(box), true)
                }
                conversation.count += 1
                conversation.hasMms = true
                if (!read && box == 1) conversation.unread += 1
                if (date > conversation.date) {
                    conversation.date = date
                    conversation.preview = subject
                    conversation.type = typeForBox(box)
                }
            }
        }

        val lowered = query.trim().lowercase()
        val matches = mutableSetOf<Long>()
        if (lowered.isNotEmpty()) {
            context.contentResolver.query(
                Telephony.Sms.CONTENT_URI,
                arrayOf("thread_id"),
                "address LIKE ? OR body LIKE ?",
                arrayOf("%$query%", "%$query%"),
                null,
            )?.use { cursor -> while (cursor.moveToNext()) matches.add(cursor.getLong(0)) }
            context.contentResolver.query(
                Telephony.Mms.CONTENT_URI,
                arrayOf("thread_id"),
                "subj LIKE ?",
                arrayOf("%$query%"),
                null,
            )?.use { cursor -> while (cursor.moveToNext()) matches.add(cursor.getLong(0)) }
        }
        return threads.values
            .asSequence()
            .filter { item ->
                val state = states[item.threadId]
                val archived = state?.archived == true
                when (filter) {
                    "unread" -> item.unread > 0 && !archived
                    "pinned" -> state?.pinned == true && !archived
                    "archived" -> archived
                    else -> !archived
                }
            }
            .filter { item ->
                lowered.isEmpty() || item.threadId in matches
            }
            .map { item ->
                val state = states[item.threadId]
                val name = contacts[normalize(item.address)] ?: ""
                mapOf(
                    "threadId" to item.threadId,
                    "address" to item.address,
                    "displayName" to name,
                    "body" to item.preview,
                    "date" to item.date,
                    "unread" to item.unread,
                    "subscriptionId" to item.subId,
                    "messageType" to item.type,
                    "pinned" to (state?.pinned == true),
                    "archived" to (state?.archived == true),
                    "blocked" to false,
                    "category" to "personal",
                    "otp" to null,
                    "recipients" to listOf(item.address),
                    "count" to item.count,
                    "hasMms" to item.hasMms,
                    "latestId" to 0,
                    "latestBody" to item.preview,
                )
            }
            .sortedWith(compareByDescending<Map<String, Any?>> { it["pinned"] == true }.thenByDescending { it["date"] as Long })
            .take(500)
            .toList()
    }

    private data class Conversation(
        val threadId: Long,
        val address: String,
        val subId: Int,
        var date: Long,
        var preview: String,
        var type: Int,
        var hasMms: Boolean = false,
        var unread: Int = 0,
        var count: Int = 0,
    )

    private fun normalize(value: String): String {
        val digits = value.filter { it.isDigit() }
        return if (digits.length > 11 && digits.startsWith("86")) digits.substring(2) else digits.takeLast(11)
    }

    private fun contacts(): Map<String, String> {
        val cached = contactsCache
        if (cached != null && System.currentTimeMillis() - cached.first < 120_000) return cached.second
        val map = HashMap<String, String>()
        if (granted(Manifest.permission.READ_CONTACTS)) {
            context.contentResolver.query(
                ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                arrayOf(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME, ContactsContract.CommonDataKinds.Phone.NUMBER),
                null,
                null,
                null,
            )?.use { cursor ->
                while (cursor.moveToNext()) {
                    val name = cursor.getString(0) ?: continue
                    val number = cursor.getString(1) ?: continue
                    val key = normalize(number)
                    if (key.isNotEmpty() && key !in map) map[key] = name
                }
            }
        }
        contactsCache = System.currentTimeMillis() to map
        return map
    }


    private fun messages(store: AuroraStore, threadId: Long, before: Long, limit: Int): List<Map<String, Any?>> {
        val hidden = store.hiddenIds()
        val rows = mutableListOf<Map<String, Any?>>()

        context.contentResolver.query(
            Telephony.Sms.CONTENT_URI,
            arrayOf("_id", "thread_id", "address", "body", "date", "type", "read", "sub_id", "status"),
            "thread_id=? AND _id<?",
            arrayOf(threadId.toString(), before.toString()),
            "_id DESC",
        )?.use { cursor ->
            while (cursor.moveToNext() && rows.size < limit) {
                val id = cursor.getLong(0)
                if (id in hidden) continue
                rows.add(
                    mapOf(
                        "id" to id,
                        "threadId" to cursor.getLong(1),
                        "address" to (cursor.getString(2) ?: "未知号码"),
                        "body" to (cursor.getString(3) ?: ""),
                        "date" to cursor.getLong(4),
                        "type" to cursor.getInt(5),
                        "read" to (cursor.getInt(6) != 0),
                        "subscriptionId" to cursor.getInt(7),
                        "status" to cursor.getInt(8),
                        "mms" to false,
                        "attachments" to emptyList<Map<String, Any?>>(),
                        "sender" to "",
                        "subject" to "",
                        "pending" to false,
                    ),
                )
            }
        }

        context.contentResolver.query(
            Telephony.Mms.CONTENT_URI,
            arrayOf("_id", "thread_id", "date", "msg_box", "sub_id", "subject", "read"),
            "thread_id=?",
            arrayOf(threadId.toString()),
            "date DESC",
        )?.use { cursor ->
            while (cursor.moveToNext() && rows.size < limit) {
                val id = cursor.getLong(0)
                if (id in hidden) continue
                val date = cursor.getLong(2)
                val box = cursor.getInt(3)
                val parts = mmsParts(id)
                rows.add(
                    mapOf(
                        "id" to id,
                        "threadId" to cursor.getLong(1),
                        "address" to (mmsAddress(id) ?: "未知号码"),
                        "body" to parts.text,
                        "date" to date,
                        "type" to typeForBox(box),
                        "read" to (cursor.getInt(6) != 0),
                        "subscriptionId" to cursor.getInt(4),
                        "status" to -1,
                        "mms" to true,
                        "attachments" to parts.attachments,
                        "sender" to parts.sender,
                        "subject" to (cursor.getString(5) ?: ""),
                        "pending" to (parts.attachments.isEmpty() && parts.text.isEmpty()),
                    ),
                )
            }
        }

        rows.sortBy { (it["date"] as? Long) ?: 0L }
        return if (rows.size <= limit) rows else rows.takeLast(limit)
    }

    private data class MmsParts(
        val text: String,
        val sender: String,
        val attachments: List<Map<String, Any?>>,
    )

    private fun mmsParts(id: Long): MmsParts {
        val text = StringBuilder()
        val attachments = mutableListOf<Map<String, Any?>>()
        var sender = ""
        context.contentResolver.query(
            Uri.parse("content://mms/part"),
            arrayOf("_id", "ct", "name", "text", "fn", "cl"),
            "mid=?",
            arrayOf(id.toString()),
            null,
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                val partId = cursor.getLong(0)
                val type = cursor.getString(1) ?: ""
                val name = cursor.getString(2) ?: cursor.getString(5) ?: cursor.getString(4) ?: ""
                val preview = cursor.getString(3)
                if (type.startsWith("text/plain")) {
                    if (text.isNotEmpty()) text.append('\n')
                    text.append(preview.orEmpty())
                } else if (type.isNotEmpty() && !type.startsWith("application/smil")) {
                    attachments.add(
                        mapOf(
                            "id" to partId.toString(),
                            "uri" to ContentUris.withAppendedId(Uri.parse("content://mms/part"), partId).toString(),
                            "mime" to type,
                            "name" to name.ifBlank { "附件" },
                            "size" to 0,
                        ),
                    )
                }
            }
        }
        context.contentResolver.query(
            Uri.parse("content://mms/$id/addr"),
            arrayOf("address", "type"),
            null,
            null,
            null,
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                if (cursor.getInt(1) == 137) {
                    sender = cursor.getString(0) ?: ""
                    break
                }
            }
        }
        return MmsParts(text.toString(), sender, attachments)
    }

    private fun mmsAddress(id: Long): String? {
        context.contentResolver.query(
            Uri.parse("content://mms/$id/addr"),
            arrayOf("address"),
            "type=137",
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) return cursor.getString(0)
        }
        context.contentResolver.query(
            Uri.parse("content://mms/$id/addr"),
            arrayOf("address"),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) return cursor.getString(0)
        }
        return null
    }

    private fun typeForBox(box: Int): Int = when (box) {
        2 -> 2
        3 -> 3
        4 -> 4
        5 -> 5
        else -> 1
    }

    private fun markRead(threadId: Long) {
        context.contentResolver.update(
            Telephony.Sms.CONTENT_URI,
            ContentValues().apply { put("read", 1); put("seen", 1) },
            "thread_id=? AND read=0",
            arrayOf(threadId.toString()),
        )
        context.contentResolver.update(
            Telephony.Mms.CONTENT_URI,
            ContentValues().apply { put("read", 1); put("seen", 1) },
            "thread_id=? AND read=0",
            arrayOf(threadId.toString()),
        )
    }

    private fun hideMessage(store: AuroraStore, id: Long) {
        val cursor = context.contentResolver.query(
            Telephony.Sms.CONTENT_URI,
            arrayOf("_id", "thread_id", "address", "body", "date"),
            "_id=?",
            arrayOf(id.toString()),
            null,
        ) ?: return
        cursor.use {
            if (it.moveToFirst()) {
                store.hide(
                    AuroraStore.Trash(
                        it.getLong(0),
                        it.getLong(1),
                        it.getString(2) ?: "未知号码",
                        it.getString(3) ?: "",
                        it.getLong(4),
                        System.currentTimeMillis(),
                        0,
                    ),
                )
            } else {
                val mms = context.contentResolver.query(
                    Telephony.Mms.CONTENT_URI,
                    arrayOf("_id", "thread_id", "date", "subject"),
                    "_id=?",
                    arrayOf(id.toString()),
                    null,
                )
                mms?.use { row ->
                    if (row.moveToFirst()) {
                        store.hide(
                            AuroraStore.Trash(
                                row.getLong(0),
                                row.getLong(1),
                                mmsAddress(id) ?: "未知号码",
                                row.getString(3) ?: "",
                                row.getLong(2),
                                System.currentTimeMillis(),
                                1,
                            ),
                        )
                    }
                }
            }
        }
    }

    private fun deleteForever(store: AuroraStore, id: Long) {
        val item = store.trash(id) ?: return
        val uri = if (item.kind == 1) Telephony.Mms.CONTENT_URI else Telephony.Sms.CONTENT_URI
        context.contentResolver.delete(ContentUris.withAppendedId(uri, id), null, null)
        store.unhide(id)
    }

    private fun purgeTrash(store: AuroraStore, days: Int): Int {
        if (days <= 0) return 0
        val cutoff = System.currentTimeMillis() - days * 86_400_000L
        val expired = store.expiredTrash(cutoff)
        for (item in expired) deleteForever(store, item.id)
        return expired.size
    }


    private fun subscriptions(): List<Map<String, Any?>> {
        if (context.checkSelfPermission(Manifest.permission.READ_PHONE_STATE) != PackageManager.PERMISSION_GRANTED) return emptyList()
        val manager = context.getSystemService(SubscriptionManager::class.java)
        return try { manager.activeSubscriptionInfoList.orEmpty().map { info ->
            val number = if (context.checkSelfPermission(Manifest.permission.READ_PHONE_NUMBERS) == PackageManager.PERMISSION_GRANTED) {
                if (Build.VERSION.SDK_INT >= 33) manager.getPhoneNumber(info.subscriptionId)
                else {
                    @Suppress("DEPRECATION")
                    info.number.orEmpty()
                }
            } else ""
            mapOf(
                "id" to info.subscriptionId,
                "slot" to info.simSlotIndex + 1,
                "name" to (info.displayName?.toString() ?: "SIM"),
                "number" to number,
                "carrier" to (info.carrierName?.toString() ?: ""),
            )
        } } catch (_: SecurityException) { emptyList() }
    }

    private fun attachmentData(uri: String): ByteArray {
        val parsed = Uri.parse(uri)
        return context.contentResolver.openInputStream(parsed)?.use { stream ->
            val buffer = ByteArray(8 * 1024 * 1024)
            var read = 0
            while (read < buffer.size) {
                val count = stream.read(buffer, read, buffer.size - read)
                if (count <= 0) break
                read += count
            }
            buffer.copyOf(read)
        } ?: throw IllegalArgumentException("无法读取附件")
    }

    private fun schedule(store: AuroraStore, address: String, body: String, at: Long, subId: Int): Long {
        require(address.isNotBlank()) { "收件号码不能为空" }
        require(body.isNotBlank()) { "短信正文不能为空" }
        require(at > System.currentTimeMillis()) { "定时时间必须在未来" }
        val id = store.schedule(address, body, at, subId)
        val alarm = context.getSystemService(AlarmManager::class.java)
        val pending = PendingIntent.getBroadcast(
            context,
            id.toInt(),
            Intent(context, ScheduledSendReceiver::class.java).putExtra("id", id),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        try {
            if (Build.VERSION.SDK_INT >= 31 && !alarm.canScheduleExactAlarms()) {
                alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending)
            } else {
                alarm.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending)
            }
        } catch (_: SecurityException) {
            alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending)
        }
        return id
    }

    private fun cancelAlarm(id: Long) {
        val alarm = context.getSystemService(AlarmManager::class.java)
        val pending = PendingIntent.getBroadcast(
            context,
            id.toInt(),
            Intent(context, ScheduledSendReceiver::class.java).putExtra("id", id),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        alarm.cancel(pending)
    }

    private fun stats(): Map<String, Any?> {
        val trash = AuroraStore(context).use { it.trashItems().size }
        val sms = count(Telephony.Sms.CONTENT_URI)
        val mms = count(Telephony.Mms.CONTENT_URI)
        val threadCount = countDistinct(Telephony.Sms.CONTENT_URI, "thread_id") +
            countDistinct(Telephony.Mms.CONTENT_URI, "thread_id")
        val dbBytes = File(context.getDatabasePath("aurora.db").absolutePath).length()
        return mapOf(
            "threads" to threadCount,
            "messages" to sms + mms,
            "indexed" to 0,
            "trash" to trash,
            "frameMs" to 0.0,
            "quality" to "full",
            "storageBytes" to dbBytes,
            "otpCount" to 0,
        )
    }

    private fun countDistinct(uri: Uri, column: String): Int =
        context.contentResolver.query(uri, arrayOf(column), null, null, null)?.use { cursor ->
            buildSet { while (cursor.moveToNext()) add(cursor.getLong(0)) }.size
        } ?: 0

    private fun count(uri: Uri): Int = context.contentResolver.query(
        uri,
        arrayOf("_id"),
        null,
        null,
        null,
    )?.use { it.count } ?: 0

    private fun exportBackup(): Boolean {
        val payload = JSONObject().apply {
            put("version", 1)
            put("exportedAt", System.currentTimeMillis())
            put("blocked", JSONArray().apply {
                AuroraStore(context).use { store ->
                    store.blocked().forEach {
                        put(JSONObject().apply { put("address", it.address); put("note", it.note); put("createdAt", it.createdAt) })
                    }
                }
            })
            put("messages", JSONArray().apply {
                context.contentResolver.query(
                    Telephony.Sms.CONTENT_URI,
                    arrayOf("_id", "thread_id", "address", "body", "date", "type", "read", "sub_id"),
                    null,
                    null,
                    "date ASC",
                )?.use { cursor ->
                    while (cursor.moveToNext() && length() < 20_000) {
                        put(JSONObject().apply {
                            put("id", cursor.getLong(0))
                            put("threadId", cursor.getLong(1))
                            put("address", cursor.getString(2))
                            put("body", cursor.getString(3))
                            put("date", cursor.getLong(4))
                            put("type", cursor.getInt(5))
                            put("read", cursor.getInt(6) != 0)
                            put("subscriptionId", cursor.getInt(7))
                        })
                    }
                }
            })
        }.toString()

        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, "qingniao-backup-${System.currentTimeMillis()}.json")
            put(MediaStore.MediaColumns.MIME_TYPE, "application/json")
            put(MediaStore.MediaColumns.RELATIVE_PATH, "Download/Qingniao")
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = context.contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: return false
        context.contentResolver.openOutputStream(uri)?.use { it.write(payload.toByteArray()) } ?: return false
        values.clear()
        values.put(MediaStore.MediaColumns.IS_PENDING, 0)
        context.contentResolver.update(uri, values, null, null)
        return true
    }

    private fun remoteMessagesSince(store: AuroraStore, since: Long): List<Map<String, Any?>> {
        val hidden = store.hiddenIds()
        val remote = store.remoteIds()
        val rows = mutableListOf<Map<String, Any?>>()
        context.contentResolver.query(
            Telephony.Sms.CONTENT_URI,
            arrayOf("_id", "thread_id", "address", "body", "date", "type", "sub_id"),
            "date>?",
            arrayOf(since.toString()),
            "date ASC",
        )?.use { cursor ->
            while (cursor.moveToNext() && rows.size < 120) {
                val id = cursor.getLong(0)
                if (id in hidden || id in remote) continue
                val body = cursor.getString(3) ?: ""
                if (body.isBlank()) continue
                rows.add(
                    mapOf(
                        "id" to id,
                        "threadId" to cursor.getLong(1),
                        "address" to (cursor.getString(2) ?: "未知号码"),
                        "body" to body,
                        "date" to cursor.getLong(4),
                        "type" to cursor.getInt(5),
                        "subscriptionId" to cursor.getInt(6),
                    ),
                )
            }
        }
        return rows
    }

    private fun insertRemoteMessage(address: String, body: String, date: Long, subId: Int): Long {
        require(address.isNotBlank()) { "远端消息缺少号码" }
        require(body.isNotBlank()) { "远端消息缺少正文" }
        val values = ContentValues().apply {
            put("address", address)
            put("body", body)
            put("date", date)
            put("date_sent", date)
            put("read", 0)
            put("seen", 0)
            put("type", Telephony.Sms.MESSAGE_TYPE_INBOX)
            if (subId >= 0) put("sub_id", subId)
        }
        val uri = context.contentResolver.insert(Telephony.Sms.Inbox.CONTENT_URI, values)
            ?: throw IllegalArgumentException("无法写入系统短信库")
        val id = ContentUris.parseId(uri)
        AuroraStore(context).use { it.markRemote(id) }
        return id
    }

    private fun syncStatus(): Map<String, Any?> = mapOf(
        "enabled" to syncPrefs.getBoolean("enabled", false),
        "serverUrl" to (syncPrefs.getString("serverUrl", "") ?: ""),
        "deviceName" to (syncPrefs.getString("deviceName", Build.MODEL) ?: Build.MODEL),
        "fingerprint" to (syncPrefs.getString("fingerprint", "") ?: ""),
        "lastSync" to syncPrefs.getLong("lastSync", 0),
        "pending" to syncPrefs.getInt("pending", 0),
        "devices" to emptyList<Map<String, Any?>>(),
    )
}
