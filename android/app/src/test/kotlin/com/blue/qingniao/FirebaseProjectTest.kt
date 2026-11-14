package com.blue.qingniao

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class FirebaseProjectTest {
    // Format-only test fixtures. These never register or contact Firebase.
    private val fields = mapOf("projectId" to "format-test-project",
        "senderId" to "123456789012", "applicationId" to "1:123456789012:android:abcdef1234567890",
        "apiKey" to "AIza" + "A".repeat(35))

    @Test fun validatesPublicAndroidIdentifiers() {
        assertEquals(fields, FirebaseProject.fromFields(fields).fields())
    }
    @Test fun rejectsMismatchedProjectAndSender() {
        assertThrows(IllegalArgumentException::class.java) {
            FirebaseProject.fromFields(fields + ("senderId" to "999999999999"))
        }
    }
    @Test fun rejectsMissingOversizeAndMalformedValues() {
        for ((name, value) in listOf("projectId" to "", "apiKey" to "x".repeat(5000),
                "applicationId" to "1:123456789012:ios:abcdef1234567890", "senderId" to "-1")) {
            assertThrows(IllegalArgumentException::class.java) {
                FirebaseProject.fromFields(fields + (name to value))
            }
        }
    }
}
