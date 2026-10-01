import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_config.dart';

/// Keeps one interstitial preloaded and shows it on navigation (see
/// [InterstitialAdNavigatorObserver]), rate-limited by
/// [AdConfig.interstitialCooldown].
///
/// The 5-second length is set on the AdMob side, not here: the SDK owns
/// the full-screen ad once shown, and an app can't close it early. In the
/// AdMob console, edit this interstitial unit and allow only the
/// "Display" ad type (turn Video off) — display interstitials can be
/// closed right away, so the user is never held longer than a few
/// seconds.
class InterstitialAdManager {
  InterstitialAdManager._();

  static final instance = InterstitialAdManager._();

  InterstitialAd? _ad;
  DateTime? _loadedAt;
  DateTime? _lastShownAt;
  bool _loading = false;
  bool _showing = false;
  Timer? _retryTimer;

  void preload() {
    if (!AdConfig.supported || _ad != null || _loading) return;
    _loading = true;
    _retryTimer?.cancel();
    InterstitialAd.load(
      adUnitId: AdConfig.interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _loading = false;
          _ad = ad;
          _loadedAt = DateTime.now();
        },
        onAdFailedToLoad: (error) {
          _loading = false;
          // No fill / offline: try again later instead of hammering.
          _retryTimer = Timer(const Duration(seconds: 60), preload);
        },
      ),
    );
  }

  /// Shows the preloaded interstitial unless one was shown within the
  /// cooldown window or none is ready yet (in which case it starts
  /// loading one for next time).
  void showIfReady() {
    if (!AdConfig.supported || _showing) return;
    final now = DateTime.now();
    final last = _lastShownAt;
    if (last != null && now.difference(last) < AdConfig.interstitialCooldown) return;

    final ad = _ad;
    final loadedAt = _loadedAt;
    if (ad == null || loadedAt == null) {
      preload();
      return;
    }
    if (now.difference(loadedAt) > AdConfig.interstitialMaxAge) {
      ad.dispose();
      _ad = null;
      preload();
      return;
    }

    _ad = null;
    _showing = true;
    _lastShownAt = now;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _showing = false;
        preload();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _showing = false;
        _lastShownAt = last;
        preload();
      },
    );
    ad.show();
  }
}

/// Requests an interstitial whenever a full screen or bottom sheet is
/// opened (a new feature) or closed (back button / back gesture). Dialogs
/// and the app's very first route don't count.
class InterstitialAdNavigatorObserver extends NavigatorObserver {
  static bool _counts(Route<dynamic> route) =>
      route is PageRoute || route is ModalBottomSheetRoute;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null && _counts(route)) _requestAd();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_counts(route)) _requestAd();
  }

  void _requestAd() {
    // Let the route transition finish first, so the ad doesn't cut into
    // the page animation.
    Future<void>.delayed(
      const Duration(milliseconds: 400),
      InterstitialAdManager.instance.showIfReady,
    );
  }
}
