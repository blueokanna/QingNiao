package com.blue.qingniao

import android.content.Context
import android.content.pm.PackageManager
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

/** Update I/O is independent of the SMS queue and never retains an Activity. */
internal object AppUpdates {
    val executor = ThreadPoolExecutor(0, 1, 30, TimeUnit.SECONDS, LinkedBlockingQueue<Runnable>())
    private data class Release(
        val versionName: String, val versionCode: Long, val size: Long,
        val sha256: String, val apkUrl: String, val pageUrl: String, val notes: String,
    ) {
        fun fields() = mapOf(
            "versionName" to versionName, "versionCode" to versionCode,
            "size" to size, "pageUrl" to pageUrl, "notes" to notes,
        )
    }
    private var release: Release? = null
    private var phase = "idle"
    private var received = 0L
    private var lastChecked = 0L
    private var failure: String? = null
    private var readyDigest: String? = null
    // The single update executor owns the validated response and its HTTP validator.
    private var latestEtag: String? = null
    private var cachedRelease: Release? = null

    @Synchronized fun snapshot(context: Context): Map<String, Any?> {
        val installed = context.packageManager.getPackageInfo(context.packageName, 0)
        return mapOf(
            "versionName" to installed.versionName.orEmpty(),
            "versionCode" to installed.longVersionCode,
            "phase" to phase, "received" to received, "lastChecked" to lastChecked,
            "error" to failure, "release" to release?.fields(),
            "canInstall" to context.packageManager.canRequestPackageInstalls(),
        )
    }

    fun check(context: Context) {
        val previouslyReady = synchronized(this) {
            if (phase in setOf("checking", "downloading", "verifying")) return
            val ready = phase == "ready"
            phase = "checking"
            failure = null
            ready
        }
        executor.execute {
            try {
                val installed = context.packageManager.getPackageInfo(context.packageName, 0)
                val candidate = fetchLatest()
                synchronized(this) {
                    release = candidate?.takeIf {
                        AppUpdatePolicy.compatibleVersion(installed.longVersionCode, it.versionCode)
                    }
                    phase = when {
                        candidate == null -> "no_release"
                        release == null -> "current"
                        release?.sha256 == readyDigest && readyFile(context).length() == release?.size -> "ready"
                        else -> "available"
                    }
                    lastChecked = System.currentTimeMillis()
                }
            } catch (_: Exception) {
                synchronized(this) { phase = if (previouslyReady) "ready" else "error"; failure = "check_failed" }
            }
        }
    }

    private fun parseRelease(raw: JSONObject): Release? {
        if (raw.optBoolean("draft", true) || raw.optBoolean("prerelease", true)) return null
        val tag = raw.getString("tag_name")
        val assets = raw.getJSONArray("assets")
        require(assets.length() <= 100)
        fun asset(name: String): JSONObject {
            val matches = (0 until assets.length()).map { assets.getJSONObject(it) }
                .filter { it.optString("name") == name }
            require(matches.size == 1) { "Missing or ambiguous release asset" }
            return matches.single()
        }
        val manifestAsset = asset("update.json")
        require(manifestAsset.getLong("size") in 1..AppUpdatePolicy.MAX_METADATA_BYTES.toLong())
        val manifestUrl = manifestAsset.getString("browser_download_url")
        require(AppUpdatePolicy.releaseAsset(manifestUrl, tag, "update.json"))
        val connection = open(manifestUrl)
        val manifest = try { readJson(connection) } finally { connection.disconnect() }
        require(integer(manifest, "schemaVersion") == 1L)
        val version = manifest.getString("versionName")
        require(version.matches(Regex("[0-9]+\\.[0-9]+\\.[0-9]+")))
        require(tag == "v$version")
        val code = integer(manifest, "versionCode")
        require(code in 1..2_100_000_000L)
        val size = integer(manifest, "size")
        require(size in 1..AppUpdatePolicy.MAX_APK_BYTES)
        val sha256 = manifest.getString("sha256")
        require(AppUpdatePolicy.validDigest(sha256))
        require(manifest.getString("apkName") == "qingniao-release.apk")
        val apk = asset("qingniao-release.apk")
        require(apk.getLong("size") == size)
        val apkUrl = apk.getString("browser_download_url")
        require(AppUpdatePolicy.releaseAsset(apkUrl, tag, "qingniao-release.apk"))
        return Release(version, code, size, sha256, apkUrl,
            "https://github.com/${AppUpdatePolicy.REPOSITORY}/releases/tag/v$version",
            raw.optString("body").take(12_000))
    }

