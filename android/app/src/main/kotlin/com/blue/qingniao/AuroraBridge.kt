package com.blue.qingniao

import android.Manifest
import android.app.Activity
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ComponentName
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
import android.os.PowerManager
import android.provider.ContactsContract
import android.provider.MediaStore
import android.provider.Settings
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
    private var pendingImport: MethodChannel.Result? = null

    companion object {
        private const val REQUEST_IMPORT = 75
    }

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
                    require(uri.scheme == "http" || uri.scheme == "https") { "Only HTTP and HTTPS links are supported" }
                    activity.startActivity(Intent(Intent.ACTION_VIEW, uri))
                    result.success(null)
                }
                "testNotification" -> {
                    Notifications.showSms(
                        context,
                        LocalizedResources.text(context, R.string.notification_test_title),
                        LocalizedResources.text(context, R.string.notification_test_body),
                        SubscriptionManager.getDefaultSmsSubscriptionId(),
                        -1L,
                    )
                    result.success(Notifications.canPromote(context))
                }
                "notificationCapabilities" -> result.success(notificationCapabilities())
                "batteryUnrestricted" -> result.success(requestBatteryUnrestricted())
                "autoStartSettings" -> result.success(openAutoStartSettings())
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
                "importBackup" -> {
                    if (pendingImport != null) {
                        result.error("busy", "Choosing a backup file", null)
                    } else {
                        pendingImport = result
                        try {
                            activity.startActivityForResult(
                                Intent(Intent.ACTION_OPEN_DOCUMENT)
                                    .addCategory(Intent.CATEGORY_OPENABLE)
                                    .setType("application/json"),
                                REQUEST_IMPORT,
                            )
                        } catch (error: Exception) {
                            pendingImport = null
                            result.error("unavailable", "No file picker is available", null)
                        }
                    }
                }
                else -> {
                    MessageIo.executor.execute {
                        try {
                            val value = work(call)
                            handler.post { result.success(value) }
                        } catch (error: Exception) {
                            val message = when (error) {
                                is SecurityException -> "SMS permission was revoked. Grant permission again."
                                is IllegalArgumentException, is IllegalStateException ->
                                    error.message ?: "Unable to complete the action"
                                else -> "System messaging service unavailable. Try again."
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
                is SecurityException -> "SMS permission was revoked. Grant permission again."
                is IllegalArgumentException, is IllegalStateException -> error.message ?: "Unable to complete the action"
                else -> "System messaging service unavailable. Try again."
            }
            result.error("message_operation_failed", message, null)
            return true
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_IMPORT) return false
        val result = pendingImport ?: return true
        pendingImport = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(false)
            return true
        }
        MessageIo.executor.execute {
            try {
                val imported = importBackup(uri)
                handler.post { result.success(imported) }
            } catch (error: Exception) {
                handler.post {
                    result.error("import_failed", error.message ?: "Backup import failed", null)
                }
            }
        }
        return true
    }

    fun cancelPending() {
        pendingImport?.error("activity_closed", "Import canceled", null)
        pendingImport = null
    }

    private fun work(call: MethodCall): Any? {
        requireAccess()
        return AuroraStore(context).use { store ->
            when (call.method) {
                "stats" -> stats()
                "exportBackup" -> exportBackup()
                "conversations" -> conversations(
                    store,
                    call.argument<String>("query")?.take(200) ?: "",
                    call.argument<String>("filter") ?: "all",
                )
                "messages" -> messages(
                    store,
                    requireNotNull(call.argument<Number>("threadId")).toLong(),
                    call.argument<Number>("before")?.toLong() ?: Long.MAX_VALUE,
                    call.argument<Number>("beforeDate")?.toLong() ?: Long.MAX_VALUE,
                    (call.argument<Number>("limit")?.toInt() ?: 80).coerceIn(1, 300),
                )
                "searchCorpus" -> searchCorpus(store)
                "markAllRead" -> ConversationOperations(context).markRead(null)
                "markThreadsRead" -> ConversationOperations(context).markRead(ConversationOperations.threadIds(call.argument("threadIds")))
                "trashThreads" -> ConversationOperations(context).moveToTrash(store, ConversationOperations.threadIds(call.argument("threadIds")))
                "copyThreads" -> ConversationOperations(context).copyText(store, ConversationOperations.threadIds(call.argument("threadIds")))
                "hideMessages" -> {
                    val ids = requireNotNull(call.argument<List<Number>>("ids"))
                    require(ids.isNotEmpty() && ids.size <= 10_000)
                    val db = store.writableDatabase
                    db.beginTransaction()
                    try {
                        ids.forEach { hideMessage(store, it.toLong()) }
                        db.setTransactionSuccessful()
                    } finally { db.endTransaction() }
                    null
                }
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
                else -> throw IllegalArgumentException("Unsupported operation: ${call.method}")
            }
        }
    }

    private val methods = setOf(
        "markAllRead", "markThreadsRead", "trashThreads", "copyThreads", "hideMessages",
        "conversations", "messages", "markRead", "hide", "restore", "delete",
        "searchCorpus", "trash", "trashRetention", "purgeTrash", "subscriptions", "draft", "saveDraft",
        "pin", "archive", "block", "unblock", "blocked", "attachmentData",
        "schedule", "scheduled", "cancelScheduled", "dataDir", "openUrl",
        "stats", "exportBackup", "importBackup", "syncStatus", "syncConfigure",
        "syncPair", "syncNow", "syncReset", "syncState", "syncStateSet",
        "remoteMessagesSince", "insertRemoteMessage", "notificationCapabilities",
        "testNotification",
        "batteryUnrestricted", "autoStartSettings",
    )

    private fun requireAccess() {
        val state = access()
        check(listOf("defaultApp", "readSms", "sendSms", "receiveSms").all { state[it] == true }) {
            "Set the default SMS role and grant SMS permissions"
        }
    }

    private fun access(): Map<String, Boolean> = mapOf(
        "defaultApp" to SmsAccess.isDefaultSmsApp(context),
        "readSms" to SmsAccess.granted(context, Manifest.permission.READ_SMS),
        "sendSms" to SmsAccess.granted(context, Manifest.permission.SEND_SMS),
        "receiveSms" to SmsAccess.granted(context, Manifest.permission.RECEIVE_SMS),
        "readContacts" to SmsAccess.granted(context, Manifest.permission.READ_CONTACTS),
        "notifications" to context.getSystemService(NotificationManager::class.java).areNotificationsEnabled(),
        "roleAvailable" to SmsAccess.roleAvailable(context),
    )

    private fun granted(permission: String) = SmsAccess.granted(context, permission)


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
                val address = cursor.getString(2) ?: "Unknown number"
                val date = cursor.getLong(4)
                val type = cursor.getInt(5)
                val read = cursor.getInt(6) != 0
                val subId = cursor.getInt(7)
                val key = normalize(address)
                if (key in blocked) continue
                val conversation = threads.getOrPut(threadId) {
                    Conversation(threadId, address, subId, date, cursor.getString(3).orEmpty(), type)
                }
                conversation.count += 1
                if (!read && type == 1) conversation.unread += 1
            }
        }

        context.contentResolver.query(
            Telephony.Mms.CONTENT_URI,
            arrayOf("_id", "thread_id", "date", "msg_box", "sub_id", "sub", "read"),
            null,
            null,
            "date DESC",
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                val id = cursor.getLong(0)
                if (MessageIdentity.mms(id) in hidden) continue
                val threadId = cursor.getLong(1)
                val date = cursor.getLong(2) * 1000
                val box = cursor.getInt(3)
                val subId = cursor.getInt(4)
                val subject = cursor.getString(5) ?: ""
                val read = cursor.getInt(6) != 0
                val address = mmsAddress(id) ?: "Unknown number"
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
                    "everything" -> true
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
        val number = android.telephony.PhoneNumberUtils.normalizeNumber(value)
        return if (number.startsWith("00")) "+${number.substring(2)}" else number
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


    private fun messages(store: AuroraStore, threadId: Long, before: Long, beforeDate: Long, limit: Int): List<Map<String, Any?>> {
        val hidden = store.hiddenIds()
        val page = MessagePageCursor(beforeDate, before)
        val rows = mutableListOf<Map<String, Any?>>()

        context.contentResolver.query(
            Telephony.Sms.CONTENT_URI,
            arrayOf("_id", "thread_id", "address", "body", "date", "type", "read", "sub_id", "status"),
            "thread_id=? AND date<=?",
            arrayOf(threadId.toString(), beforeDate.toString()),
            "date DESC, _id DESC",
        )?.use { cursor ->
            while (cursor.moveToNext() && rows.size < limit) {
                val id = cursor.getLong(0)
                if (id in hidden || !page.includes(cursor.getLong(4), id)) continue
                rows.add(
                    mapOf(
                        "id" to id,
                        "threadId" to cursor.getLong(1),
                        "address" to (cursor.getString(2) ?: "Unknown number"),
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

        var mmsCount = 0
        context.contentResolver.query(
            Telephony.Mms.CONTENT_URI,
            arrayOf("_id", "thread_id", "date", "msg_box", "sub_id", "sub", "read"),
            "thread_id=? AND date<=?",
            arrayOf(threadId.toString(), (beforeDate / 1000).toString()),
            "date DESC, _id ASC",
        )?.use { cursor ->
            while (cursor.moveToNext() && mmsCount < limit) {
                val id = cursor.getLong(0)
                if (MessageIdentity.mms(id) in hidden) continue
                val date = cursor.getLong(2) * 1000
                if (!page.includes(date, MessageIdentity.mms(id))) continue
                mmsCount++
                val box = cursor.getInt(3)
                val parts = mmsParts(id)
                rows.add(
                    mapOf(
                        "id" to MessageIdentity.mms(id),
                        "threadId" to cursor.getLong(1),
                        "address" to (mmsAddress(id) ?: "Unknown number"),
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

        rows.sortWith(compareBy<Map<String, Any?>> { it["date"] as Long }.thenBy { it["id"] as Long })
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
                            "name" to name.ifBlank { "Attachment" },
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
        val address = context.contentResolver.query(
            Telephony.Sms.CONTENT_URI,
            arrayOf("address"),
            "thread_id=?",
            arrayOf(threadId.toString()),
            null,
        )?.use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null }
        if (address != null) {
            Notifications.cancel(context, address.hashCode())
        }
    }

    private fun hideMessage(store: AuroraStore, key: Long) {
        val id = MessageIdentity.providerId(key)
        val mms = key < 0
        val uri = if (mms) Telephony.Mms.CONTENT_URI else Telephony.Sms.CONTENT_URI
        val columns = if (mms) arrayOf("_id", "thread_id", "sub", "date")
            else arrayOf("_id", "thread_id", "address", "body", "date")
        context.contentResolver.query(uri, columns, "_id=?", arrayOf(id.toString()), null)?.use { row ->
            if (row.moveToFirst()) store.hide(AuroraStore.Trash(key, row.getLong(1),
                if (mms) mmsAddress(id).orEmpty() else row.getString(2).orEmpty(),
                row.getString(if (mms) 2 else 3).orEmpty(),
                row.getLong(if (mms) 3 else 4) * (if (mms) 1000 else 1),
                System.currentTimeMillis(), if (mms) 1 else 0))
        }
    }

    private fun deleteForever(store: AuroraStore, id: Long) {
        val item = store.trash(id) ?: return
        val uri = if (item.kind == 1) Telephony.Mms.CONTENT_URI else Telephony.Sms.CONTENT_URI
        val itemUri = ContentUris.withAppendedId(uri, MessageIdentity.providerId(id))
        val removed = context.contentResolver.delete(itemUri, null, null)
        if (removed == 0) {
            val remains = context.contentResolver.query(itemUri, arrayOf("_id"), null, null, null)
                ?.use { it.moveToFirst() } ?: throw IllegalStateException("Unable to verify message deletion")
            check(!remains) { "The messaging provider did not delete this message" }
        }
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
            BoundedAttachmentReader.read(stream)
        } ?: throw IllegalArgumentException("Unable to read attachment")
    }

    private fun schedule(store: AuroraStore, address: String, body: String, at: Long, subId: Int): Long {
        require(address.isNotBlank()) { "Recipient number is required" }
        require(body.isNotBlank()) { "Message text is required" }
        require(at > System.currentTimeMillis()) { "Scheduled time must be in the future" }
        val id = store.schedule(address, body, at, subId)
        try {
            ScheduledMessageAlarms.arm(context, id, at)
        } catch (error: Exception) {
            store.cancelScheduled(id)
            throw error
        }
        return id
    }

    private fun cancelAlarm(id: Long) {
        ScheduledMessageAlarms.cancel(context, id)
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

    private fun importBackup(uri: Uri): Boolean {
        check(SmsAccess.isDefaultSmsApp(context)) {
            "Set this app as default before restoring a backup"
        }
        val bytes = context.contentResolver.openInputStream(uri)?.use { input ->
            val output = java.io.ByteArrayOutputStream()
            val buffer = ByteArray(64 * 1024)
            var total = 0
            while (true) {
                val read = input.read(buffer)
                if (read <= 0) break
                total += read
                require(total <= 32 * 1024 * 1024) { "Backup exceeds 32 MB" }
                output.write(buffer, 0, read)
            }
            output.toByteArray()
        } ?: return false
        if (bytes.isEmpty()) return false
        val root = JSONObject(String(bytes, Charsets.UTF_8))

        val existing = HashSet<String>()
        context.contentResolver.query(
            Telephony.Sms.CONTENT_URI,
            arrayOf("address", "date", "body"),
            null,
            null,
            null,
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                existing.add(
                    backupKey(cursor.getString(0), cursor.getLong(1), cursor.getString(2)),
                )
            }
        }

        var inserted = 0
        AuroraStore(context).use { store ->
            root.optJSONArray("messages")?.let { messages ->
                val count = minOf(messages.length(), 20_000)
                for (index in 0 until count) {
                    val message = messages.optJSONObject(index) ?: continue
                    val address = message.optString("address").trim()
                    val body = message.optString("body")
                    val date = message.optLong("date", 0)
                    val type = message.optInt("type", 1)
                    if (address.isEmpty() || date <= 0 || type !in 1..2) continue
                    if (!existing.add(backupKey(address, date, body))) continue
                    val values = ContentValues().apply {
                        put("address", address)
                        put("body", body)
                        put("date", date)
                        put("date_sent", date)
                        put("type", type)
                        put("read", if (message.optBoolean("read", true)) 1 else 0)
                        put("seen", 1)
                        val subscription = message.optInt("subscriptionId", -1)
                        if (subscription >= 0) put("sub_id", subscription)
                    }
                    try {
                        if (context.contentResolver.insert(Telephony.Sms.CONTENT_URI, values) != null) {
                            inserted += 1
                        }
                    } catch (_: Exception) {

                    }
                }
            }

            root.optJSONArray("blocked")?.let { blocked ->
                for (index in 0 until minOf(blocked.length(), 5_000)) {
                    val entry = blocked.optJSONObject(index) ?: continue
                    val address = entry.optString("address").trim()
                    if (address.isNotEmpty()) store.block(address, entry.optString("note"))
                }
            }

            root.optJSONArray("drafts")?.let { drafts ->
                for (index in 0 until minOf(drafts.length(), 5_000)) {
                    val entry = drafts.optJSONObject(index) ?: continue
                    val address = entry.optString("address").trim()
                    if (address.isNotEmpty()) store.saveDraft(address, entry.optString("body"))
                }
            }

            root.optJSONArray("threadState")?.let { states ->
                for (index in 0 until minOf(states.length(), 5_000)) {
                    val entry = states.optJSONObject(index) ?: continue
                    val address = entry.optString("address").trim()
                    if (address.isEmpty()) continue
                    val threadId = try {
                        Telephony.Threads.getOrCreateThreadId(context, address)
                    } catch (_: Exception) {
                        continue
                    }
                    if (entry.optBoolean("pinned", false)) store.setPinned(threadId, true)
                    if (entry.optBoolean("archived", false)) store.setArchived(threadId, true)
                }
            }
        }
        return inserted >= 0
    }

    private fun backupKey(address: String?, date: Long, body: String?): String =
        "${address.orEmpty()}|$date|${body.orEmpty().hashCode()}"

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
            put("drafts", JSONArray().apply {
                AuroraStore(context).use { store ->
                    store.draftsAll().forEach { (address, body) ->
                        put(JSONObject().apply {
                            put("address", address)
                            put("body", body)
                        })
                    }
                }
            })
            put("threadState", JSONArray().apply {
                val addresses = HashMap<Long, String>()
                context.contentResolver.query(
                    Telephony.Sms.CONTENT_URI,
                    arrayOf("thread_id", "address"),
                    null,
                    null,
                    null,
                )?.use { cursor ->
                    while (cursor.moveToNext()) {
                        addresses.putIfAbsent(cursor.getLong(0), cursor.getString(1) ?: "")
                    }
                }
                AuroraStore(context).use { store ->
                    store.states().forEach { (threadId, state) ->
                        val address = addresses[threadId]
                        if (!address.isNullOrEmpty()) {
                            put(JSONObject().apply {
                                put("address", address)
                                put("pinned", state.pinned)
                                put("archived", state.archived)
                            })
                        }
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

    
    private fun searchCorpus(store: AuroraStore): List<Map<String, Any?>> {
        val hidden = store.hiddenIds()
        val rows = mutableListOf<Map<String, Any?>>()
        context.contentResolver.query(
            Telephony.Sms.CONTENT_URI,
            arrayOf("_id", "thread_id", "address", "body", "date", "read"),
            null,
            null,
            "date DESC",
        )?.use { cursor ->
            while (cursor.moveToNext() && rows.size < 50_000) {
                val id = cursor.getLong(0)
                if (id in hidden) continue
                val body = cursor.getString(3) ?: ""
                if (body.isEmpty()) continue
                rows.add(
                    mapOf(
                        "id" to id,
                        "threadId" to cursor.getLong(1),
                        "address" to (cursor.getString(2) ?: ""),
                        "body" to body,
                        "date" to cursor.getLong(4),
                        "read" to (cursor.getInt(5) != 0),
                    ),
                )
            }
        }
        var mms = 0
        context.contentResolver.query(
            Telephony.Mms.CONTENT_URI,
            arrayOf("_id", "thread_id", "date", "sub", "read"),
            null,
            null,
            "date DESC",
        )?.use { cursor ->
            while (cursor.moveToNext() && mms < 5_000) {
                val id = cursor.getLong(0)
                if (MessageIdentity.mms(id) in hidden) continue
                val subject = cursor.getString(3) ?: ""
                if (subject.isEmpty()) continue
                val address = "MMS"
                rows.add(
                    mapOf(
                        "id" to -id,
                        "threadId" to cursor.getLong(1),
                        "address" to address,
                        "body" to subject,
                        "date" to cursor.getLong(2) * 1000,
                        "read" to (cursor.getInt(4) != 0),
                    ),
                )
                mms += 1
            }
        }
        return rows
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
                        "address" to (cursor.getString(2) ?: "Unknown number"),
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
        require(address.isNotBlank()) { "Remote message is missing a number" }
        require(body.isNotBlank()) { "Remote message is missing text" }
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
            ?: throw IllegalArgumentException("Unable to write to the system message store")
        val id = ContentUris.parseId(uri)
        AuroraStore(context).use { it.markRemote(id) }
        return id
    }

    private fun notificationCapabilities(): Map<String, Any?> {
        val power = context.getSystemService(PowerManager::class.java)
        return mapOf(
            "fluidCloud" to Notifications.canPromote(context),
            "fluidCloudActive" to Notifications.promotionActive(context),
            "fluidCloudEnabled" to Notifications.fluidCloudEnabled(context),
            "batteryUnrestricted" to power.isIgnoringBatteryOptimizations(context.packageName),
            "sdk" to Build.VERSION.SDK_INT,
            "manufacturer" to Build.MANUFACTURER,
        )
    }

    private fun requestBatteryUnrestricted(): Boolean {
        val power = context.getSystemService(PowerManager::class.java)
        if (power.isIgnoringBatteryOptimizations(context.packageName)) return true
        return try {
            activity.startActivity(
                Intent(
                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                    Uri.parse("package:${context.packageName}"),
                ),
            )
            true
        } catch (_: Exception) {
            try {
                activity.startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
            } catch (_: Exception) {}
            false
        }
    }

    
    private fun openAutoStartSettings(): Boolean {
        val candidates = listOf(
            "com.coloros.safecenter/com.coloros.safecenter.permission.startup.StartupAppListActivity",
            "com.coloros.safecenter/com.coloros.safecenter.startupapp.StartupAppListActivity",
            "com.oplus.battery/com.oplus.battery.startupapp.StartupAppListActivity",
            "com.oneplus.security/com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity",
            "com.coloros.oppoguardelf/com.coloros.powermanager.fuelgaue.PowerUsageModelActivity",
        )
        for (flattened in candidates) {
            val component = ComponentName.unflattenFromString(flattened) ?: continue
            try {
                activity.startActivity(Intent().setComponent(component))
                return true
            } catch (_: Exception) {
            }
        }
        return try {
            activity.startActivity(
                Intent(
                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.parse("package:${context.packageName}"),
                ),
            )
            false
        } catch (_: Exception) {
            false
        }
    }

    private fun syncStatus(): Map<String, Any?> = mapOf(
        "enabled" to syncPrefs.readFlag("enabled", false),
        "serverUrl" to (syncPrefs.getString("serverUrl", "") ?: ""),
        "deviceName" to (syncPrefs.getString("deviceName", Build.MODEL) ?: Build.MODEL),
        "fingerprint" to (syncPrefs.getString("fingerprint", "") ?: ""),
        "lastSync" to syncPrefs.getLong("lastSync", 0),
        "pending" to syncPrefs.getInt("pending", 0),
        "devices" to emptyList<Map<String, Any?>>(),
    )
}
