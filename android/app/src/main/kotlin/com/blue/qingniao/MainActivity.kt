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
    private val cadence by lazy { DisplayCadence(this) }
    private val appearance by lazy { AppearanceBridge(this) }
    private val aurora by lazy { AuroraBridge(this) }
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
        PushGateway.onSignal = { events?.success("sync") }

        val appContext = applicationContext
        MessageIo.executor.execute {
            SmsSendWatchdog.sweep(appContext)
            try { ScheduledMessageAlarms.restore(appContext) }
            catch (_: Exception) { android.util.Log.w("ScheduleRecovery", "Unable to restore scheduled alarms") }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.blue.qingniao/messages").setMethodCallHandler(::handle)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "com.blue.qingniao/changes").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink) { events = sink }
            override fun onCancel(arguments: Any?) { events = null }
        })
        contentResolver.registerContentObserver(Uri.parse("content://mms-sms"), true, observer)
        contentResolver.registerContentObserver(Telephony.Sms.CONTENT_URI, true, observer)
    }
    private fun access() = mapOf(
        "defaultApp" to SmsAccess.isDefaultSmsApp(this),
        "readSms" to SmsAccess.granted(this, Manifest.permission.READ_SMS),
        "sendSms" to SmsAccess.granted(this, Manifest.permission.SEND_SMS),
        "receiveSms" to SmsAccess.granted(this, Manifest.permission.RECEIVE_SMS),
        "readContacts" to SmsAccess.granted(this, Manifest.permission.READ_CONTACTS),
        "notifications" to getSystemService(android.app.NotificationManager::class.java).areNotificationsEnabled(),
        "roleAvailable" to SmsAccess.roleAvailable(this),
        "systemSmsPackage" to Telephony.Sms.getDefaultSmsPackage(this)
    )
    private fun requireAccess() {
        val state = access()
        check(listOf("defaultApp", "readSms", "sendSms", "receiveSms").all { state[it] == true }) { "Set the default SMS role and grant SMS permissions" }
    }
    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            if (PushGateway.handle(this, call, result)) return
            if (appearance.handle(call, result)) return
        } catch (_: Exception) {
            result.error("appearance_unavailable", "Unable to read appearance settings", null)
            return
        }
        if (aurora.handle(call, result)) return
        when (call.method) {
            "copySensitive" -> {
                val text = call.argument<String>("text")
                if (text == null || text.length > 120_000) {
                    result.error("clipboard_limit", "Selection is too large to copy", null)
                    return
                }
                val clip = android.content.ClipData.newPlainText("Qingniao", text)
                clip.description.extras = android.os.PersistableBundle().apply {
                    putBoolean("android.content.extra.IS_SENSITIVE", true)
                }
                getSystemService(android.content.ClipboardManager::class.java).setPrimaryClip(clip)
                result.success(null)
                return
            }
            "pickContact", "pickAttachment", "pickFirebaseConfiguration" -> {
                if (pendingSelection != null) { result.error("busy", "A picker is already open", null); return }
                pendingSelection = result
                val selection = when (call.method) {
                    "pickContact" -> Intent(Intent.ACTION_PICK, android.provider.ContactsContract.CommonDataKinds.Phone.CONTENT_URI)
                    "pickFirebaseConfiguration" -> Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("*/*")
                    else -> Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("*/*").putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("image/*", "audio/*", "video/*"))
                }
                val request = when(call.method) { "pickContact" -> 73; "pickFirebaseConfiguration" -> 75; else -> 74 }
                try { startActivityForResult(selection, request) }
                catch (_: android.content.ActivityNotFoundException) { pendingSelection = null; result.error("unavailable", "No picker is available", null) }
                return
            }
            "openFirebaseConsole" -> {
                try { startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://console.firebase.google.com/"))); result.success(null) }
                catch (_: android.content.ActivityNotFoundException) { result.error("unavailable", "No browser is available", null) }
                return
            }
            "access" -> { result.success(access()); return }
            "requestAccess" -> {
                if (pendingAccess != null) { result.error("busy", "A permission request is already in progress", null); return }
                pendingAccess = result
                val roles = getSystemService(RoleManager::class.java)
                try {
                    if (!roles.isRoleAvailable(RoleManager.ROLE_SMS)) {
                        pendingAccess = null
                        result.error("role_unavailable", "The system SMS role is unavailable", null)
                    } else if (!roles.isRoleHeld(RoleManager.ROLE_SMS)) {
                        startActivityForResult(roles.createRequestRoleIntent(RoleManager.ROLE_SMS), 71)
                    } else requestMessagePermissions()
                } catch (_: Exception) {
                    pendingAccess = null
                    result.error("role_unavailable", "Unable to open the system SMS role request", null)
                }
                return
            }
            "launchIntent" -> {
                val address = intent.getStringExtra("address") ?: intent.data?.takeIf { it.scheme in setOf("sms", "smsto", "mms", "mmsto") }?.schemeSpecificPart?.substringBefore('?')
                result.success(mapOf("address" to address, "body" to intent.getStringExtra("sms_body")))

                if (!address.isNullOrBlank()) Notifications.cancel(this, address.hashCode())
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
                        else -> throw IllegalArgumentException("Unsupported operation")
                    }
                }
                handler.post { result.success(value) }
            } catch (error: Exception) {
                val message = when (error) { is SecurityException -> "SMS permission was revoked. Grant permission again."; is IllegalArgumentException, is IllegalStateException -> error.message ?: "Unable to complete the action"; else -> "System messaging service unavailable. Try again." }
                handler.post { result.error("message_operation_failed", message, null) }
            }
        }
    }
    private fun requestMessagePermissions() {
        val permissions = mutableListOf(Manifest.permission.READ_SMS, Manifest.permission.SEND_SMS, Manifest.permission.RECEIVE_SMS, Manifest.permission.RECEIVE_MMS, Manifest.permission.RECEIVE_WAP_PUSH, Manifest.permission.READ_PHONE_STATE, Manifest.permission.READ_PHONE_NUMBERS, Manifest.permission.READ_CONTACTS)
        if (android.os.Build.VERSION.SDK_INT >= 33) permissions.add(Manifest.permission.POST_NOTIFICATIONS)
        val missing = permissions.filter { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }.toTypedArray()
        if (missing.isEmpty()) { pendingAccess?.success(access()); pendingAccess = null }
        else requestPermissions(missing, 72)
    }
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (aurora.onActivityResult(requestCode, resultCode, data)) return
        if (requestCode == 73 || requestCode == 74 || requestCode == 75) {
            val result = pendingSelection ?: return
            pendingSelection = null
            val selected = data?.data
            if (resultCode != RESULT_OK || selected == null) { result.success(null); return }
            MessageIo.executor.execute {
                try {
                    val value: Any? = if (requestCode == 73) contentResolver.query(selected, arrayOf(android.provider.ContactsContract.CommonDataKinds.Phone.NUMBER), null, null, null)?.use { if (it.moveToFirst()) it.getString(0) else null }
                    else if (requestCode == 75) {
                        val bytes = contentResolver.openInputStream(selected)?.use { BoundedAttachmentReader.read(it, 131_072) }
                            ?: throw IllegalArgumentException("Unable to read Firebase configuration")
                        require(bytes.size <= 131_072) { "Firebase configuration is too large" }
                        FirebaseProject.fromGoogleServices(bytes.toString(Charsets.UTF_8), packageName).fields()
                    } else {
                        val type = contentResolver.getType(selected) ?: "application/octet-stream"
                        require(listOf("image/", "audio/", "video/").any(type::startsWith))
                        mapOf("uri" to selected.toString(), "type" to type)
                    }
                    handler.post { result.success(value) }
                } catch (_: Exception) { handler.post { result.error("selection_failed", "Unable to read the selected content", null) } }
            }
            return
        }
        if (requestCode == 71) {


            if (SmsAccess.isDefaultSmsApp(this)) requestMessagePermissions()
            else { pendingAccess?.success(access()); pendingAccess = null }
        }
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 72) { pendingAccess?.success(access()); pendingAccess = null }
    }
    override fun onResume() { super.onResume(); cadence.resume() }
    override fun onPause() { cadence.pause(); super.onPause() }
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent); setIntent(intent)
        events?.success(if (intent.getBooleanExtra("remoteSync", false)) "sync" else "intent")
    }
    override fun onDestroy() {
        cadence.pause()
        PushGateway.onSignal = null
        contentResolver.unregisterContentObserver(observer)
        handler.removeCallbacks(changed)
        aurora.cancelPending()
        events = null
        pendingAccess?.error("activity_closed", "Permission request ended. Try again.", null)
        pendingAccess = null
        pendingSelection?.error("activity_closed", "Selection canceled", null)
        pendingSelection = null
        super.onDestroy()
    }
}
