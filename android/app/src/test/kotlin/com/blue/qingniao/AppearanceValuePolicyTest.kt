package com.blue.qingniao

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AppearanceValuePolicyTest {
    @Test fun acceptsClientSettingsAndInclusiveBoundaries() {
        for ((key, values) in mapOf(
            "starfieldSeed" to listOf("0", "9031", "4294967295"),
            "navigationBlur" to listOf("0.0", "18.0", "32.0"),
            "navigationOpacity" to listOf("0.55", "0.78", "0.95")
        )) for (value in values) assertTrue("$key=$value", AppearanceValuePolicy.accepts(key, value))
    }

    @Test fun rejectsInvalidNumericPayloads() {
        for (key in AppearanceValuePolicy.keys) {
            for (value in listOf("NaN", "Infinity", "-Infinity", "", "bad", "1e10000", "-1")) {
                assertFalse("$key=$value", AppearanceValuePolicy.accepts(key, value))
            }
        }
        assertFalse(AppearanceValuePolicy.accepts("starfieldSeed", "4294967296"))
        assertFalse(AppearanceValuePolicy.accepts("starfieldSeed", "1.5"))
        assertFalse(AppearanceValuePolicy.accepts("navigationBlur", "32.01"))
        assertFalse(AppearanceValuePolicy.accepts("navigationOpacity", "0.54"))
        assertFalse(AppearanceValuePolicy.accepts("navigationOpacity", "0.96"))
        assertFalse(AppearanceValuePolicy.accepts("unknown", "1"))
    }
}
