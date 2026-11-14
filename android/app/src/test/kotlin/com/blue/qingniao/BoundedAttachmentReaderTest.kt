package com.blue.qingniao

import org.junit.Assert.assertArrayEquals
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.InputStream

class BoundedAttachmentReaderTest {
    @Test fun acceptsEmptyAndExactLimit() {
        assertArrayEquals(byteArrayOf(), BoundedAttachmentReader.read(ByteArrayInputStream(byteArrayOf()), 2))
        assertArrayEquals(byteArrayOf(1, 2), BoundedAttachmentReader.read(ByteArrayInputStream(byteArrayOf(1, 2)), 2))
    }

    @Test(expected = IllegalArgumentException::class)
    fun rejectsOversizedInsteadOfTruncating() {
        BoundedAttachmentReader.read(ByteArrayInputStream(byteArrayOf(1, 2, 3)), 2)
    }

    @Test fun handlesStreamsReturningZero() {
        val stream = object : InputStream() {
            var remaining = 2
            override fun read(): Int = if (remaining-- > 0) 7 else -1
            override fun read(buffer: ByteArray, offset: Int, length: Int): Int = 0
        }
        assertArrayEquals(byteArrayOf(7, 7), BoundedAttachmentReader.read(stream, 3))
    }
}
