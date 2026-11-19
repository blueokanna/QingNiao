package com.blue.qingniao

/** Subscription IDs and zero-based logical slot indices are different namespaces. */
internal object SmsSubscriptionIdentity {
    const val UNKNOWN = -1

    fun validId(value: Int): Boolean = value >= 0 && value != Int.MAX_VALUE

    fun resolve(explicitIds: List<Int>, slotIndex: Int, active: List<Pair<Int, Int>>): Int {
        explicitIds.firstOrNull(::validId)?.let { return it }
        if (slotIndex < 0) return UNKNOWN
        return active.filter { validId(it.first) && it.second == slotIndex }
            .map { it.first }.distinct().singleOrNull() ?: UNKNOWN
    }

    fun displaySlot(slotIndex: Int): Int = if (slotIndex >= 0 && slotIndex < Int.MAX_VALUE) slotIndex + 1 else 0
}
