package com.blue.qingniao

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent


class NotificationExpiryReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra("id", -1)
        if (id < 0) return
        Notifications.cancel(context, id)
    }
}
