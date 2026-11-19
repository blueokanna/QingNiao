package com.blue.qingniao

import android.app.Application
import android.content.ContentProvider
import android.content.ContentValues
import android.database.MatrixCursor
import android.net.Uri
import android.provider.Telephony
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowContentResolver

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [32], application = Application::class)
class SmsSendRecoveryTest {
    private lateinit var store: MessageStore
    private lateinit var provider: SmsProvider
    private val context get() = RuntimeEnvironment.getApplication()

    class SmsProvider : ContentProvider() {
        var type = Telephony.Sms.MESSAGE_TYPE_OUTBOX
        var status = Telephony.Sms.STATUS_PENDING
        var date = System.currentTimeMillis()
        var failUpdate = false
        var nullQuery = false
        override fun onCreate() = true
        override fun getType(uri: Uri) = "vnd.android.cursor.item/sms"
        override fun insert(uri: Uri, values: ContentValues?) = uri
        override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?) = 0
        override fun query(uri: Uri, projection: Array<out String>?, selection: String?, selectionArgs: Array<out String>?, sortOrder: String?): MatrixCursor? {
            if (nullQuery) return null
            val columns = projection ?: arrayOf("type", "date")
            return MatrixCursor(columns).apply {
                if (selection == "type IN (4,6)" && type !in setOf(4, 6)) return@apply
                addRow(columns.map { when (it) { "_id" -> 1L; "type" -> type; else -> date } })
            }
        }
        override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int {
            if (failUpdate) throw IllegalStateException("provider temporarily unavailable")
            if (type !in setOf(4, 6)) return 0
            values?.getAsInteger("type")?.let { type = it }
            values?.getAsInteger("status")?.let { status = it }
            return 1
        }
    }

    @Before fun setUp() {
        context.deleteDatabase("message_state.db")
        store = MessageStore(context)
        provider = SmsProvider()
        ShadowContentResolver.registerProviderInternal("sms", provider)
    }

    @After fun tearDown() { store.close() }

    @Test fun multipartReceiptsAreIdempotentAndRequireEveryPart() {
        store.registerOutgoing(1, 2)
        assertNull(store.receiptState(1, "sent"))
        assertNull(store.receipt(1, 0, "sent", true))
        assertNull(store.receipt(1, 0, "sent", true))
        assertNull(store.receipt(1, 3, "sent", true))
        assertEquals(2, store.receipt(1, 1, "sent", true))
        assertEquals(2, store.receipt(1, 0, "sent", true))
    }

    @Test fun anyFailedPartCompletesAsFailureWithoutWaitingForever() {
        store.registerOutgoing(1, 3)
        store.receipt(1, 0, "sent", true)
        assertEquals(5, store.receipt(1, 1, "sent", false))
        assertTrue(SmsSendWatchdog.failIfPending(context, 1))
        assertEquals(5, provider.type)
        assertEquals(64, provider.status)
    }

    @Test fun recoversSuccessfulSubmissionAfterProviderWriteFailureAndReopen() {
        store.registerOutgoing(1, 2)
        store.receipt(1, 0, "sent", true)
        store.receipt(1, 1, "sent", true)
        store.close()
        store = MessageStore(context)
        provider.failUpdate = true
        assertFalse(SmsSendWatchdog.failIfPending(context, 1))
        assertEquals(4, provider.type)
        provider.failUpdate = false
        assertTrue(SmsSendWatchdog.failIfPending(context, 1))
        assertEquals(2, provider.type)
        assertEquals(32, provider.status) // sent, awaiting optional delivery report
    }

    @Test fun missingCallbacksExpireButRecentAndAlreadySentMessagesDoNotFail() {
        store.registerOutgoing(1, 2)
        store.receipt(1, 0, "sent", true)
        assertFalse(SmsSendWatchdog.failIfPending(context, 1))
        assertEquals(4, provider.type)
        provider.date -= 120_000
        assertTrue(SmsSendWatchdog.failIfPending(context, 1))
        assertEquals(5, provider.type)
        provider.type = 2
        provider.status = 0
        assertFalse(SmsSendWatchdog.failIfPending(context, 1))
        assertEquals(2, provider.type)
        assertEquals(0, provider.status)
    }

    @Test fun completedDeliveryConfirmsSendingEvenIfSentCallbacksWereLost() {
        store.registerOutgoing(1, 2)
        store.receipt(1, 0, "delivered", true)
        store.receipt(1, 1, "delivered", true)
        assertTrue(SmsSendWatchdog.failIfPending(context, 1))
        assertEquals(2, provider.type)
        assertEquals(0, provider.status)
    }

    @Test fun unavailableProviderDoesNotDiscardDurableReceipts() {
        store.registerOutgoing(1, 1)
        store.receipt(1, 0, "sent", true)
        provider.nullQuery = true
        assertFalse(SmsSendWatchdog.failIfPending(context, 1))
        assertEquals(2, store.receiptState(1, "sent"))
        provider.nullQuery = false
        assertTrue(SmsSendWatchdog.failIfPending(context, 1))
        assertEquals(2, provider.type)
    }

    @Test fun foregroundSweepRecoversTrackedOutboxRowsWithoutNeedingAnAlarm() {
        store.registerOutgoing(1, 1)
        store.receipt(1, 0, "sent", true)
        SmsSendWatchdog.sweep(context)
        assertEquals(2, provider.type)
        provider.type = 4
        store.forgetOutgoing(1)
        provider.date -= 120_000
        SmsSendWatchdog.sweep(context)
        assertEquals(4, provider.type)
    }
}
