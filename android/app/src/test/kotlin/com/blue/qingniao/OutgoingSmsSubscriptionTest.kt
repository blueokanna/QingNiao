package com.blue.qingniao

import org.junit.Assert.*
import org.junit.Test

class OutgoingSmsSubscriptionTest {
    @Test fun usesExplicitSimOrSystemDefault() {
        assertEquals(93, OutgoingSmsSubscription.resolve(93, 41, listOf(41, 93)))
        assertEquals(41, OutgoingSmsSubscription.resolve(-1, 41, listOf(41, 93)))
    }

    @Test fun fallsBackToOnlyActiveSimWhenDefaultIsMissingOrStale() {
        assertEquals(93, OutgoingSmsSubscription.resolve(-1, -1, listOf(93)))
        assertEquals(93, OutgoingSmsSubscription.resolve(-1, 41, listOf(93)))
        assertEquals(0, OutgoingSmsSubscription.resolve(-1, Int.MAX_VALUE, listOf(0)))
    }

    @Test fun rejectsAmbiguousMissingAndRemovedSimsBeforeOutboxInsertion() {
        assertThrows(IllegalStateException::class.java) { OutgoingSmsSubscription.resolve(-1, -1, listOf(41, 93)) }
        assertThrows(IllegalStateException::class.java) { OutgoingSmsSubscription.resolve(-1, -1, emptyList()) }
        assertThrows(IllegalStateException::class.java) { OutgoingSmsSubscription.resolve(41, 93, listOf(93)) }
    }

    @Test fun phoneStatePermissionIsOptionalWhenASubscriptionIsKnown() {
        assertEquals(93, OutgoingSmsSubscription.resolve(93, -1, null))
        assertEquals(41, OutgoingSmsSubscription.resolve(-1, 41, null))
        assertThrows(IllegalStateException::class.java) { OutgoingSmsSubscription.resolve(-1, -1, null) }
    }
}
