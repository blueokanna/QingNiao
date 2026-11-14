package com.blue.qingniao

object MessageIdentity {
    fun sms(id: Long): Long { require(id > 0); return id }
    fun mms(id: Long): Long { require(id > 0); return -id }
    fun providerId(key: Long): Long {
        require(key != 0L && key != Long.MIN_VALUE)
        return if (key < 0) -key else key
    }
}
