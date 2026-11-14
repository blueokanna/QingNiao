package com.blue.qingniao

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.telephony.SubscriptionManager
import android.util.Log

/**
 * 仅 debug 构建包含的验证入口，方便用 adb 在没有 UI 交互的情况下验证
 * 通知（含流体云 / Live Updates）与真实短信收发链路。
 *
 * ```
 * adb shell am broadcast -a com.blue.qingniao.DEBUG_NOTIFY \
 *     --es address 10086 --es body "验证码 123456" --ei sub 1
 * adb shell am broadcast -a com.blue.qingniao.DEBUG_SEND \
 *     --es address 13054434880 --es body "self test" --ei sub 1
 * ```
 */
class DebugNotifyReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val address = intent.getStringExtra("address") ?: "10086"
        val body = intent.getStringExtra("body") ?: "青鸟调试通知"
        val subscription = intent.getIntExtra("sub", -1)
        when (intent.action) {
            ACTION_NOTIFY -> {
                Notifications.showSms(context, address, body, subscription, -1L)
                Log.d(TAG, "notification shown for $address promoted=${Notifications.canPromote(context)}")
            }
            ACTION_SEND -> {
                val pending = goAsync()
                MessageIo.receiverExecutor.execute {
                    try {
                        val id = MessageStore(context).use { store ->
                            SmsTransport.send(
                                context,
                                store,
                                address,
                                body,
                                if (subscription >= 0) subscription else SubscriptionManager.getDefaultSmsSubscriptionId(),
                            )
                        }
                        Log.d(TAG, "sent to $address id=$id")
                        Thread.sleep(4000)
                        val row = context.contentResolver.query(
                            android.content.ContentUris.withAppendedId(android.provider.Telephony.Sms.CONTENT_URI, id),
                            arrayOf("_id", "type", "status"),
                            null,
                            null,
                            null,
                        )?.use {
                            if (it.moveToFirst()) "id=${it.getLong(0)} type=${it.getInt(1)} status=${it.getInt(2)}" else "missing"
                        }
                        Log.d(TAG, "row after send: $row")
                    } catch (error: Exception) {
                        Log.e(TAG, "send failed: ${error.message}")
                    } finally {
                        pending.finish()
                    }
                }
            }
            ACTION_ACCESS -> {
                val state = mapOf(
                    "defaultApp" to SmsAccess.isDefaultSmsApp(context),
                    "readSms" to SmsAccess.granted(context, android.Manifest.permission.READ_SMS),
                    "sendSms" to SmsAccess.granted(context, android.Manifest.permission.SEND_SMS),
                    "receiveSms" to SmsAccess.granted(context, android.Manifest.permission.RECEIVE_SMS),
                    "promoted" to Notifications.canPromote(context),
                    "fluidCloud" to Notifications.fluidCloudEnabled(context),
                )
                Log.d(TAG, "access=$state")
            }
        }
    }

    companion object {
        private const val TAG = "QingniaoDebug"
        private const val ACTION_NOTIFY = "com.blue.qingniao.DEBUG_NOTIFY"
        private const val ACTION_SEND = "com.blue.qingniao.DEBUG_SEND"
        private const val ACTION_ACCESS = "com.blue.qingniao.DEBUG_ACCESS"
    }
}
