package com.blue.qingniao

import android.Manifest
import android.app.role.RoleManager
import android.content.Intent
import android.content.pm.PackageManager
import android.database.ContentObserver
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.Telephony
import android.telephony.SubscriptionManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val appearance by lazy { AppearanceBridge(this) }
    private val handler = Handler(Looper.getMainLooper())
    private var events: EventChannel.EventSink? = null
    private var pendingAccess: MethodChannel.Result? = null
    private var pendingSelection: MethodChannel.Result? = null
    private val changed = Runnable { events?.success("messages") }
    private val observer = object : ContentObserver(handler) {
        override fun onChange(selfChange: Boolean) { handler.removeCallbacks(changed); handler.postDelayed(changed, 180) }
    }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.blue.qingniao/messages").setMethodCallHandler(::handle)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "com.blue.qingniao/changes").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink) { events = sink }
            override fun onCancel(arguments: Any?) { events = null }
        })
        contentResolver.registerContentObserver(Uri.parse("content://mms-sms"), true, observer)
        contentResolver.registerContentObserver(Telephony.Sms.CONTENT_URI, true, observer)
    }
    private fun access() = mapOf(
        "defaultApp" to (Telephony.Sms.getDefaultSmsPackage(this) == packageName),
        "readSms" to (checkSelfPermission(Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED),
        "sendSms" to (checkSelfPermission(Manifest.permission.SEND_SMS) == PackageManager.PERMISSION_GRANTED),
        "receiveSms" to (checkSelfPermission(Manifest.permission.RECEIVE_SMS) == PackageManager.PERMISSION_GRANTED),
        "readContacts" to (checkSelfPermission(Manifest.permission.READ_CONTACTS) == PackageManager.PERMISSION_GRANTED),
        "notifications" to getSystemService(android.app.NotificationManager::class.java).areNotificationsEnabled(),
        "roleAvailable" to getSystemService(RoleManager::class.java).isRoleAvailable(RoleManager.ROLE_SMS)
    )
    private fun requireAccess() {
        val state = access()
        check(listOf("defaultApp", "readSms", "sendSms", "receiveSms").all { state[it] == true }) { "请设置默认短信应用并授予短信权限" }
    }
    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            if (appearance.handle(call, result)) return
        } catch (_: Exception) {
            result.error("appearance_unavailable", "无法读取系统外观设置", null)
            return
        }
        when (call.method) {
            "pickContact", "pickAttachment" -> {
                if (pendingSelection != null) { result.error("busy", "选择器已打开", null); return }
                pendingSelection = result
                val selection = if (call.method == "pickContact") Intent(Intent.ACTION_PICK, android.provider.ContactsContract.CommonDataKinds.Phone.CONTENT_URI)
                    else Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("*/*").putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("image/*", "audio/*", "video/*"))
                try { startActivityForResult(selection, if (call.method == "pickContact") 73 else 74) }
                catch (_: android.content.ActivityNotFoundException) { pendingSelection = null; result.error("unavailable", "设备没有可用的选择器", null) }
                return
            }
            "access" -> { result.success(access()); return }
            "requestAccess" -> {
                if (pendingAccess != null) { result.error("busy", "权限申请正在进行", null); return }
                pendingAccess = result
                val roles = getSystemService(RoleManager::class.java)
                if (!roles.isRoleAvailable(RoleManager.ROLE_SMS)) { pendingAccess = null; result.error("unavailable", "设备不支持默认短信应用", null); return }
                if (!roles.isRoleHeld(RoleManager.ROLE_SMS)) startActivityForResult(roles.createRequestRoleIntent(RoleManager.ROLE_SMS), 71)
                else requestMessagePermissions()
                return
            }
            "launchIntent" -> {
                val address = intent.getStringExtra("address") ?: intent.data?.takeIf { it.scheme in setOf("sms", "smsto", "mms", "mmsto") }?.schemeSpecificPart?.substringBefore('?')
                result.success(mapOf("address" to address, "body" to intent.getStringExtra("sms_body")))
                intent = Intent(this, MainActivity::class.java)
                return
            }
            "settings" -> { startActivity(Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))); result.success(null); return }
        }
        MessageIo.executor.execute {
            try {
                requireAccess()
                val value: Any? = MessageStore(this).use { store ->
                    val repository = SmsRepository(this, store)
                    when (call.method) {
                        "conversations" -> repository.conversations(call.argument<String>("query")?.take(200) ?: "")
                        "mmsMessages" -> MmsRepository(this).messages(call.argument<Number>("before")?.toLong() ?: Long.MAX_VALUE)
                        "mmsImage" -> MmsRepository(this).image(requireNotNull(call.argument<Number>("id")).toLong())
                        "retryMms" -> { MmsTransport.retry(this); null }
                        "sendMms" -> { MmsTransport.send(this, requireNotNull(call.argument<List<String>>("recipients")), requireNotNull(call.argument("body")), call.argument<Number>("subscriptionId")?.toInt() ?: SubscriptionManager.getDefaultSmsSubscriptionId(), call.argument<String>("attachment")?.let(Uri::parse)); null }
                        "messages" -> repository.messages(call.argument<Number>("threadId")?.toLong(), call.argument<Number>("before")?.toLong() ?: Long.MAX_VALUE, trash = call.argument<Boolean>("trash") == true)
                        "markRead" -> { repository.markRead(requireNotNull(call.argument<Number>("threadId")).toLong()); null }
                        "send" -> SmsTransport.send(this, store, requireNotNull(call.argument("address")), requireNotNull(call.argument("body")), call.argument<Number>("subscriptionId")?.toInt() ?: SubscriptionManager.getDefaultSmsSubscriptionId())
                        "hide" -> { store.hide(requireNotNull(call.argument<Number>("id")).toLong()); null }
                        "restore" -> { store.restore(requireNotNull(call.argument<Number>("id")).toLong()); null }
                        "delete" -> { repository.delete(requireNotNull(call.argument<Number>("id")).toLong()); null }
                        "draft" -> store.draft(requireNotNull(call.argument("address")))
                        "saveDraft" -> { store.saveDraft(requireNotNull(call.argument("address")), requireNotNull(call.argument("body"))); null }
                        "subscriptions" -> {
                            if (checkSelfPermission(Manifest.permission.READ_PHONE_STATE) != PackageManager.PERMISSION_GRANTED) emptyList<Map<String, Any>>()
                            else getSystemService(SubscriptionManager::class.java).activeSubscriptionInfoList.orEmpty().map { mapOf("id" to it.subscriptionId, "name" to it.displayName.toString(), "slot" to it.simSlotIndex + 1) }
                        }
                        else -> throw IllegalArgumentException("不支持的操作")
                    }
                }
                handler.post { result.success(value) }
            } catch (error: Exception) {
                val message = when (error) { is SecurityException -> "短信权限已撤销，请重新授权"; is IllegalArgumentException, is IllegalStateException -> error.message ?: "操作无法完成"; else -> "系统消息服务暂时不可用，请重试" }
                handler.post { result.error("message_operation_failed", message, null) }
            }
        }
    }
    private fun requestMessagePermissions() {
        val permissions = mutableListOf(Manifest.permission.READ_SMS, Manifest.permission.SEND_SMS, Manifest.permission.RECEIVE_SMS, Manifest.permission.RECEIVE_MMS, Manifest.permission.RECEIVE_WAP_PUSH, Manifest.permission.READ_PHONE_STATE, Manifest.permission.READ_PHONE_NUMBERS)
        if (android.os.Build.VERSION.SDK_INT >= 33) permissions.add(Manifest.permission.POST_NOTIFICATIONS)
        val missing = permissions.filter { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }.toTypedArray()
        if (missing.isEmpty()) { pendingAccess?.success(access()); pendingAccess = null }
        else requestPermissions(missing, 72)
    }
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 73 || requestCode == 74) {
            val result = pendingSelection ?: return
            pendingSelection = null
            val selected = data?.data
            if (resultCode != RESULT_OK || selected == null) { result.success(null); return }
            MessageIo.executor.execute {
                try {
                    val value: Any? = if (requestCode == 73) contentResolver.query(selected, arrayOf(android.provider.ContactsContract.CommonDataKinds.Phone.NUMBER), null, null, null)?.use { if (it.moveToFirst()) it.getString(0) else null }
                    else {
                        val type = contentResolver.getType(selected) ?: "application/octet-stream"
                        require(listOf("image/", "audio/", "video/").any(type::startsWith))
                        mapOf("uri" to selected.toString(), "type" to type)
                    }
                    handler.post { result.success(value) }
                } catch (_: Exception) { handler.post { result.error("selection_failed", "无法读取所选内容", null) } }
            }
            return
        }
        if (requestCode == 71) {
            if (access()["defaultApp"] == true) requestMessagePermissions()
            else { pendingAccess?.success(access()); pendingAccess = null }
        }
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 72) { pendingAccess?.success(access()); pendingAccess = null }
    }
    override fun onNewIntent(intent: Intent) { super.onNewIntent(intent); setIntent(intent); events?.success("intent") }
    override fun onDestroy() {
        contentResolver.unregisterContentObserver(observer)
        handler.removeCallbacks(changed)
        events = null
        pendingAccess?.error("activity_closed", "权限申请已结束，请重试", null)
        pendingAccess = null
        pendingSelection?.error("activity_closed", "选择已取消", null)
        pendingSelection = null
        super.onDestroy()
    }
}
