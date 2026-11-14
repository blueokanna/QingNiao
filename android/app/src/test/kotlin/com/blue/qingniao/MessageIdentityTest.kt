package com.blue.qingniao

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class MessageIdentityTest {
    @Test fun separateProviderIds() {
        assertNotEquals(MessageIdentity.sms(42), MessageIdentity.mms(42))
        assertEquals(42L, MessageIdentity.providerId(MessageIdentity.sms(42)))
        assertEquals(42L, MessageIdentity.providerId(MessageIdentity.mms(42)))
    }
    @Test fun rejectOverflowAndInvalidKeys() {
        for (id in listOf(0L, Long.MIN_VALUE)) {
            assertThrows(IllegalArgumentException::class.java) { MessageIdentity.providerId(id) }
        }
        assertThrows(IllegalArgumentException::class.java) { MessageIdentity.mms(-1) }
        assertEquals(Long.MAX_VALUE, MessageIdentity.providerId(MessageIdentity.mms(Long.MAX_VALUE)))
    }
    @Test fun validateBatchBounds() {
        assertEquals(listOf(1L, 2L), ConversationOperations.threadIds(listOf(1L, 2L, 1L)))
        assertThrows(IllegalArgumentException::class.java) { ConversationOperations.threadIds(emptyList()) }
        assertThrows(IllegalArgumentException::class.java) { ConversationOperations.threadIds(listOf(-1L)) }
        assertThrows(IllegalArgumentException::class.java) { ConversationOperations.threadIds(List(10001) { 1L }) }
    }
}
