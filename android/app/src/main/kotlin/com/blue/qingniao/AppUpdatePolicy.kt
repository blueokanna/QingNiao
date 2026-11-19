package com.blue.qingniao

import java.net.URI

/** Restricts metadata and download redirects to the project's GitHub release infrastructure. */
internal object AppUpdatePolicy {
    const val REPOSITORY = "blueokanna/qingniao"
    const val LATEST_URL = "https://api.github.com/repos/$REPOSITORY/releases/latest"
    const val MAX_APK_BYTES = 256L * 1024 * 1024
    const val MAX_METADATA_BYTES = 1024 * 1024

    private val assetPath = Regex("/$REPOSITORY/releases/download/v[0-9]+\\.[0-9]+\\.[0-9]+/(update\\.json|qingniao-release\\.apk)")

    fun releaseAsset(raw: String): Boolean = runCatching {
        val uri = URI(raw)
        secure(uri) && uri.host == "github.com" &&
            assetPath.matches(uri.rawPath) &&
            uri.rawQuery == null && uri.rawFragment == null
    }.getOrDefault(false)

    fun downloadUrl(raw: String): Boolean = runCatching {
        val uri = URI(raw)
        secure(uri) && (releaseAsset(raw) || uri.host in setOf(
            "release-assets.githubusercontent.com", "objects.githubusercontent.com",
        ))
    }.getOrDefault(false)

    private fun secure(uri: URI) = uri.scheme == "https" && uri.userInfo == null &&
        (uri.port == -1 || uri.port == 443)

    fun validDigest(value: String) = value.matches(Regex("[a-f0-9]{64}"))

    fun compatibleVersion(installed: Long, candidate: Long) =
        candidate > installed && candidate <= 2_100_000_000L
}
