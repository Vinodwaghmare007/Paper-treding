import 'dart:convert';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

import '../entities/supported_coin.dart';

/// Remote Config parameter name — publish a JSON array of objects shaped
/// like `{"symbol":"BTCUSDT","baseAsset":"BTC","displayName":"Bitcoin",
/// "coingeckoId":"bitcoin"}` under this key in the Firebase console to add,
/// remove, or fix a coin without an app store release.
const supportedCoinsRemoteConfigKey = 'supported_coins_json';

/// Fetches [SupportedCoin] entries from Firebase Remote Config, falling
/// back to the bundled [supportedCoins] default whenever Remote Config
/// isn't configured, the fetch fails/times out (offline, Tier-2/3 network),
/// the parameter is unset, or the JSON is malformed. A coin catalog is
/// load-bearing data for every screen in the app — a Remote Config outage
/// must never blank the coin list, only prevent it from being *updated*.
class RemoteConfigCoinSource {
  RemoteConfigCoinSource({FirebaseRemoteConfig? remoteConfig})
      : _remoteConfig = remoteConfig ?? FirebaseRemoteConfig.instance;

  final FirebaseRemoteConfig _remoteConfig;
  bool _configured = false;

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    await _remoteConfig.setConfigSettings(RemoteConfigSettings(
      fetchTimeout: const Duration(seconds: 10),
      // In debug builds, fetch every time so a developer testing a new
      // coin-list publish doesn't have to wait out a production-length
      // throttle window; production uses Remote Config's own recommended
      // floor so this can't be (ab)used to hammer the fetch endpoint.
      minimumFetchInterval: kDebugMode ? Duration.zero : const Duration(hours: 1),
    ));
    await _remoteConfig.setDefaults({supportedCoinsRemoteConfigKey: ''});
    _configured = true;
  }

  /// Returns the live Remote Config coin list if one has been published and
  /// parses to at least one valid entry; otherwise returns the bundled
  /// [supportedCoins] default.
  Future<List<SupportedCoin>> fetchSupportedCoins() async {
    try {
      await _ensureConfigured();
      await _remoteConfig.fetchAndActivate();
      final raw = _remoteConfig.getString(supportedCoinsRemoteConfigKey);
      if (raw.isEmpty) return supportedCoins;
      final parsed = _parse(raw);
      return parsed.isEmpty ? supportedCoins : parsed;
    } catch (e) {
      debugPrint('[RemoteConfigCoinSource] falling back to the bundled coin list: $e');
      return supportedCoins;
    }
  }

  /// Skips a malformed individual entry rather than discarding the whole
  /// published list over one typo — returns an empty list only if nothing
  /// in [raw] parsed at all, which the caller treats as "no live list yet."
  List<SupportedCoin> _parse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];

      final coins = <SupportedCoin>[];
      for (final entry in decoded) {
        if (entry is! Map) continue;
        final symbol = entry['symbol'];
        final baseAsset = entry['baseAsset'];
        final displayName = entry['displayName'];
        final coingeckoId = entry['coingeckoId'];
        if (symbol is! String ||
            baseAsset is! String ||
            displayName is! String ||
            coingeckoId is! String) {
          continue;
        }
        coins.add(SupportedCoin(
          symbol: symbol,
          baseAsset: baseAsset,
          displayName: displayName,
          coingeckoId: coingeckoId,
        ));
      }
      return coins;
    } on FormatException catch (e) {
      debugPrint('[RemoteConfigCoinSource] malformed $supportedCoinsRemoteConfigKey: $e');
      return const [];
    }
  }
}
