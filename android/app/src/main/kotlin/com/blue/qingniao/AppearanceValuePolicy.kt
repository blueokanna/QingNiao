package com.blue.qingniao

/** Numeric settings shared with AppSettings; reject nonfinite or out-of-range input. */
internal object AppearanceValuePolicy {
    val keys = setOf("starfieldSeed", "navigationBlur", "navigationOpacity")

    fun accepts(key: String, value: String): Boolean = when (key) {
        "starfieldSeed" -> value.toLongOrNull()?.let { it in 0L..0xffff_ffffL } == true
        "navigationBlur" -> value.toDoubleOrNull()?.let { it.isFinite() && it in 0.0..32.0 } == true
        "navigationOpacity" -> value.toDoubleOrNull()?.let { it.isFinite() && it in 0.55..0.95 } == true
        else -> false
    }
}
