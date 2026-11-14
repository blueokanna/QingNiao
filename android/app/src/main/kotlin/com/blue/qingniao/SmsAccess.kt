package com.blue.qingniao

import android.app.role.RoleManager
import android.content.Context
import android.content.pm.PackageManager
import android.provider.Settings
import android.provider.Telephony
import android.util.Log

/**
 * 默认短信应用的判定。
 *
 * 部分 OEM（ColorOS / HyperOS 等）通过 RoleManager 授予短信角色后并不会同步写入
 * Settings.Secure 的 s ms_default_application，而旧接口 getDefaultSmsPackage 在个别
 * 版本上会返回 null，导致应用明明已经是默认短信应用却仍被判定为未授权。
 * 这里以 RoleManager 为准，再回退到两套旧接口。
 */
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
