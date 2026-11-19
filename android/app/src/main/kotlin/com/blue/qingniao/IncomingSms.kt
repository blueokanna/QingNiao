package com.blue.qingniao

import java.nio.ByteBuffer
import java.security.MessageDigest

/** The received time is fixed when journaled, including across provider retries. */
internal data class IncomingSms(
    val key: String,
    val address: String,
    val body: String,
    val receivedAt: Long,
    val sentAt: Long,
    val subscriptionId: Int,
    val serviceCenter: String?,
    val protocol: Int,
    val replyPathPresent: Boolean,
) {
    // Include the SIM and the complete PDUs (including sender timestamp), never body alone.
    companion object {
        fun key(pdus: List<ByteArray>, format: String?, subscriptionId: Int, slotIndex: Int = -1): String {
            val digest = MessageDigest.getInstance("SHA-256")
            fun add(bytes: ByteArray) {
                digest.update(ByteBuffer.allocate(4).putInt(bytes.size).array())
                digest.update(bytes)
            }
            add(subscriptionId.toString().toByteArray(Charsets.UTF_8))
            add(format.orEmpty().toByteArray(Charsets.UTF_8))
            pdus.forEach(::add)
            // Without phone-state permission, an explicit slot still separates two unknown SIMs.
            // It is only a dedupe discriminator, never a fabricated subscription ID.
            if (!SmsSubscriptionIdentity.validId(subscriptionId) && slotIndex >= 0) {
                add("slot:$slotIndex".toByteArray(Charsets.UTF_8))
            }
            return digest.digest().joinToString("") { "%02x".format(it.toInt() and 0xff) }
        }
    }
}

internal data class SavedIncomingSms(val threadId: Long, val read: Boolean)

/** Keep notification failures outside the durable delivery transaction. */
internal class IncomingSmsDelivery(private val target: Target) {
    interface Target {
        fun isDefaultSmsApp(): Boolean
        fun persist(message: IncomingSms): SavedIncomingSms?
        fun complete(key: String)
        fun notify(message: IncomingSms, saved: SavedIncomingSms)
        fun notificationFailed(error: Exception)
    }

    fun deliver(message: IncomingSms): Boolean {
        if (!target.isDefaultSmsApp()) return false
        val saved = checkNotNull(target.persist(message)) { "SMS provider did not save the message" }
        try {
            if (!saved.read) {
                try {
                    target.notify(message, saved)
                } catch (error: Exception) {
                    target.notificationFailed(error)
                }
            }
        } finally {
            // Clear the journal only after the alert attempt. A crash before this point
            // replays against the existing provider row and can replace the same notification.
            target.complete(message.key)
        }
        return true
    }
}
