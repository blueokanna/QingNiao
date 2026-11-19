package com.blue.qingniao

import java.util.Locale

internal object MessageAddress {
    fun normalize(value: String): String {
        val trimmed = value.trim()
        // Alphanumeric sender IDs are identities, not vanity phone numbers.
        if (trimmed.any { it.isLetter() }) return trimmed.lowercase(Locale.ROOT)
        val number = buildString {
            for (character in trimmed) {
                when {
                    character.isDigit() -> append(character.digitToInt())
                    character == '+' || character == '*' || character == '#' -> append(character)
                }
            }
        }
        return if (number.startsWith("00")) "+${number.substring(2)}" else number
    }
}
