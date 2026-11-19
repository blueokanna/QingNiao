package com.blue.qingniao

/** Serializes intake requests with job completion without cancelling a running recovery job. */
internal class IncomingSmsRecoveryRequests {
    private var generation = 0L
    private var finishedLocally = false

    @Synchronized
    fun request(hasScheduledJob: () -> Boolean, schedule: () -> Boolean) {
        generation++
        // Repeated broadcasts must not reset latency/backoff. A just-finished job may still
        // appear in JobScheduler until its asynchronous completion is processed.
        if (!finishedLocally && hasScheduledJob()) return
        if (schedule()) finishedLocally = false
    }

    @Synchronized
    fun started(): Long {
        finishedLocally = false
        return generation
    }

    @Synchronized
    fun finish(startGeneration: Long, retry: Boolean, finishJob: (Boolean) -> Unit) {
        val reschedule = retry || generation != startGeneration
        finishedLocally = !reschedule
        // Keep the callback inside this lock so a request cannot be lost between the
        // final pending check and telling JobScheduler that the work is complete.
        finishJob(reschedule)
    }
}
