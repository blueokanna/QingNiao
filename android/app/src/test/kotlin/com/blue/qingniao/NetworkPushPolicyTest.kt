package com.blue.qingniao

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NetworkPushPolicyTest {
    private val now = 1_800_000_000_000L
    private val data = mapOf("type" to "sync_available", "spaceId" to "paired-space")
    @Test fun acceptBoundMetadataOnly() {
        assertTrue(NetworkPushPolicy.accepts(data, "paired-space", now, now, "message-1"))
    }
    @Test fun rejectUnpairedOrMessageContent() {
        assertFalse(NetworkPushPolicy.accepts(data, "another-space", now, now, "message-1"))
        assertFalse(NetworkPushPolicy.accepts(data + ("body" to "private SMS"), "paired-space", now, now, "message-1"))
        assertFalse(NetworkPushPolicy.accepts(data + ("type" to "sms"), "paired-space", now, now, "message-1"))
    }
    @Test fun rejectExpiredFutureAndMissingIdentity() {
        assertFalse(NetworkPushPolicy.accepts(data, "paired-space", now - 86_400_001, now, "message-1"))
        assertFalse(NetworkPushPolicy.accepts(data, "paired-space", now + 120_001, now, "message-1"))
        assertFalse(NetworkPushPolicy.accepts(data, "paired-space", now, now, null))
        assertFalse(NetworkPushPolicy.accepts(data, "paired-space", Long.MAX_VALUE, now, "message-1"))
    }
}
