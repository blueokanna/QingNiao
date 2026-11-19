package com.blue.qingniao

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class IncomingSmsJobRunsTest {
    @Test fun stopMatchesJobIdInsteadOfBinderParameterIdentity() {
        val runs = IncomingSmsJobRuns()
        val token = runs.start(9024)
        runs.stop(9024)
        assertTrue(token.get())
        assertFalse(runs.finish(9024, token))
    }

    @Test fun staleCompletionCannotFinishReplacementJob() {
        val runs = IncomingSmsJobRuns()
        val old = runs.start(9024)
        val replacement = runs.start(9024)
        assertTrue(old.get())
        assertFalse(runs.finish(9024, old))
        assertFalse(replacement.get())
        assertTrue(runs.finish(9024, replacement))
        assertFalse(runs.finish(9024, replacement))
    }

    @Test fun serviceDestructionCancelsAllWorkers() {
        val runs = IncomingSmsJobRuns()
        val first = runs.start(1)
        val second = runs.start(2)
        runs.stopAll()
        assertTrue(first.get())
        assertTrue(second.get())
        assertFalse(runs.finish(1, first))
        assertFalse(runs.finish(2, second))
    }
}
