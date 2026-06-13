pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    // Pinned to 2.1.x because sentry_flutter 8.x still ships Android
    // code declaring language version 1.6; Kotlin 2.2+ rejects it.
    // When sentry_flutter is bumped to v9 (declares 1.8+) this can
    // move back to the latest 2.x.
    id("org.jetbrains.kotlin.android") version "2.1.21" apply false
}

include(":app")
