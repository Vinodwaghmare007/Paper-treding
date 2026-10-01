import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Requires android/app/google-services.json — see setup notes.
    id("com.google.gms.google-services")
    // Uploads mapping/symbol files at build time for de-obfuscated crash
    // reports — required for firebase_crashlytics beyond just the Dart
    // package dependency in pubspec.yaml.
    id("com.google.firebase.crashlytics")
}

// Release signing config, read from android/key.properties (gitignored —
// see android/.gitignore). That file is NOT checked in and never should
// be; generate the keystore yourself and keep both the .jks/.keystore
// file and its passwords somewhere durable and backed up outside this
// repo. Losing the release keystore means losing the ability to publish
// any future update to the same Play Store listing — Google cannot
// recover or reset it for you.
//
// One-time setup:
//   keytool -genkey -v -keystore ~/crypto-paper-trader-release.keystore \
//     -keyalg RSA -keysize 2048 -validity 10000 -alias crypto_paper_trader
//
// Then create android/key.properties (NOT android/app/key.properties):
//   storePassword=<the keystore password>
//   keyPassword=<the key password>
//   keyAlias=crypto_paper_trader
//   storeFile=/absolute/path/to/crypto-paper-trader-release.keystore
//
// Without that file present, release builds fall back to the debug
// signing config (as before this change) so `flutter run --release` and
// CI builds that don't need a real release artifact still work — but a
// debug-signed build cannot be uploaded to the Play Store, so watch for
// the warning this prints when that happens.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasReleaseSigningConfig = keystorePropertiesFile.exists()
if (hasReleaseSigningConfig) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
} else {
    logger.warn(
        "android/key.properties not found — release builds will be signed " +
            "with the debug keystore and CANNOT be uploaded to the Play " +
            "Store. See the comment above this warning in app/build.gradle.kts."
    )
}

// AdMob app ID (ca-app-pub-XXXX~YYYY) from ADMOB_APP_ID in
// android/gradle.properties. Falls back to Google's sample app ID, which
// only serves test ads — set the real one before a Play Store release.
val admobTestAppId = "ca-app-pub-3940256099942544~3347511713"
val admobAppId = (project.findProperty("ADMOB_APP_ID") as String?)
    ?.takeIf { it.isNotBlank() } ?: admobTestAppId
if (admobAppId == admobTestAppId) {
    logger.warn("ADMOB_APP_ID not set in android/gradle.properties — using AdMob's test app ID.")
}

android {
    namespace = "com.vinodwaghmare.papertrader.crypto_paper_trader"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        // flutter_local_notifications (18.x) requires core library
        // desugaring — without this, Gradle fails at
        // :app:checkDebugAarMetadata with "requires core library
        // desugaring to be enabled for :app" before compilation even
        // starts. The desugar_jdk_libs version below is the commonly
        // documented minimum for recent flutter_local_notifications
        // releases; this sandbox has no Android SDK/Gradle to verify it
        // against a real build (see docs/RELEASE.md) — if Gradle still
        // complains about the desugaring library version specifically,
        // bump the version below to whatever it asks for.
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.vinodwaghmare.papertrader.crypto_paper_trader"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // versionCode/versionName come from pubspec.yaml's `version:` field
        // (currently 1.0.0+1 -> versionName "1.0.0", versionCode 1). Bump
        // the `+N` build-number suffix for every Play Store upload
        // (versionCode must strictly increase), and the `X.Y.Z` part
        // following semver — patch for fixes, minor for new features
        // (e.g. each of Phases 1-5), major only for a breaking rework.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["admobAppId"] = admobAppId
    }

    signingConfigs {
        if (hasReleaseSigningConfig) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigningConfig) {
                signingConfigs.getByName("release")
            } else {
                // See the warning logged above — debug-signed, not
                // Play-Store-uploadable, but keeps `flutter run --release`
                // and CI builds working without a real keystore present.
                signingConfigs.getByName("debug")
            }

            // R8 (AGP's default minifier/shrinker for isMinifyEnabled).
            // Test the actual release build after enabling this, not just
            // debug — obfuscation/shrinking is exactly the kind of thing
            // that can silently strip a class a plugin reaches via
            // reflection. See the manual QA checklist for the "did the
            // release build actually launch and trade" pass this needs.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}

flutter {
    source = "../.."
}