    fun download(context: Context) {
        val candidate = synchronized(this) {
            if (phase in setOf("checking", "downloading", "verifying", "ready")) return
            val value = release ?: return
            phase = "downloading"
            failure = null
            received = 0
            value
        }
        executor.execute {
            var part: File? = null
            try {
                val downloadFile = File(directory(context), "update.part")
                part = downloadFile
                val digest = MessageDigest.getInstance("SHA-256")
                val started = System.nanoTime()
                open(candidate.apkUrl).let { connection ->
                    try {
                        require(connection.responseCode == HttpURLConnection.HTTP_OK)
                        val declared = connection.contentLengthLong
                        require(declared == -1L || declared == candidate.size)
                        connection.inputStream.use { input ->
                            downloadFile.outputStream().use { output ->
                                val buffer = ByteArray(64 * 1024)
                                var total = 0L
                                while (true) {
                                    check(TimeUnit.NANOSECONDS.toMinutes(System.nanoTime() - started) < 15)
                                    val count = input.read(buffer)
                                    if (count == -1) break
                                    total += count
                                    require(total <= candidate.size)
                                    digest.update(buffer, 0, count)
                                    output.write(buffer, 0, count)
                                    synchronized(this) { received = total }
                                }
                                require(total == candidate.size)
                                output.fd.sync()
                            }
                        }
                    } finally { connection.disconnect() }
                }
                synchronized(this) { phase = "verifying" }
                require(hex(digest.digest()) == candidate.sha256)
                verifyApk(context, downloadFile, candidate)
                val ready = readyFile(context)
                if (ready.exists()) check(ready.delete())
                check(downloadFile.renameTo(ready))
                synchronized(this) { readyDigest = candidate.sha256; phase = "ready" }
            } catch (_: Exception) {
                part?.delete()
                synchronized(this) { phase = "error"; failure = "download_failed" }
            }
        }
    }

    @Synchronized fun beginInstall(): Boolean {
        if (phase != "ready") return false
        phase = "verifying"
        return true
    }

    @Synchronized fun finishInstallVerification() { phase = "ready" }

    fun invalidateDownload(context: Context) {
        runCatching { readyFile(context).delete() }
        synchronized(this) { readyDigest = null; phase = "error"; failure = "download_failed"; received = 0 }
    }

    private fun integer(value: JSONObject, key: String): Long = when (val number = value.get(key)) {
        is Int -> number.toLong()
        is Long -> number
        else -> throw IllegalArgumentException("Expected integer $key")
    }

