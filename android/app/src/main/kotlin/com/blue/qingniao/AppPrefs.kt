package com.blue.qingniao

import android.content.SharedPreferences


object AppPrefs {
    // Older builds stored string flags; typed reads can crash SMS receivers.
    fun bool(prefs: SharedPreferences, key: String, fallback: Boolean): Boolean {
        val raw = runCatching { prefs.all[key] }.getOrNull() ?: return fallback
        return when (raw) {
            is Boolean -> raw
            is String -> when (raw.lowercase(java.util.Locale.ROOT)) {
                "true" -> true
                "false" -> false
                else -> fallback
            }
            is Number -> raw.toInt() != 0
            else -> fallback
        }
    }
}
