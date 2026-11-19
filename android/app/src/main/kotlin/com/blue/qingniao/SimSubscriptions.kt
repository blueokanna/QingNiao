package com.blue.qingniao

import android.Manifest
import android.content.Context
import android.content.Intent
import android.os.Build
import android.telephony.SubscriptionInfo
import android.telephony.SubscriptionManager

/** One permission-aware source of current SIM/eSIM metadata for both bridges and notifications. */
object SimSubscriptions {
    private fun active(context: Context): List<SubscriptionInfo> {
        if (!SmsAccess.granted(context, Manifest.permission.READ_PHONE_STATE)) return emptyList()
        return try {
            context.getSystemService(SubscriptionManager::class.java)
                ?.activeSubscriptionInfoList.orEmpty()
                .filter { SmsSubscriptionIdentity.validId(it.subscriptionId) }
        } catch (_: SecurityException) {
            emptyList()
        } catch (_: Exception) {
            emptyList()
        }
    }

    fun cards(context: Context): List<Map<String, Any?>> {
        val manager = context.getSystemService(SubscriptionManager::class.java)
        val canReadNumber = SmsAccess.granted(context, Manifest.permission.READ_PHONE_NUMBERS)
        return active(context).map { info ->
            val number = if (canReadNumber) try {
                if (Build.VERSION.SDK_INT >= 33) manager?.getPhoneNumber(info.subscriptionId).orEmpty()
                else {
                    @Suppress("DEPRECATION")
                    info.number.orEmpty()
                }
            } catch (_: SecurityException) { "" }
            catch (_: Exception) { "" } else ""
            mapOf(
                "id" to info.subscriptionId,
                "slot" to SmsSubscriptionIdentity.displaySlot(info.simSlotIndex),
                "name" to info.displayName?.toString().orEmpty(),
                "number" to number,
                "carrier" to info.carrierName?.toString().orEmpty(),
                "isEmbedded" to info.isEmbedded,
            )
        }.sortedWith(compareBy({ (it["slot"] as Int).takeIf { slot -> slot > 0 } ?: Int.MAX_VALUE }, { it["id"] as Int }))
    }

    internal fun outgoingId(context: Context, requested: Int): Int = OutgoingSmsSubscription.resolve(
        requested, SubscriptionManager.getDefaultSmsSubscriptionId(),
        if (SmsAccess.granted(context, Manifest.permission.READ_PHONE_STATE))
            active(context).map { it.subscriptionId } else null,
    )

    internal fun incomingId(context: Context, intent: Intent): Int {
        val explicit = listOf(
            intent.getIntExtra(SubscriptionManager.EXTRA_SUBSCRIPTION_INDEX, -1),
            intent.getIntExtra("subscription", -1),
            intent.getIntExtra("subscription_id", -1),
            intent.getIntExtra("sub_id", -1),
        )
        // Never turn a valid but removed subscription into the current card in its old slot.
        explicit.firstOrNull(SmsSubscriptionIdentity::validId)?.let { return it }
        val slot = incomingSlot(intent)
        return SmsSubscriptionIdentity.resolve(explicit, slot,
            if (slot >= 0) active(context).map { it.subscriptionId to it.simSlotIndex } else emptyList())
    }

    internal fun incomingSlot(intent: Intent): Int = listOf(
        intent.getIntExtra(SubscriptionManager.EXTRA_SLOT_INDEX, -1),
        intent.getIntExtra("slot", -1),
        intent.getIntExtra("slotId", -1),
    ).firstOrNull { it >= 0 && it != Int.MAX_VALUE } ?: -1

    internal fun notificationLabel(context: Context, subscriptionId: Int): String {
        if (!SmsSubscriptionIdentity.validId(subscriptionId)) return "SMS"
        val info = active(context).firstOrNull { it.subscriptionId == subscriptionId }
            ?: return "SMS · #$subscriptionId"
        val kind = if (info.isEmbedded) "eSIM" else "SIM"
        val slot = SmsSubscriptionIdentity.displaySlot(info.simSlotIndex)
        return if (slot > 0) "SMS · $kind $slot" else "SMS · $kind · #$subscriptionId"
    }
}
