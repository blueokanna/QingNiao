package com.blue.qingniao

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent


class NotificationExpiryReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (!intent.hasExtra("id")) return
        val id = intent.getIntExtra("id", 0)
        // Notification IDs are signed hashes, so negative IDs are valid too.
        Notifications.cancel(context, id, intent.getStringExtra(Notifications.EXTRA_TAG))
    }
}
