package com.blue.qingniao

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailabilityLight
import com.google.firebase.installations.FirebaseInstallations
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

object PushGateway {
    private const val CHANNEL = "network_sync"
    private const val NOTICE = 4102
    @Volatile var onSignal: (() -> Unit)? = null
    private fun prefs(context: Context) = context.getSharedPreferences("network_push", Context.MODE_PRIVATE)
    private fun configured(context: Context) = FirebaseApp.getApps(context).isNotEmpty()

    fun handle(context: Context, call: MethodCall, result: MethodChannel.Result): Boolean {
        if (call.method !in setOf("pushStatus", "pushSetEnabled", "pushRegistrationId")) return false
        val settings = prefs(context)
        val available = configured(context)
        val services = GoogleApiAvailabilityLight.getInstance().isGooglePlayServicesAvailable(context) == ConnectionResult.SUCCESS
        if (call.method == "pushStatus") {
            result.success(mapOf("configured" to available, "services" to services,
                "enabled" to settings.getBoolean("enabled", false)))
            return true
        }
        if (!available || !services) {
            result.error("push_unavailable", "Firebase configuration and Google Play services are required", null)
            return true
        }
        val messaging = FirebaseMessaging.getInstance()
        if (call.method == "pushRegistrationId") {
            if (!settings.getBoolean("enabled", false)) {
                result.error("push_disabled", "Network push is disabled", null)
            } else messaging.register().continueWithTask { registration ->
                if (!registration.isSuccessful) throw registration.exception ?: IllegalStateException("FCM registration failed")
                FirebaseInstallations.getInstance().id
            }.addOnCompleteListener { task ->
                if (task.isSuccessful) result.success(task.result)
                else result.error("push_registration_failed", "Unable to register for network push", null)
            }
            return true
        }
        val enabled = call.argument<Boolean>("enabled") == true
        messaging.isAutoInitEnabled = enabled
        settings.edit().putBoolean("enabled", enabled).remove("recent").apply()
        if (enabled) {
            messaging.register().addOnCompleteListener { task ->
                if (task.isSuccessful) result.success(null)
                else {
                    settings.edit().putBoolean("enabled", false).apply()
                    messaging.isAutoInitEnabled = false
                    result.error("push_registration_failed", "Unable to register for network push", null)
                }
            }
        } else {
            context.getSystemService(NotificationManager::class.java).cancel(NOTICE)
            messaging.unregister().addOnCompleteListener { task ->
                if (task.isSuccessful) result.success(null)
                else result.error("push_unregister_failed", "Push is disabled locally; registration revocation could not reach Firebase", null)
            }
        }
        return true
    }

    @Synchronized fun receive(context: Context, message: RemoteMessage) {
        val settings = prefs(context)
        if (!settings.getBoolean("enabled", false) || message.notification != null) return
        val raw = context.getSharedPreferences("aurora_sync", Context.MODE_PRIVATE).getString("state", "")
        val state = runCatching { JSONObject(raw.orEmpty()) }.getOrNull() ?: return
        if (!state.optBoolean("enabled") || !NetworkPushPolicy.accepts(message.data,
                state.optString("spaceId"), message.sentTime, System.currentTimeMillis(), message.messageId)) return
        val id = requireNotNull(message.messageId)
        val recent = runCatching { JSONArray(settings.getString("recent", "[]")) }.getOrDefault(JSONArray())
        val ids = (0 until recent.length()).map { recent.optString(it) }
        if (id in ids) return
        settings.edit().putString("recent", JSONArray((ids + id).takeLast(64)).toString()).apply()
        Handler(Looper.getMainLooper()).post { onSignal?.invoke() }
        val appearance = context.getSharedPreferences("appearance", Context.MODE_PRIVATE)
        if (!AppPrefs.bool(appearance, "notifications", true)) return
        val manager = context.getSystemService(NotificationManager::class.java)
        if (!manager.areNotificationsEnabled()) return
        manager.createNotificationChannel(NotificationChannel(CHANNEL,
            LocalizedResources.text(context, R.string.push_title), NotificationManager.IMPORTANCE_DEFAULT))
        val intent = Intent(context, MainActivity::class.java)
            .putExtra("remoteSync", true).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val open = PendingIntent.getActivity(context, NOTICE, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification = Notification.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_message)
            .setContentTitle(LocalizedResources.text(context, R.string.push_title))
            .setContentText(LocalizedResources.text(context, R.string.push_body))
            .setContentIntent(open).setAutoCancel(true).setOnlyAlertOnce(true)
            .setVisibility(Notification.VISIBILITY_PRIVATE).build()
        manager.notify(NOTICE, notification)
    }
}

class NetworkPushService : FirebaseMessagingService() {
    override fun onMessageReceived(message: RemoteMessage) { PushGateway.receive(this, message) }
    override fun onRegistered(installationId: String) {
        Handler(Looper.getMainLooper()).post { PushGateway.onSignal?.invoke() }
    }
}
