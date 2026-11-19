package com.blue.qingniao

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

class MessageAddressTest {
    @Test fun blockedPhoneMatchesFormattingAndInternationalPrefix() {
        assertEquals(MessageAddress.normalize("+86 138-0000-0000"),
            MessageAddress.normalize("0086 (138) 0000 0000"))
        assertEquals("10086", MessageAddress.normalize("10086"))
    }

    @Test fun distinctAlphanumericSendersAreNotCollapsedIntoPhoneDigits() {
        assertEquals("bank1", MessageAddress.normalize(" BANK1 "))
        assertNotEquals(MessageAddress.normalize("BANK1"), MessageAddress.normalize("BANK2"))
        assertNotEquals(MessageAddress.normalize("BANK1"), MessageAddress.normalize("22651"))
    }

    @Test fun preservesShortCodesAndNormalizesUnicodeDigits() {
        assertEquals("*123#", MessageAddress.normalize("*123#"))
        assertEquals("123", MessageAddress.normalize("１２３"))
    }
}
