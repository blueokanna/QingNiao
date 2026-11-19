package com.blue.qingniao

import org.junit.Assert.*
import org.junit.Test

class SmsSubscriptionIdentityTest {
    private val active = listOf(37 to 0, 81 to 1)

    @Test fun explicitSubscriptionIsNeverInterpretedAsSlot() {
        assertEquals(81, SmsSubscriptionIdentity.resolve(listOf(81), 0, active))
        // A removed card must retain its own identity, not the replacement occupying its slot.
        assertEquals(12, SmsSubscriptionIdentity.resolve(listOf(12), 0, active))
        assertEquals(0, SmsSubscriptionIdentity.resolve(listOf(0), 1, active))
    }

    @Test fun absentSubscriptionUsesOnlyAnUnambiguousReportedSlot() {
        assertEquals(37, SmsSubscriptionIdentity.resolve(listOf(-1), 0, active))
        assertEquals(81, SmsSubscriptionIdentity.resolve(emptyList(), 1, active))
        assertEquals(-1, SmsSubscriptionIdentity.resolve(emptyList(), 2, active))
        assertEquals(-1, SmsSubscriptionIdentity.resolve(emptyList(), 0, listOf(37 to 0, 81 to 0)))
    }

    @Test fun absentPermissionOrSlotDoesNotGuessTheOnlyActiveCard() {
        assertEquals(-1, SmsSubscriptionIdentity.resolve(emptyList(), 0, emptyList()))
        assertEquals(-1, SmsSubscriptionIdentity.resolve(emptyList(), -1, listOf(37 to 0)))
    }

    @Test fun defaultSubscriptionSentinelIsNotARealIdentity() {
        assertEquals(81, SmsSubscriptionIdentity.resolve(listOf(Int.MAX_VALUE, -1, 81), 0, active))
        assertEquals(-1, SmsSubscriptionIdentity.resolve(listOf(Int.MAX_VALUE), -1, active))
        assertFalse(SmsSubscriptionIdentity.validId(Int.MAX_VALUE))
    }

    @Test fun displaySlotsAreOneBasedAndUnknownStaysUnknown() {
        assertEquals(1, SmsSubscriptionIdentity.displaySlot(0))
        assertEquals(2, SmsSubscriptionIdentity.displaySlot(1))
        assertEquals(0, SmsSubscriptionIdentity.displaySlot(-1))
        assertEquals(0, SmsSubscriptionIdentity.displaySlot(Int.MAX_VALUE))
    }
}
