package com.blue.qingniao

import android.content.SharedPreferences

/**
 * 外观/通知偏好是 Dart 与 Kotlin 共用的同一份 SharedPreferences。
 * Dart 侧一律以字符串写入，老版本也可能留下字符串，直接 getBoolean 会抛
 * ClassCastException 并让接收器崩溃（真机上表现为“收短信但完全没有通知”）。
 * 这里统一做宽容读取。
 */
object AppPrefs {
    fun bool(prefs: SharedPreferences, key: String, fallback: Boolean): Boolean {
        val raw = runCatching { prefs.all[key] }.getOrNull() ?: return fallback
        return when (raw) {
            is Boolean -> raw
            is String -> raw.equals("true", ignoreCase = true)
            is Number -> raw.toInt() != 0
            else -> fallback
        }
    }
}