    /** Re-check the complete private file immediately before granting the installer access. */
    fun verifiedInstallerFile(context: Context): File {
        val candidate = synchronized(this) {
            check(phase == "verifying")
            requireNotNull(release)
        }
        val file = readyFile(context)
        require(file.length() == candidate.size)
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val count = input.read(buffer)
                if (count == -1) break
                digest.update(buffer, 0, count)
            }
        }
        require(hex(digest.digest()) == candidate.sha256)
        verifyApk(context, file, candidate)
        return file
    }

    @Suppress("DEPRECATION")
    private fun verifyApk(context: Context, file: File, candidate: Release) {
        val manager = context.packageManager
        val installed = manager.getPackageInfo(context.packageName, PackageManager.GET_SIGNING_CERTIFICATES)
        val archive = requireNotNull(manager.getPackageArchiveInfo(file.path, PackageManager.GET_SIGNING_CERTIFICATES))
        require(archive.packageName == context.packageName)
        require(archive.longVersionCode == candidate.versionCode && archive.versionName == candidate.versionName)
        require(AppUpdatePolicy.compatibleVersion(installed.longVersionCode, archive.longVersionCode))
        val forbiddenFlags = android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE or android.content.pm.ApplicationInfo.FLAG_TEST_ONLY
        require((requireNotNull(archive.applicationInfo).flags and forbiddenFlags) == 0)
        val installedSigners = requireNotNull(installed.signingInfo).apkContentsSigners.map { hex(it.toByteArray()) }.toSet()
        val downloadedSigners = requireNotNull(archive.signingInfo).apkContentsSigners.map { hex(it.toByteArray()) }.toSet()
        require(installedSigners.isNotEmpty() && installedSigners == downloadedSigners)
    }

    private fun hex(bytes: ByteArray) = bytes.joinToString("") { "%02x".format(it.toInt() and 255) }
    private fun directory(context: Context) = File(context.cacheDir, "app_updates").apply {
        check(isDirectory || mkdirs())
    }
    fun readyFile(context: Context) = File(directory(context), "qingniao-update.apk")

    private fun fetchLatest(): Release? {
        val connection = open(AppUpdatePolicy.LATEST_URL, api = true)
        return try {
            when (connection.responseCode) {
                HttpURLConnection.HTTP_NOT_MODIFIED -> requireNotNull(cachedRelease)
                HttpURLConnection.HTTP_NOT_FOUND -> {
                    latestEtag = null
                    cachedRelease = null
                    null
                }
                else -> {
                    val etag = connection.getHeaderField("ETag")
                    val candidate = parseRelease(readJson(connection))
                    cachedRelease = candidate
                    latestEtag = etag.takeIf { candidate != null }
                    candidate
                }
            }
        } finally { connection.disconnect() }
    }

    private fun readJson(connection: HttpURLConnection): JSONObject {
        require(connection.responseCode == HttpURLConnection.HTTP_OK)
        require(connection.contentLengthLong <= AppUpdatePolicy.MAX_METADATA_BYTES)
        val started = System.nanoTime()
        val bytes = ByteArrayOutputStream()
        connection.inputStream.use { input ->
            val buffer = ByteArray(8192)
            while (true) {
                check(TimeUnit.NANOSECONDS.toSeconds(System.nanoTime() - started) < 45)
                val count = input.read(buffer)
                if (count == -1) break
                require(bytes.size() + count <= AppUpdatePolicy.MAX_METADATA_BYTES)
                bytes.write(buffer, 0, count)
            }
        }
        return JSONObject(bytes.toString(Charsets.UTF_8.name()))
    }

    private fun open(initial: String, api: Boolean = false): HttpURLConnection {
        var url = initial
        repeat(6) {
            require(if (api) url == AppUpdatePolicy.LATEST_URL else AppUpdatePolicy.downloadUrl(url))
            val connection = URL(url).openConnection() as HttpURLConnection
            connection.instanceFollowRedirects = false
            connection.connectTimeout = 15_000
            connection.readTimeout = 20_000
            connection.setRequestProperty("User-Agent", "Qingniao-Android-Updater")
            connection.setRequestProperty("Accept-Encoding", "identity")
            if (api) {
                latestEtag?.let { connection.setRequestProperty("If-None-Match", it) }
                connection.setRequestProperty("Accept", "application/vnd.github+json")
                connection.setRequestProperty("X-GitHub-Api-Version", "2022-11-28")
            }
            try {
                if (connection.responseCode in setOf(301, 302, 303, 307, 308)) {
                    val next = requireNotNull(connection.getHeaderField("Location"))
                    url = URL(URL(url), next).toExternalForm()
                    connection.disconnect()
                } else return connection
            } catch (error: Exception) {
                connection.disconnect()
                throw error
            }
        }
        error("Too many redirects")
    }
}
