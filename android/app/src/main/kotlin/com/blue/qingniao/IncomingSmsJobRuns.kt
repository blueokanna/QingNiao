package com.blue.qingniao

import java.util.concurrent.atomic.AtomicBoolean

/** Accessed on the service's main thread; worker threads only read their cancellation token. */
internal class IncomingSmsJobRuns {
    private val runs = mutableMapOf<Int, AtomicBoolean>()

    fun start(jobId: Int): AtomicBoolean = AtomicBoolean(false).also {
        runs.put(jobId, it)?.set(true)
    }

    fun stop(jobId: Int) {
        runs.remove(jobId)?.set(true)
    }

    fun finish(jobId: Int, token: AtomicBoolean): Boolean {
        if (runs[jobId] !== token || token.get()) return false
        runs.remove(jobId)
        return true
    }

    fun stopAll() {
        runs.values.forEach { it.set(true) }
        runs.clear()
    }
}
