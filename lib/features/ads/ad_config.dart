import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// AdMob ad unit IDs and timing knobs, in one place.
///
/// Unit IDs default to Google's official *test* units, which always fill
/// and are safe to click during development. For a real Play Store build,
/// pass your own units via --dart-define (buildapk.bat reads them from
/// admob_defines.txt — see the comment at the top of that script):
///
///   --dart-define=ADMOB_BANNER_ANDROID=ca-app-pub-XXXX/YYYY
///   --dart-define=ADMOB_INTERSTITIAL_ANDROID=ca-app-pub-XXXX/ZZZZ
///
/// The matching AdMob *app* ID is a separate, native-side setting:
/// ADMOB_APP_ID in android/gradle.properties (Android) and
/// GADApplicationIdentifier in ios/Runner/Info.plist (iOS). Never click
/// your own real ads while testing — AdMob treats that as invalid traffic.
abstract final class AdConfig {
  static const _bannerAndroid = String.fromEnvironment(
    'ADMOB_BANNER_ANDROID',
    defaultValue: 'ca-app-pub-3940256099942544/9214589741',
  );
  static const _bannerIos = String.fromEnvironment(
    'ADMOB_BANNER_IOS',
    defaultValue: 'ca-app-pub-3940256099942544/2435281174',
  );
  static const _interstitialAndroid = String.fromEnvironment(
    'ADMOB_INTERSTITIAL_ANDROID',
    defaultValue: 'ca-app-pub-3940256099942544/1033173712',
  );
  static const _interstitialIos = String.fromEnvironment(
    'ADMOB_INTERSTITIAL_IOS',
    defaultValue: 'ca-app-pub-3940256099942544/4411468910',
  );

  /// The Google Mobile Ads SDK only exists on Android and iOS — on any
  /// other platform (and in widget tests, which run on the host VM) every
  /// ad widget/manager in this folder becomes a no-op.
  static bool get supported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS) && !_isTest;

  static bool get _isTest => Platform.environment.containsKey('FLUTTER_TEST');

  static String get bannerAdUnitId => Platform.isIOS ? _bannerIos : _bannerAndroid;

  static String get interstitialAdUnitId =>
      Platform.isIOS ? _interstitialIos : _interstitialAndroid;

  /// Share of the screen height the home/trading banner occupies.
  static const bannerHeightFraction = 0.15;

  /// How often the banner swaps to a fresh ad. 30s is AdMob's minimum —
  /// app-driven refresh faster than that is a policy violation. Because
  /// the app refreshes it, set this banner unit's own "Automatic refresh"
  /// to *Disabled* in the AdMob console so the two don't stack.
  static const bannerRefreshInterval = Duration(seconds: 30);

  /// Minimum gap between two interstitials. Navigation (back button, new
  /// screen, new sheet) *asks* for one every time, but AdMob's policy
  /// disallows an interstitial after every user action and suspends
  /// accounts that do it, so anything inside this window is skipped.
  /// Lowering it raises that risk.
  static const interstitialCooldown = Duration(seconds: 60);

  /// A loaded interstitial is only valid for an hour; reload before then.
  static const interstitialMaxAge = Duration(minutes: 55);
}
