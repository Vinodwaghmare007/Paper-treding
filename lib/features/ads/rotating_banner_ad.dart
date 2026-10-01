import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_config.dart';

/// Banner strip taking [AdConfig.bannerHeightFraction] of the screen
/// height, swapping to a fresh ad every [AdConfig.bannerRefreshInterval].
///
/// The next ad loads in the background while the current one stays on
/// screen, so the strip never goes blank between rotations. Refresh pauses
/// while another route covers this one or the app is in the background —
/// AdMob disallows refreshing a banner nobody can see. Takes no space at
/// all until the first ad has loaded (offline / no fill).
class RotatingBannerAd extends StatefulWidget {
  const RotatingBannerAd({super.key});

  @override
  State<RotatingBannerAd> createState() => _RotatingBannerAdState();
}

class _RotatingBannerAdState extends State<RotatingBannerAd> with WidgetsBindingObserver {
  BannerAd? _current;
  AdSize? _currentSize;
  BannerAd? _pending;
  Timer? _refreshTimer;
  bool _inForeground = true;
  int? _requestedWidth;
  int? _requestedMaxHeight;

  @override
  void initState() {
    super.initState();
    if (!AdConfig.supported) return;
    WidgetsBinding.instance.addObserver(this);
    _refreshTimer = Timer.periodic(AdConfig.bannerRefreshInterval, (_) => _refresh());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!AdConfig.supported) return;
    final size = MediaQuery.sizeOf(context);
    final width = size.width.truncate();
    final maxHeight = _maxHeightFor(size.height).truncate();
    // First build, or rotation changed the slot size: load an ad that fits.
    if (width != _requestedWidth || maxHeight != _requestedMaxHeight) {
      _requestedWidth = width;
      _requestedMaxHeight = maxHeight;
      _pending?.dispose();
      _pending = null;
      _load();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _inForeground = state == AppLifecycleState.resumed;
  }

  static double _maxHeightFor(double screenHeight) =>
      // Inline adaptive banners need at least 32dp; 50 keeps landscape usable.
      (screenHeight * AdConfig.bannerHeightFraction).clamp(50.0, double.infinity);

  void _refresh() {
    if (!mounted || !_inForeground) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    _load();
  }

  void _load() {
    final width = _requestedWidth;
    final maxHeight = _requestedMaxHeight;
    if (_pending != null || width == null || maxHeight == null) return;

    final ad = BannerAd(
      adUnitId: AdConfig.bannerAdUnitId,
      size: AdSize.getInlineAdaptiveBannerAdSize(width, maxHeight),
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (loaded) async {
          final banner = loaded as BannerAd;
          final platformSize = await banner.getPlatformAdSize();
          if (!mounted || !identical(banner, _pending)) {
            banner.dispose();
            return;
          }
          final previous = _current;
          setState(() {
            _current = banner;
            _currentSize = platformSize ?? banner.size;
            _pending = null;
          });
          // Dispose the old ad only after its AdWidget has left the tree.
          WidgetsBinding.instance.addPostFrameCallback((_) => previous?.dispose());
        },
        onAdFailedToLoad: (failed, error) {
          failed.dispose();
          if (identical(failed, _pending)) _pending = null;
          // Keep showing the current ad; the next tick tries again.
        },
      ),
    );
    _pending = ad;
    ad.load();
  }

  @override
  void dispose() {
    if (AdConfig.supported) WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _pending?.dispose();
    _current?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _current;
    final adSize = _currentSize;
    if (ad == null || adSize == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      height: _maxHeightFor(MediaQuery.sizeOf(context).height),
      color: const Color(0xFF1E222D),
      alignment: Alignment.center,
      child: SizedBox(
        width: adSize.width.toDouble(),
        height: adSize.height.toDouble(),
        child: AdWidget(key: ObjectKey(ad), ad: ad),
      ),
    );
  }
}
