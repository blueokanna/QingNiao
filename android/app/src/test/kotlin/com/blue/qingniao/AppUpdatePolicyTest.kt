package com.blue.qingniao

import org.junit.Assert.*
import org.junit.Test

class AppUpdatePolicyTest {
    @Test fun onlyProjectReleaseAssetsAreAcceptedAsInitialDownloads() {
        assertTrue(AppUpdatePolicy.releaseAsset("https://github.com/blueokanna/qingniao/releases/download/v1.2.3/update.json"))
        for (url in listOf(
            "http://github.com/blueokanna/qingniao/releases/download/v1.2.3/update.json",
            "https://github.com.evil.test/blueokanna/qingniao/releases/download/v1.2.3/update.json",
            "https://github.com/other/qingniao/releases/download/v1.2.3/update.json",
            "https://user@github.com/blueokanna/qingniao/releases/download/v1.2.3/update.json",
            "https://github.com:444/blueokanna/qingniao/releases/download/v1.2.3/update.json",
            "https://github.com/blueokanna/qingniao/releases/download/v1.2.3/update.json?redirect=other",
            "https://github.com/blueokanna/qingniao/releases/download/v1.2.3/../../file.apk",
            "https://github.com/blueokanna/qingniao/releases/download/v1.2.3/other.apk",
            "https://github.com/blueokanna/qingniao/releases/download/%2e%2e/update.json",
            "file:///tmp/update.apk",
        )) assertFalse(url, AppUpdatePolicy.releaseAsset(url))
    }

    @Test fun redirectsStayOnExplicitHttpsAssetHosts() {
        assertTrue(AppUpdatePolicy.downloadUrl("https://release-assets.githubusercontent.com/github-production-release-asset/1?sig=abc"))
        assertTrue(AppUpdatePolicy.downloadUrl("https://objects.githubusercontent.com/asset"))
        assertFalse(AppUpdatePolicy.downloadUrl("https://raw.githubusercontent.com/blueokanna/qingniao/main/update.apk"))
        assertFalse(AppUpdatePolicy.downloadUrl("https://localhost/update.apk"))
        assertFalse(AppUpdatePolicy.downloadUrl("https://release-assets.githubusercontent.com.evil.test/asset"))
        assertFalse(AppUpdatePolicy.downloadUrl("http://objects.githubusercontent.com/asset"))
    }

    @Test fun updateVersionMustIncreaseWithinAndroidLimits() {
        assertTrue(AppUpdatePolicy.compatibleVersion(1, 2))
        assertFalse(AppUpdatePolicy.compatibleVersion(2, 2))
        assertFalse(AppUpdatePolicy.compatibleVersion(2, 1))
        assertFalse(AppUpdatePolicy.compatibleVersion(2, Long.MAX_VALUE))
        assertTrue(AppUpdatePolicy.validDigest("a".repeat(64)))
        assertFalse(AppUpdatePolicy.validDigest("a".repeat(63)))
        assertFalse(AppUpdatePolicy.validDigest("g".repeat(64)))
    }
}
