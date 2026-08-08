pluginManagement {
    val flutterSdkPath = run {
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
    id("com.android.application") version "8.7.3" apply false
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
    // Reads android/app/google-services.json at build time (see setup notes).
    id("com.google.gms.google-services") version "4.4.2" apply false
    // Uploads mapping/symbol files at build time for de-obfuscated crash
    // reports — cross-checked against firebase_crashlytics' own example
    // project setup (its pub cache ships one), not guessed; pin may be a
    // patch or two behind whatever's newest by the time this is built.
    id("com.google.firebase.crashlytics") version "3.0.2" apply false
}

include(":app")
