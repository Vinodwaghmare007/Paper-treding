import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/entities/rss_source.dart';
import '../../data/sources/remote_config_rss_source.dart';

final remoteConfigRssSourceProvider = Provider<RemoteConfigRssSource>((ref) {
  return RemoteConfigRssSource();
});

/// The RSS source list, currently only consulted for future filter-chip
/// UI (see news_feed_screen.dart) — not used to drive any network call,
/// since the app never fetches RSS itself.
final rssSourcesProvider = FutureProvider<List<RssSourceConfig>>((ref) async {
  return ref.watch(remoteConfigRssSourceProvider).fetchRssSources();
});
