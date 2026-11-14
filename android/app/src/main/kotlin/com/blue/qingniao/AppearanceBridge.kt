package com.blue.qingniao

import android.app.Activity
import android.app.NotificationManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class AppearanceBridge(private val activity: Activity) {
    private val preferences = activity.getSharedPreferences("appearance", Activity.MODE_PRIVATE)
    private val choices = mapOf(
        "themeMode" to setOf("system", "light", "dark", "amoled"),
        "fontFamily" to setOf("system", "harmony", "google"),
        "seed" to setOf("青碧", "极光", "湖水", "晨曦", "梅子", "石墨"),
        "motion" to setOf("full", "balanced", "reduced"),
        "bubble" to setOf("soft", "capsule", "cookie")
    )
    private val booleans = setOf("useDynamic", "amoled", "morph", "delivery", "notifications", "preview", "sendDelay", "lowPowerAurora")

    fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {
            "setLauncherIcon" -> {
                LauncherIcons.select(activity, requireNotNull(call.argument<String>("icon")))
                result.success(null)
            }
            "systemSeed" -> result.success(String.format("#%08X", activity.getColor(android.R.color.system_accent1_500)))
            "systemPalette" -> result.success(palette())
            "settingsAll" -> result.success(preferences.all.mapValues { it.value.toString() })
            "settingsSet" -> {
                val key = call.argument<String>("key")
                val value = call.argument<String>("value")
                val valid = when {
                    key == null || value == null -> false
                    key in choices -> value in choices.getValue(key)
                    key in booleans -> value == "true" || value == "false"
                    key == "fontScale" -> value.toDoubleOrNull()?.let { it.isFinite() && it in 0.85..1.5 } == true
                    key == "trashDays" -> value.toIntOrNull() in setOf(0, 7, 30, 90)
                    key == "signature" -> value.length <= 160
                    else -> false
                }
                if (!valid) result.error("invalid_setting", "设置值无效", null)
                else { preferences.edit().putString(key, value).apply(); result.success(null) }
            }
            "deviceDiagnostics" -> {
                val power = activity.getSystemService(PowerManager::class.java)
                result.success(mapOf(
                    "manufacturer" to Build.MANUFACTURER,
                    "model" to Build.MODEL,
                    "sdk" to Build.VERSION.SDK_INT,
                    "notificationsEnabled" to activity.getSystemService(NotificationManager::class.java).areNotificationsEnabled(),
                    "batteryRestricted" to activity.getSystemService(android.app.ActivityManager::class.java).isBackgroundRestricted,
                    "batteryOptimizationExcluded" to power.isIgnoringBatteryOptimizations(activity.packageName),
                    "powerSaveMode" to power.isPowerSaveMode
                ))
            }
            "notificationSettings" -> launch(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName), result)
            "appSettings" -> launch(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${activity.packageName}")), result)
            "batterySettings" -> launch(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS), result)
            else -> return false
        }
        return true
    }

    private fun launch(intent: Intent, result: MethodChannel.Result) {
        try { activity.startActivity(intent); result.success(null) }
        catch (_: android.content.ActivityNotFoundException) { result.error("unavailable", "系统没有提供此设置页面", null) }
    }

    private fun palette(): Map<String, List<Int>> {
        val resources = activity.resources
        val tones = listOf(0, 10, 50, 100, 200, 300, 400, 500, 600, 700, 800, 900, 1000)
        return listOf("accent1", "accent2", "accent3", "neutral1", "neutral2").associateWith { family ->
            tones.map { tone ->
                val id = resources.getIdentifier("system_${family}_$tone", "color", "android")
                check(id != 0) { "System color palette unavailable" }
                activity.getColor(id)
            }
        }
    }
}
