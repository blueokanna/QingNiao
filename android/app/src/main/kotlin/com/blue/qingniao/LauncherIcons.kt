package com.blue.qingniao

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build

object LauncherIcons {
    private val components = mapOf("bird" to "LauncherBird", "leaf" to "LauncherLeaf", "chat" to "LauncherChat")

    fun select(context: Context, key: String) {
        require(key in components) { "Unknown launcher icon" }
        val manager = context.packageManager
        fun component(name: String) = ComponentName(context, "${context.packageName}.$name")
        if (Build.VERSION.SDK_INT >= 33) {
            manager.setComponentEnabledSettings(components.map { (id, name) ->
                PackageManager.ComponentEnabledSetting(component(name), if (id == key) PackageManager.COMPONENT_ENABLED_STATE_ENABLED else PackageManager.COMPONENT_ENABLED_STATE_DISABLED, PackageManager.DONT_KILL_APP)
            })
        } else {
            // Enable the replacement before disabling existing aliases on older launchers.
            manager.setComponentEnabledSetting(component(components.getValue(key)), PackageManager.COMPONENT_ENABLED_STATE_ENABLED, PackageManager.DONT_KILL_APP)
            components.filterKeys { it != key }.values.forEach { manager.setComponentEnabledSetting(component(it), PackageManager.COMPONENT_ENABLED_STATE_DISABLED, PackageManager.DONT_KILL_APP) }
        }
        context.getSharedPreferences("appearance", Context.MODE_PRIVATE).edit().putString("launcherIcon", key).apply()
    }
}
