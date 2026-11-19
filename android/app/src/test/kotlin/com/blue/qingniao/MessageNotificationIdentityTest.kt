package com.blue.qingniao

import org.junit.Assert.*
import org.junit.Test

class MessageNotificationIdentityTest {
    @Test fun javaHashCollisionCannotMergeNotificationsOrReplyActions() {
        val first = MessageNotificationIdentity.of("Aa", 37)
        val second = MessageNotificationIdentity.of("BB", 37)
        assertEquals(first.id, second.id) // A real Java String hash collision.
        assertNotEquals(first.tag, second.tag)
        assertNotEquals(first.actionUri("reply"), second.actionUri("reply"))
    }

    @Test fun sameSenderOnTwoSubscriptionsHasIndependentIdentity() {
        val first = MessageNotificationIdentity.of("10690000", 37)
        val second = MessageNotificationIdentity.of("10690000", 81)
        assertNotEquals(first.tag, second.tag)
        assertNotEquals(first.actionUri("open"), second.actionUri("open"))
    }

    @Test fun receiptReplayReplacesTheSameNotificationAndActions() {
        val first = MessageNotificationIdentity.of("+8613800000000", 81)
        val replay = MessageNotificationIdentity.of("+8613800000000", 81)
        assertEquals(first, replay)
        assertEquals(first.actionUri("expiry"), replay.actionUri("expiry"))
    }

    @Test fun operationsHaveDistinctUrisWithoutEmbeddingSenderOrOtp() {
        val identity = MessageNotificationIdentity.of("+8613800000000", 81)
        val actions = listOf("open", "reply", "read", "copy", "expiry")
        assertEquals(actions.size, actions.map(identity::actionUri).toSet().size)
        assertFalse(identity.actionUri("copy").contains("13800000000"))
        assertTrue(identity.tag.matches(Regex("incoming\\.[a-f0-9]{64}")))
    }

    @Test fun unknownSubscriptionDoesNotAliasSubscriptionZero() {
        assertNotEquals(MessageNotificationIdentity.of("1069", -1).tag,
            MessageNotificationIdentity.of("1069", 0).tag)
    }
}
