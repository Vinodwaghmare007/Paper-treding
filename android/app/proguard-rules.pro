# Custom R8/ProGuard rules for the release build (isMinifyEnabled/
# isShrinkResources — see build.gradle.kts). Most plugins used here
# (firebase_core/auth/firestore/functions, google_sign_in, webview_flutter,
# home_widget, workmanager, sqflite) ship their own consumer ProGuard rules
# bundled in their AARs, which Gradle merges in automatically — this file
# only needs to cover gaps those don't.
#
# THIS HAS NOT BEEN BUILT-AND-RUN IN THIS SANDBOX (no Android SDK
# available here) — obfuscation/shrinking is exactly the kind of thing
# that can silently break a plugin that reaches a class via reflection at
# runtime rather than failing the build. Before shipping: build a real
# release APK/AAB, install it on a device, and walk through the manual QA
# checklist (docs/MANUAL_QA_CHECKLIST.md) against THAT build, not a debug
# one. If something that works in debug breaks only in release, it's
# almost always a missing keep rule here.

# Flutter's own embedding — normally covered by the Flutter Gradle plugin
# automatically, kept explicitly as a defensive no-op.
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }

# home_widget's HomeWidgetProvider subclass is only referenced by fully-
# qualified class name from AndroidManifest.xml (the <receiver> entry),
# never from Kotlin/Java code directly — R8 can't see that reference and
# may otherwise strip or rename it.
-keep class com.vinodwaghmare.papertrader.crypto_paper_trader.MarketWeatherWidgetProvider { *; }
-keep class es.antonborri.home_widget.** { *; }

# workmanager resolves the registered Dart callback via a stored handle,
# not Java reflection, but its background service/receiver classes are
# also only referenced from AndroidManifest.xml.
-keep class dev.fluttercommunity.workmanager.** { *; }
