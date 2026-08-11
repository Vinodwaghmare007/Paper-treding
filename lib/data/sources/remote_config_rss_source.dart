import 'dart:convert';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

import '../entities/rss_source.dart';

/// Same Remote Config parameter name functions/src/news/rssSources.ts
/// reads server-side via the Admin SDK — publishing one JSON array here
/// updates the source list for both the backend's actual polling and
/// this app's (currently display-only) source registry at once.
const rssSourcesRemoteConfigKey = 'rss_sources_json';

/// Mirrors RemoteConfigCoinSource's fetch/parse/fallback design exactly —
/// see that class's doc comment for the full rationale. A Remote Config
/// outage here must fall back to [defaultRssSources], never to an empty
/// list.
class RemoteConfigRssSource {
  RemoteConfigRssSource({FirebaseRemoteConfig? remoteConfig})
      : _remoteConfig = remoteConfig ?? FirebaseRemoteConfig.instance;

  final FirebaseRemoteConfig _remoteConfig;
  bool _configured = false;

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    await _remoteConfig.setConfigSettings(RemoteConfigSettings(
      fetchTimeout: const Duration(seconds: 10),
      minimumFetchInterval: kDebugMode ? Duration.zero : const Duration(hours: 1),
    ));
    await _remoteConfig.setDefaults({rssSourcesRemoteConfigKey: ''});
    _configured = true;
  }

  Future<List<RssSourceConfig>> fetchRssSources() async {
    try {
      await _ensureConfigured();
      await _remoteConfig.fetchAndActivate();
      final raw = _remoteConfig.getString(rssSourcesRemoteConfigKey);
      if (raw.isEmpty) return defaultRssSources;
      final parsed = _parse(raw);
      return parsed.isEmpty ? defaultRssSources : parsed;
    } catch (e) {
      debugPrint('[RemoteConfigRssSource] falling back to the bundled RSS source list: $e');
      return defaultRssSources;
    }
  }

  List<RssSourceConfig> _parse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];

      final sources = <RssSourceConfig>[];
      for (final entry in decoded) {
        if (entry is! Map) continue;
        final name = entry['name'];
        final url = entry['url'];
        final category = entry['category'];
        if (name is! String || url is! String || category is! String) continue;
        sources.add(RssSourceConfig(
          name: name,
          url: url,
          category: category,
          cryptoExclusive: entry['cryptoExclusive'] == true,
        ));
      }
      return sources;
    } on FormatException catch (e) {
      debugPrint('[RemoteConfigRssSource] malformed $rssSourcesRemoteConfigKey: $e');
      return const [];
    }
  }
}
