package com.blue.qingniao

import android.app.Activity
import android.hardware.display.DisplayManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.View

class DisplayCadence(private val activity: Activity) : DisplayManager.DisplayListener {
    private val manager = activity.getSystemService(DisplayManager::class.java)
    private var registered = false

    fun resume() {
        if (!registered) {
            manager.registerDisplayListener(this, Handler(Looper.getMainLooper()))
            registered = true
        }
        apply()
    }

    fun pause() {
        if (registered) manager.unregisterDisplayListener(this)
        registered = false
        activity.window.attributes = activity.window.attributes.apply { preferredRefreshRate = 0f }
    }

    private fun apply() {
        val display = activity.display ?: return
        val rate = display.refreshRate
        if (!rate.isFinite() || rate <= 0) return
        val attributes = activity.window.attributes
        if (kotlin.math.abs(attributes.preferredRefreshRate - rate) > .1f) {
            attributes.preferredRefreshRate = rate
            activity.window.attributes = attributes
        }
        if (Build.VERSION.SDK_INT >= 35) {
            activity.window.decorView.requestedFrameRate = View.REQUESTED_FRAME_RATE_CATEGORY_HIGH
        }
    }

    override fun onDisplayChanged(displayId: Int) { if (activity.display?.displayId == displayId) apply() }
    override fun onDisplayAdded(displayId: Int) = Unit
    override fun onDisplayRemoved(displayId: Int) = Unit
}
