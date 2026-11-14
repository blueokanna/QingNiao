package com.blue.qingniao

import java.io.ByteArrayOutputStream
import java.io.InputStream

object BoundedAttachmentReader {
    fun read(stream: InputStream, limit: Int = 8 * 1024 * 1024): ByteArray {
        require(limit > 0)
        val output = ByteArrayOutputStream(minOf(limit, 8192))
        val buffer = ByteArray(minOf(limit, 8192))
        while (true) {
            if (output.size() == limit) {
                require(stream.read() < 0) { "Attachment exceeds the preview size limit" }
                break
            }
            val count = stream.read(buffer, 0, minOf(buffer.size, limit - output.size()))
            if (count < 0) break
            if (count == 0) {
                val next = stream.read()
                if (next < 0) break
                require(output.size() < limit) { "Attachment exceeds the preview size limit" }
                output.write(next)
            } else {
                output.write(buffer, 0, count)
            }
        }
        return output.toByteArray()
    }
}
