package com.blue.qingniao

import org.junit.Assert.*
import org.junit.Test

class IncomingSmsRecoveryRequestsTest {
    @Test fun repeatedIntakeDoesNotPostponePendingOrCancelRunningJob() {
        val requests = IncomingSmsRecoveryRequests()
        var scheduled = false
        var schedules = 0
        fun request() = requests.request({ scheduled }) { schedules++; scheduled = true; true }
        request()
        repeat(20) { request() }
        val started = requests.started()
        request()
        assertEquals(1, schedules)
        var retry = false
        requests.finish(started, false) { retry = it }
        assertTrue(retry)
    }

    @Test fun intakeAfterFinalDatabaseCheckArmsAnotherRun() {
        val requests = IncomingSmsRecoveryRequests()
        val started = requests.started()
        requests.request({ true }) { fail("Must not replace running job"); false }
        var retry = false
        requests.finish(started, false) { retry = it }
        assertTrue(retry)
    }

    @Test fun intakeAfterCompletionReplacesStaleSchedulerEntry() {
        val requests = IncomingSmsRecoveryRequests()
        val started = requests.started()
        requests.finish(started, false) { assertFalse(it) }
        var schedules = 0
        requests.request({ true }) { schedules++; true }
        assertEquals(1, schedules)
        requests.request({ true }) { schedules++; true }
        assertEquals(1, schedules)
    }

    @Test fun failedScheduleCanBeRetriedAndProviderFailureKeepsJobAlive() {
        val requests = IncomingSmsRecoveryRequests()
        var schedules = 0
        requests.request({ false }) { schedules++; false }
        requests.request({ false }) { schedules++; true }
        assertEquals(2, schedules)
        val started = requests.started()
        requests.finish(started, true) { assertTrue(it) }
    }

    @Test fun successfulUncontendedRunDoesNotPollAgain() {
        val requests = IncomingSmsRecoveryRequests()
        requests.request({ false }) { true }
        val started = requests.started()
        requests.finish(started, false) { assertFalse(it) }
    }
}
