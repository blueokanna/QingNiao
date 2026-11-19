package com.blue.qingniao

import android.app.Application
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/** Exercises the durable SQLite handoff, including reopening and receipt retention. */
@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [32], application = Application::class)
class IncomingSmsStoreTest {
    private val context get() = RuntimeEnvironment.getApplication()
    private lateinit var store: IncomingSmsStore

    private fun message(id: Int = 1, subscription: Int = 37) = IncomingSms(
        IncomingSms.key(listOf("pdu-$id".toByteArray()), "3gpp", subscription),
        "+12345", "message-$id", 1000L + id, 500L + id, subscription,
        "+54321", 0, true,
    )

    @Before fun setUp() {
        context.deleteDatabase("incoming_sms.db")
        store = IncomingSmsStore(context)
    }

    @After fun tearDown() { store.close() }

    private fun reopen() {
        store.close()
        store = IncomingSmsStore(context)
    }

    @Test fun duplicateBroadcastAfterReopenPreservesOriginalTimeAndSim() {
        val sms = message()
        store.enqueue(sms)
        reopen()
        store.enqueue(sms.copy(receivedAt = 9999))
        store.enqueue(message(subscription = 51))
        val pending = store.pending(20)
        assertEquals(2, pending.size)
        assertEquals(setOf(sms, message(subscription = 51)), pending.toSet())
    }

    @Test fun completedReceiptClearsPrivateContentAndSuppressesReplayAfterReopen() {
        val sms = message()
        store.enqueue(sms)
        store.complete(sms.key)
        reopen()
        store.enqueue(sms.copy(receivedAt = 9999))
        assertFalse(store.hasPending())
        store.readableDatabase.rawQuery(
            "SELECT address,body,service_center,completed_at FROM incoming_sms WHERE receipt_key=?",
            arrayOf(sms.key),
        ).use { cursor ->
            assertTrue(cursor.moveToFirst())
            assertTrue(cursor.isNull(0))
            assertTrue(cursor.isNull(1))
            assertTrue(cursor.isNull(2))
            assertFalse(cursor.isNull(3))
        }
    }

    @Test fun failedRowsRotateBehindNewMessagesAndRemainRecoverableAfterPruning() {
        val failed = message()
        val fresh = message(2)
        store.enqueue(failed)
        store.attempted(failed.key)
        assertFalse(store.hasUnattempted())
        store.enqueue(fresh)
        reopen()
        assertEquals(listOf(fresh), store.pending(1))
        assertTrue(store.hasUnattempted())
        store.pruneReceipts()
        assertEquals(listOf(fresh, failed), store.pending(20))
    }

    @Test fun receiptLimitsAndExpiryNeverRemovePendingBodies() {
        val pending = message()
        store.enqueue(pending)
        val db = store.writableDatabase
        db.beginTransaction()
        try {
            for (id in 2..1030) {
                val sms = message(id)
                store.enqueue(sms)
                store.complete(sms.key)
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
        store.pruneReceipts()
        db.rawQuery("SELECT COUNT(*) FROM incoming_sms WHERE completed_at IS NOT NULL", null).use {
            assertTrue(it.moveToFirst())
            assertEquals(1024, it.getInt(0))
        }
        db.execSQL("UPDATE incoming_sms SET completed_at=1 WHERE completed_at IS NOT NULL")
        store.pruneReceipts()
        reopen()
        assertEquals(listOf(pending), store.pending(20))
        store.readableDatabase.rawQuery("SELECT COUNT(*) FROM incoming_sms", null).use {
            assertTrue(it.moveToFirst())
            assertEquals(1, it.getInt(0))
        }
    }
}
