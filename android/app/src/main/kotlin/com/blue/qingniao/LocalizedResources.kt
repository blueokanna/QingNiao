package com.blue.qingniao

import android.content.Context
import android.content.SharedPreferences
import android.content.res.Configuration
import android.os.LocaleList

fun SharedPreferences.readFlag(key: String, fallback: Boolean): Boolean =
    AppPrefs.bool(this, key, fallback)

object LocalizedResources {
    fun text(context: Context, resource: Int): String {
        val language = context.getSharedPreferences("appearance", Context.MODE_PRIVATE)
            .getString("locale", "system")
        if (language == null || language == "system") return context.getString(resource)
        val configuration = Configuration(context.resources.configuration)
        configuration.setLocales(LocaleList.forLanguageTags(language))
        return context.createConfigurationContext(configuration).getString(resource)
    }
}
