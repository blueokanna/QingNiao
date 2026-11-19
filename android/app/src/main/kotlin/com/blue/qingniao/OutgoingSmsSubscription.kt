package com.blue.qingniao

internal object OutgoingSmsSubscription {
    // null means phone-state permission is unavailable, not that there are no SIMs.
    fun resolve(requested: Int, defaultId: Int, activeIds: List<Int>?): Int {
        val active = activeIds?.filter(SmsSubscriptionIdentity::validId)?.distinct()
        if (SmsSubscriptionIdentity.validId(requested)) {
            check(active == null || requested in active) { "The selected SIM is unavailable. Choose an active SIM." }
            return requested
        }
        if (SmsSubscriptionIdentity.validId(defaultId) && (active == null || defaultId in active)) return defaultId
        active?.singleOrNull()?.let { return it }
        check(active?.isEmpty() != true) { "No active SIM is available for sending SMS." }
        error("Choose a SIM for sending SMS.")
    }
}
