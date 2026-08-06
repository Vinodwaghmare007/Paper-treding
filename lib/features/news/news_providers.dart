import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/sources/crypto_news_source.dart';
import '../../domain/entities/news_headline.dart';

final cryptoNewsSourceProvider = Provider<CryptoNewsSource>((ref) {
  final source = CryptoNewsSource();
  ref.onDispose(source.dispose);
  return source;
});

/// Headlines for BTC, most recent first. Refresh by invalidating this
/// provider (e.g. pull-to-refresh) — CryptoNewsSource serves its own
/// 15-minute in-memory cache underneath, so an invalidation within that
/// window is still cheap.
final newsHeadlinesProvider = FutureProvider<List<NewsHeadline>>((ref) {
  return ref.watch(cryptoNewsSourceProvider).fetchHeadlines(currency: 'BTC');
});
