package com.blue.qingniao

import android.app.Application
import android.content.Context
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import org.json.JSONObject

class QingniaoApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        FirebaseConfiguration.initialize(this)
    }
}

/** Configure the default Firebase app before a foreground or background service starts. */
object FirebaseConfiguration {
    private fun prefs(context: Context) = context.getSharedPreferences("firebase_project", Context.MODE_PRIVATE)
    private fun saved(context: Context): FirebaseProject? {
        val raw = prefs(context).getString("configuration", null) ?: return null
        val json = JSONObject(raw)
        return FirebaseProject.fromFields(json.keys().asSequence().associateWith { json.getString(it) })
    }
    private fun options(project: FirebaseProject) = FirebaseOptions.Builder()
        .setProjectId(project.projectId).setApplicationId(project.applicationId)
        .setGcmSenderId(project.senderId).setApiKey(project.apiKey).build()

    private fun desired(context: Context) = saved(context)?.let(::options) ?: FirebaseOptions.fromResource(context)
    private fun current() = runCatching { FirebaseApp.getInstance() }.getOrNull()

    @Synchronized fun initialize(context: Context) {
        if (current() != null) return
        runCatching { desired(context)?.let { FirebaseApp.initializeApp(context.applicationContext, it) } }
    }

    @Synchronized fun status(context: Context): Map<String, Any?> {
        val active = current()?.options
        val desired = runCatching { desired(context) }.getOrNull()
        val restart = active != desired
        return mapOf("configured" to (active != null && !restart),
            "restartRequired" to restart,
            "projectId" to desired?.projectId,
            "configuration" to runCatching { saved(context)?.fields() }.getOrNull(),
            "custom" to prefs(context).contains("configuration"))
    }

    @Synchronized fun save(context: Context, project: FirebaseProject?) {
        check(!context.getSharedPreferences("network_push", Context.MODE_PRIVATE).getBoolean("enabled", false)) {
            "Disable network push before changing its project"
        }
        val edit = prefs(context).edit()
        if (project == null) edit.remove("configuration")
        else edit.putString("configuration", JSONObject(project.fields()).toString())
        check(edit.commit()) { "Unable to save Firebase configuration" }
        // SDK components retain the default app for this process. Never delete it
        // underneath in-flight SDK tasks; a changed project takes effect at launch.
        if (current() == null) initialize(context)
    }
}
