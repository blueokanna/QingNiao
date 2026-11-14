package com.blue.qingniao

object NetworkPushPolicy {
    fun accepts(data: Map<String, String>, spaceId: String, sentAt: Long, now: Long, messageId: String?): Boolean {
        if (data.keys != setOf("type", "spaceId") || data["type"] != "sync_available") return false
        if (spaceId.isEmpty() || data["spaceId"] != spaceId || messageId.isNullOrBlank() || messageId.length > 256) return false
        if (sentAt <= 0 || now <= 0) return false
        return sentAt >= now - 86_400_000L && sentAt <= now + 120_000L
    }
}
