package com.blue.qingniao

import android.app.role.RoleManager
import android.content.Context
import android.content.pm.PackageManager
import android.provider.Telephony


object SmsAccess {
    fun isDefaultSmsApp(context: Context): Boolean {
        return runCatching {
            val roles = context.getSystemService(RoleManager::class.java)
            if (roles != null && roles.isRoleAvailable(RoleManager.ROLE_SMS)) {
                roles.isRoleHeld(RoleManager.ROLE_SMS)
            } else {
                Telephony.Sms.getDefaultSmsPackage(context) == context.packageName
            }
        }.getOrDefault(false)
    }

    fun granted(context: Context, permission: String): Boolean =
        context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    fun roleAvailable(context: Context): Boolean = runCatching {
        context.getSystemService(RoleManager::class.java)?.isRoleAvailable(RoleManager.ROLE_SMS) ?: false
    }.getOrDefault(false)
}
