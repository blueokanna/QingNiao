package com.blue.qingniao

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

internal class AppUpdateBridge(private val activity: Activity) {
    private val handler = Handler(Looper.getMainLooper())
    private var pendingInstall: MethodChannel.Result? = null
    private var closed = false

    fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        val context = activity.applicationContext
        when (call.method) {
            "updateInfo" -> result.success(AppUpdates.snapshot(context))
            "checkForUpdate" -> {
                AppUpdates.check(context)
                result.success(AppUpdates.snapshot(context))
            }
            "downloadUpdate" -> {
                AppUpdates.download(context)
                result.success(AppUpdates.snapshot(context))
            }
            "openUpdateInstallSettings" -> {
                try {
                    activity.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:${activity.packageName}")))
                    result.success(null)
                } catch (_: Exception) {
                    result.error("installer_unavailable", "Unable to open install permission settings", null)
                }
            }
            "installUpdate" -> {
                if (!context.packageManager.canRequestPackageInstalls()) {
                    result.error("install_permission", "Allow updates from this app in system settings", null)
                    return true
                }
                if (pendingInstall != null) {
                    result.error("update_busy", "An installation request is already in progress", null)
                    return true
                }
                if (!AppUpdates.beginInstall()) {
                    result.error("update_busy", "The update is not ready for installation", null)
                    return true
                }
                pendingInstall = result
                AppUpdates.executor.execute {
                    val valid = runCatching { AppUpdates.verifiedInstallerFile(context) }.isSuccess
                    if (!valid) AppUpdates.invalidateDownload(context)
                    else AppUpdates.finishInstallVerification()
                    handler.post {
                        val reply = pendingInstall
                        pendingInstall = null
                        if (reply == null || closed) return@post
                        if (!valid) {
                            reply.error("invalid_update", "Update validation failed. Download the update again.", null)
                            return@post
                        }
                        try {
                            activity.startActivity(Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(Uri.parse("content://${context.packageName}.updates/qingniao-update.apk"),
                                    "application/vnd.android.package-archive")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            })
                            reply.success(null)
                        } catch (_: Exception) {
                            reply.error("installer_unavailable", "The Android package installer is unavailable", null)
                        }
                    }
                }
            }
            else -> return false
        }
        return true
    }

    fun close() {
        closed = true
        pendingInstall?.error("activity_closed", "Installation request ended", null)
        pendingInstall = null
    }
}
