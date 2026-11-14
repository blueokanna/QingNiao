package com.blue.qingniao

data class MessagePageCursor(val date: Long = Long.MAX_VALUE, val key: Long = Long.MAX_VALUE) {
    fun includes(candidateDate: Long, candidateKey: Long): Boolean =
        candidateDate < date || (candidateDate == date && candidateKey < key)
}
