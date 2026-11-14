package com.blue.qingniao

import org.json.JSONObject

/** Public Android project identifiers only; never accepts server credentials. */
data class FirebaseProject(val projectId: String, val applicationId: String,
    val senderId: String, val apiKey: String) {
    init {
        require(projectId.matches(Regex("[a-z][a-z0-9-]{4,28}[a-z0-9]"))) { "Invalid Firebase project ID" }
        require(senderId.matches(Regex("[0-9]{6,20}"))) { "Invalid Firebase project number" }
        require(applicationId.matches(Regex("1:${Regex.escape(senderId)}:android:[a-fA-F0-9]{8,64}"))) {
            "Android application ID must belong to the project number"
        }
        require(apiKey.matches(Regex("AIza[A-Za-z0-9_-]{35}"))) { "Invalid Firebase API key" }
    }

    fun fields(): Map<String, String> = mapOf("projectId" to projectId,
        "applicationId" to applicationId, "senderId" to senderId, "apiKey" to apiKey)

    companion object {
        fun fromFields(fields: Map<*, *>): FirebaseProject {
            fun field(name: String) = (fields[name] as? String)?.trim()
                ?: throw IllegalArgumentException("Missing Firebase field")
            return FirebaseProject(field("projectId"), field("applicationId"), field("senderId"), field("apiKey"))
        }

        fun fromGoogleServices(raw: String, packageName: String): FirebaseProject {
            require(raw.length <= 131_072) { "Firebase configuration is too large" }
            val root = JSONObject(raw)
            require(!root.has("private_key") && root.optString("type") != "service_account") {
                "Use google-services.json, not a service account key"
            }
            val project = root.getJSONObject("project_info")
            val clients = root.getJSONArray("client")
            val matches = (0 until clients.length()).map { clients.getJSONObject(it) }.filter {
                it.getJSONObject("client_info").getJSONObject("android_client_info")
                    .getString("package_name") == packageName
            }
            require(matches.size == 1) { "Configuration must contain exactly one matching Android app" }
            val client = matches.single()
            return FirebaseProject(project.getString("project_id"),
                client.getJSONObject("client_info").getString("mobilesdk_app_id"),
                project.getString("project_number"),
                client.getJSONArray("api_key").getJSONObject(0).getString("current_key"))
        }
    }
}
