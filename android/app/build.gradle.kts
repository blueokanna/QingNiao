plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseCredentials = listOf(
    "QINGNIAO_KEYSTORE_PATH", "QINGNIAO_STORE_PASSWORD",
    "QINGNIAO_KEY_ALIAS", "QINGNIAO_KEY_PASSWORD"
).associateWith { providers.environmentVariable(it).orNull }
val hasReleaseCredentials = releaseCredentials.values.all { !it.isNullOrBlank() }
val verifyReleaseSigning by tasks.registering {
    doLast {
        check(hasReleaseCredentials) { "Release signing requires QINGNIAO_KEYSTORE_PATH, QINGNIAO_STORE_PASSWORD, QINGNIAO_KEY_ALIAS and QINGNIAO_KEY_PASSWORD." }
        check(file(releaseCredentials.getValue("QINGNIAO_KEYSTORE_PATH")!!).isFile) { "Release keystore does not exist." }
    }
}
tasks.configureEach {
    if (name in setOf("packageRelease", "packageReleaseBundle", "signReleaseBundle", "assembleRelease", "bundleRelease")) {
        dependsOn(verifyReleaseSigning)
    }
}

android {
    namespace = "com.blue.qingniao"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.blue.qingniao"
        minSdk = 31
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseCredentials) {
            create("production") {
                storeFile = file(releaseCredentials.getValue("QINGNIAO_KEYSTORE_PATH")!!)
                storePassword = releaseCredentials.getValue("QINGNIAO_STORE_PASSWORD")
                keyAlias = releaseCredentials.getValue("QINGNIAO_KEY_ALIAS")
                keyPassword = releaseCredentials.getValue("QINGNIAO_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseCredentials) signingConfigs.getByName("production") else null
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("com.klinkerapps:android-smsmms:5.2.6") { isTransitive = false }
    implementation("com.klinkerapps:logger:1.0.3")
}
