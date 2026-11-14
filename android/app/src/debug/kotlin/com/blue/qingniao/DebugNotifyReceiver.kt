package com.blue.qingniao

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.telephony.SubscriptionManager
import android.util.Log


class DebugNotifyReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val address = intent.getStringExtra("address") ?: "10086"
        val body = intent.getStringExtra("body") ?: "Qingniao debug notification"
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
                    "promotionActive" to Notifications.promotionActive(context),
                    "fluidCloud" to Notifications.fluidCloudEnabled(context),
                )
                Log.d(TAG, "access=$state")
            }
            ACTION_CLEAR -> {
                val manager = context.getSystemService(android.app.NotificationManager::class.java)
                val active = runCatching { manager.activeNotifications.toList() }.getOrDefault(emptyList())
                active.forEach { manager.cancel(it.id) }
                Log.d(TAG, "cleared ${active.size} notifications")
            }
            ACTION_DUMP -> {
                val address = intent.getStringExtra("address") ?: ""
                val rows = StringBuilder()
                context.contentResolver.query(
                    android.provider.Telephony.Sms.CONTENT_URI,
                    arrayOf("_id", "address", "body", "type", "status", "date"),
                    "address=?",
                    arrayOf(address),
                    "_id DESC",
                )?.use { cursor ->
                    while (cursor.moveToNext() && rows.length < 900) {
                        rows.append("id=").append(cursor.getLong(0))
                            .append(" type=").append(cursor.getInt(3))
                            .append(" status=").append(cursor.getInt(4))
                            .append(" body=").append(cursor.getString(2)?.take(24))
                            .append("; ")
                    }
                }
                Log.d(TAG, "dump[$address] $rows")
            }
        }
    }

    companion object {
        private const val TAG = "QingniaoDebug"
        private const val ACTION_NOTIFY = "com.blue.qingniao.DEBUG_NOTIFY"
        private const val ACTION_SEND = "com.blue.qingniao.DEBUG_SEND"
        private const val ACTION_ACCESS = "com.blue.qingniao.DEBUG_ACCESS"
        private const val ACTION_CLEAR = "com.blue.qingniao.DEBUG_CLEAR"
        private const val ACTION_DUMP = "com.blue.qingniao.DEBUG_DUMP"
    }
}
