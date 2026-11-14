package com.blue.qingniao

import android.app.role.RoleManager
import android.content.Context
import android.content.pm.PackageManager
import android.provider.Settings
import android.provider.Telephony
import android.util.Log


object SmsAccess {
    private const val TAG = "QingniaoAccess"
    private const val LEGACY_SETTING = "sms_default_application"

    fun isDefaultSmsApp(context: Context): Boolean {
        val legacy = runCatching { Telephony.Sms.getDefaultSmsPackage(context) }.getOrNull()
        val setting = runCatching {
            Settings.Secure.getString(context.contentResolver, LEGACY_SETTING)
        }.getOrNull()
        val roleHeld = runCatching {
            val roles = context.getSystemService(RoleManager::class.java)
            roles != null && roles.isRoleAvailable(RoleManager.ROLE_SMS) && roles.isRoleHeld(RoleManager.ROLE_SMS)
        }.getOrDefault(false)
        val default = roleHeld || legacy == context.packageName || setting == context.packageName
        Log.d(TAG, "isDefaultSmsApp legacy=$legacy setting=$setting roleHeld=$roleHeld -> $default")
        return default
    }

    fun granted(context: Context, permission: String): Boolean =
        context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    fun roleAvailable(context: Context): Boolean = runCatching {
        context.getSystemService(RoleManager::class.java)?.isRoleAvailable(RoleManager.ROLE_SMS) ?: false
    }.getOrDefault(false)
}
