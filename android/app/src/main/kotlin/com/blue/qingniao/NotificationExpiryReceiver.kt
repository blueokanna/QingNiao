package com.blue.qingniao

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * 提升为流体云的通知是 ongoing 的，用户不点开也不会消失。
 * 15 分钟后自动撤下，避免状态栏胶囊常驻；用户点开/标为已读会更早取消。
 */
class NotificationExpiryReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra("id", -1)
        if (id < 0) return
        Notifications.cancel(context, id)
    }
}
