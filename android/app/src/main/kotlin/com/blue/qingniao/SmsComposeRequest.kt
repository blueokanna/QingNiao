package com.blue.qingniao

import java.net.URLDecoder

/** Parses opaque sms:/smsto: URIs as well as extras without losing literal '+' characters. */
internal data class SmsComposeRequest(val recipients: List<String>, val body: String) {
    fun fields(): Map<String, Any> = mapOf(
        "compose" to true, "address" to recipients.firstOrNull().orEmpty(),
        "recipients" to recipients, "body" to body,
    )

    companion object {
        fun parse(action: String?, uri: String?, address: String? = null,
                  extraRecipients: List<String> = emptyList(), body: String? = null,
                  text: String? = null): SmsComposeRequest? {
            val scheme = uri?.substringBefore(':')?.lowercase()
            val smsUri = scheme in setOf("sms", "smsto", "mms", "mmsto")
            val compose = action == "android.intent.action.SENDTO" && smsUri ||
                action == "android.intent.action.VIEW" && smsUri ||
                action == "android.intent.action.SEND"
            if (!compose) return null
            val target = if (smsUri) uri!!.substringAfter(':').substringBefore('#') else ""
            val query = target.substringAfter('?', "").split('&').mapNotNull {
                if ('=' !in it) null else decode(it.substringBefore('=')) to decode(it.substringAfter('='))
            }.toMap()
            val rawRecipients = address?.takeIf { it.isNotBlank() }
                ?: target.substringBefore('?').removePrefix("//").let(::decode)
            val recipients = (listOf(rawRecipients) + extraRecipients)
                .flatMap { it.split(',', ';') }.map(String::trim).filter(String::isNotEmpty).distinct()
            return SmsComposeRequest(recipients, body ?: query["body"] ?: query["sms_body"] ?: text.orEmpty())
        }

        private fun decode(value: String): String = try {
            URLDecoder.decode(value.replace("+", "%2B"), "UTF-8")
        } catch (_: IllegalArgumentException) { value }
    }
}
