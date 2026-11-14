package com.blue.qingniao

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MessagePageCursorTest {
    @Test fun mixedProvidersUseStableTimeAndIdentityOrder() {
        val cursor = MessagePageCursor(100_000, -42)
        assertTrue(cursor.includes(99_000, 99))
        assertTrue(cursor.includes(100_000, -43))
        assertFalse(cursor.includes(100_000, -42))
        assertFalse(cursor.includes(100_000, -41))
        assertFalse(cursor.includes(100_000, 42))
        assertFalse(cursor.includes(101_000, -99))
    }
    @Test fun smsCursorIncludesMmsAtSameTimestamp() {
        assertTrue(MessagePageCursor(100_000, 42).includes(100_000, -42))
        assertTrue(MessagePageCursor().includes(100_000, -42))
    }
}
