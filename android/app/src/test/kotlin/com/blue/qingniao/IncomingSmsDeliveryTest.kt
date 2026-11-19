package com.blue.qingniao

import org.junit.Assert.*
import org.junit.Test

class IncomingSmsDeliveryTest {
    private fun message(sentAt: Long = 10, subscription: Int = 1) = IncomingSms(
        IncomingSms.key(listOf("sender:$sentAt:repeat body".toByteArray()), "3gpp", subscription),
        "+8613800000000", "repeat body", 1000 + sentAt, sentAt, subscription, null, 0, false,
    )

    private class Target : IncomingSmsDelivery.Target {
        var default = true
        var returnNull = false
        var providerFailure = false
        var crashBeforeCompletion = false
        var notificationFailure = false
        var notificationsEnabled = true
        var blocked = false
        var alreadyRead = false
        val steps = mutableListOf<String>()
        val provider = mutableMapOf<List<Any>, SavedIncomingSms>()
        val completed = mutableSetOf<String>()
        var alerts = 0
        var notificationErrors = 0

        override fun isDefaultSmsApp() = default
        override fun persist(message: IncomingSms): SavedIncomingSms? {
            steps += "persist"
            if (providerFailure) throw SecurityException("provider access revoked")
            if (returnNull) return null
            // A provider commit can survive even when the journal completion did not.
            return provider.getOrPut(listOf(message.address, message.body, message.receivedAt,
                message.sentAt, message.subscriptionId)) { SavedIncomingSms(73, alreadyRead) }
        }
        override fun complete(key: String) {
            steps += "complete"
            if (crashBeforeCompletion) throw IllegalStateException("interrupted journal update")
            completed += key
        }
        override fun notify(message: IncomingSms, saved: SavedIncomingSms) {
            steps += "notify"
            assertEquals(73L, saved.threadId)
            if (notificationFailure) throw SecurityException("notifications denied")
            if (notificationsEnabled && !blocked) alerts++
        }
        override fun notificationFailed(error: Exception) { notificationErrors++ }
    }

    @Test fun persistsBeforeAlertingAndClearsJournalAfterAlertAttempt() {
        val target = Target()
        val sms = message()
        assertTrue(IncomingSmsDelivery(target).deliver(sms))
        assertEquals(listOf("persist", "notify", "complete"), target.steps)
        assertEquals(setOf(sms.key), target.completed)
        assertEquals(1, target.alerts)
    }

    @Test fun disabledNotificationsAndBlockedSendersStillPersist() {
        for (blocked in listOf(false, true)) {
            val target = Target().apply {
                this.blocked = blocked
                notificationsEnabled = blocked
            }
            assertTrue(IncomingSmsDelivery(target).deliver(message()))
            assertEquals(1, target.provider.size)
            assertEquals(1, target.completed.size)
            assertEquals(0, target.alerts)
        }
    }

    @Test fun notificationExceptionDoesNotRequeueOrLoseSavedSms() {
        val target = Target().apply { notificationFailure = true }
        assertTrue(IncomingSmsDelivery(target).deliver(message()))
        assertEquals(1, target.provider.size)
        assertEquals(1, target.completed.size)
        assertEquals(1, target.notificationErrors)
    }

    @Test fun nullInsertLeavesJournalPendingWithoutAlert() {
        val target = Target().apply { returnNull = true }
        assertThrows(IllegalStateException::class.java) { IncomingSmsDelivery(target).deliver(message()) }
        assertTrue(target.completed.isEmpty())
        assertEquals(0, target.alerts)
    }

    @Test fun revokedProviderPermissionLeavesJournalPendingWithoutAlert() {
        val target = Target().apply { providerFailure = true }
        assertThrows(SecurityException::class.java) { IncomingSmsDelivery(target).deliver(message()) }
        assertTrue(target.completed.isEmpty())
        assertEquals(0, target.alerts)
    }

    @Test fun losingDefaultRoleDefersProviderWriteUntilRestored() {
        val target = Target().apply { default = false }
        val delivery = IncomingSmsDelivery(target)
        assertFalse(delivery.deliver(message()))
        assertTrue(target.steps.isEmpty())
        target.default = true
        assertTrue(delivery.deliver(message()))
        assertEquals(1, target.provider.size)
    }

    @Test fun replayAfterProviderCommitUsesOriginalReceiptAndDoesNotInsertAgain() {
        val target = Target().apply { crashBeforeCompletion = true }
        val sms = message()
        assertThrows(IllegalStateException::class.java) { IncomingSmsDelivery(target).deliver(sms) }
        assertEquals(1, target.provider.size)
        assertTrue(target.completed.isEmpty())
        target.crashBeforeCompletion = false
        // A new delivery instance models a restarted process loading the same journal row.
        assertTrue(IncomingSmsDelivery(target).deliver(sms.copy()))
        assertEquals(1, target.provider.size)
        assertEquals(1, target.completed.size)
        // A crash can repeat an alert (same notification ID), but never the provider row.
        assertEquals(2, target.alerts)
    }

    @Test fun sameBodyAtDifferentTimesAndOnDifferentSimsAreSeparateSms() {
        val target = Target()
        val delivery = IncomingSmsDelivery(target)
        listOf(message(), message(sentAt = 11), message(subscription = 2)).forEach {
            assertTrue(delivery.deliver(it))
        }
        assertEquals(3, target.provider.size)
        assertEquals(3, target.completed.size)
    }

    @Test fun replayDoesNotNotifyMessageAlreadyReadInProvider() {
        val target = Target().apply { alreadyRead = true }
        assertTrue(IncomingSmsDelivery(target).deliver(message()))
        assertEquals(1, target.completed.size)
        assertEquals(0, target.alerts)
    }

    @Test fun unknownSubscriptionsOnDifferentSlotsDoNotCollapseIdenticalPdus() {
        val pdus = listOf(byteArrayOf(1, 2, 3))
        assertNotEquals(IncomingSms.key(pdus, "3gpp", -1, 0),
            IncomingSms.key(pdus, "3gpp", -1, 1))
        // When the actual subscription is known, a changed logical slot is not a new message.
        assertEquals(IncomingSms.key(pdus, "3gpp", 37, 0),
            IncomingSms.key(pdus, "3gpp", 37, 1))
    }

    @Test fun receiptKeyIncludesAllPartsTheirBoundariesFormatAndSim() {
        val first = listOf(byteArrayOf(1, 2), byteArrayOf(3))
        val key = IncomingSms.key(first, "3gpp", 1)
        assertEquals(key, IncomingSms.key(first.map { it.copyOf() }, "3gpp", 1))
        assertNotEquals(key, IncomingSms.key(first, "3gpp", 2))
        assertNotEquals(key, IncomingSms.key(first, "3gpp2", 1))
        assertNotEquals(key, IncomingSms.key(first.reversed(), "3gpp", 1))
        assertNotEquals(key, IncomingSms.key(listOf(byteArrayOf(1), byteArrayOf(2, 3)), "3gpp", 1))
        assertNotEquals(key, IncomingSms.key(listOf(byteArrayOf(1, 2), byteArrayOf(4)), "3gpp", 1))
    }
}
