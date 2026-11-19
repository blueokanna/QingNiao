package com.blue.qingniao

import java.security.MessageDigest

/** Notification tags and PendingIntent data must survive collisions in the 32-bit request ID. */
internal data class MessageNotificationIdentity(val id: Int, val tag: String) {
    fun actionUri(action: String): String = "qingniao://message-notification/$tag/$action"

    companion object {
        fun of(address: String, subscriptionId: Int): MessageNotificationIdentity {
            val source = "$subscriptionId:$address"
            val digest = MessageDigest.getInstance("SHA-256").digest(source.toByteArray(Charsets.UTF_8))
            val tag = "incoming." + digest.joinToString("") { "%02x".format(it.toInt() and 0xff) }
            val id = source.hashCode().let { if (it == 4100) it + 1 else it }
            return MessageNotificationIdentity(id, tag)
        }
    }
}
