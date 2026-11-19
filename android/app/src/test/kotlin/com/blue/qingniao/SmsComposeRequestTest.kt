package com.blue.qingniao

import org.junit.Assert.*
import org.junit.Test

class SmsComposeRequestTest {
    private val sendTo = "android.intent.action.SENDTO"

    @Test fun decodesPhoneAndBodyWithoutTurningPlusIntoSpace() {
        val request = SmsComposeRequest.parse(sendTo, "sms:%2B8613800000000?body=%E4%BD%A0%E5%A5%BD%20A+B%26C%3F%0Aline2")!!
        assertEquals(listOf("+8613800000000"), request.recipients)
        assertEquals("\u4f60\u597d A+B&C?\nline2", request.body)
    }

    @Test fun acceptsAllSmsSchemesAndMultipleRecipients() {
        for (scheme in listOf("sms", "smsto", "mms", "mmsto")) {
            val request = SmsComposeRequest.parse(sendTo, "$scheme:+12345;67890,67890?body=hello")!!
            assertEquals(listOf("+12345", "67890"), request.recipients)
            assertEquals("hello", request.body)
        }
    }

    @Test fun acceptsBodyOnlyAndEmptyComposeRequests() {
        assertEquals(SmsComposeRequest(emptyList(), "hello"), SmsComposeRequest.parse(sendTo, "smsto:", body = "hello"))
        assertEquals(SmsComposeRequest(emptyList(), ""), SmsComposeRequest.parse(sendTo, "sms:"))
        assertEquals(SmsComposeRequest(emptyList(), "shared text"),
            SmsComposeRequest.parse("android.intent.action.SEND", null, text = "shared text"))
    }

    @Test fun supportsBrowserLinksAndExtrasWithPredictablePrecedence() {
        assertEquals(SmsComposeRequest(listOf("12345"), "hello"),
            SmsComposeRequest.parse("android.intent.action.VIEW", "sms:12345?body=hello"))
        assertEquals(SmsComposeRequest(listOf("67890", "54321"), "extra body"),
            SmsComposeRequest.parse(sendTo, "smsto:12345?body=uri", address = "67890",
                extraRecipients = listOf("54321"), body = "extra body", text = "text"))
    }

    @Test fun ignoresLauncherNotificationAndUnrelatedWebIntents() {
        assertNull(SmsComposeRequest.parse(null, null, address = "12345"))
        assertNull(SmsComposeRequest.parse("android.intent.action.MAIN", null))
        assertNull(SmsComposeRequest.parse("android.intent.action.VIEW", "https://example.com"))
    }

    @Test fun malformedEscapesDoNotCrashOrDecodeTwice() {
        assertEquals("bad%xx", SmsComposeRequest.parse(sendTo, "sms:12345?body=bad%xx")!!.body)
        assertEquals("%26", SmsComposeRequest.parse(sendTo, "sms:12345?body=%2526")!!.body)
    }
}
