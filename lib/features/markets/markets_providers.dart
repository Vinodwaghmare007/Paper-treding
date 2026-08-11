import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/entities/supported_coin.dart';
import '../../data/repositories/watchlist_repository.dart';
import '../../data/sources/coingecko_source.dart';
import '../../domain/entities/watchlist_entry.dart';
import '../auth/auth_providers.dart';
import '../coins/coin_catalog_providers.dart';
import '../connectivity/connectivity_providers.dart';

final watchlistRepositoryProvider = Provider<WatchlistRepository>((ref) {
  return WatchlistRepository(ref.watch(firebaseFirestoreProvider));
});

/// Requires a signed-in user — only meant to be watched beneath AuthGate,
/// same contract as portfolio_providers.dart's `_uidOrThrow`.
String _uidOrThrow(Ref ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) {
    throw StateError('watchlist provider read outside of AuthGate');
  }
  return uid;
}

/// Ordered by the user's own drag-and-drop sort order — see
/// WatchlistRepository.reorder.
final watchlistEntriesProvider = StreamProvider<List<WatchlistEntry>>((ref) {
  final uid = _uidOrThrow(ref);
  return ref.watch(watchlistRepositoryProvider).watchWatchlist(uid);
});

/// Convenience view for widgets that only need to know *which* symbols are
/// followed (e.g. a star icon's filled/outline state), without caring
/// about order.
final followedSymbolsProvider = Provider<Set<String>>((ref) {
  final entries = ref.watch(watchlistEntriesProvider).valueOrNull ?? const [];
  return {for (final e in entries) e.symbol};
});

final coinGeckoSourceProvider = Provider<CoinGeckoSource>((ref) {
  final source = CoinGeckoSource();
  ref.onDispose(source.dispose);
  return source;
});

/// Every curated coin's live price + 24h change + 7-day sparkline, polled
/// every 45s in one batched CoinGecko call (see coingecko_source.dart for
/// why CoinGecko rather than Binance — the sparkline). Exposes the whole
/// [CoinMarketSnapshot] (not just a bare map) so the Markets screen can
/// show a "stale" indicator on a failed refresh instead of silently
/// serving old prices as current.
///
/// Scaling note (15 -> 50+ coins): this stays ONE request per 45s poll no
/// matter how many ids are joined into `ids=...` — the coin count only
/// changes that single response's size (a few KB more JSON), not the call
/// frequency, so it doesn't move the needle on CoinGecko's free-tier rate
/// limit. 50-ish ~15-char ids comma-joined is a few hundred characters,
/// nowhere near a URL length limit either. No pagination/chunking needed;
/// see coingecko_source.dart's fetchMarkets for where this is issued.
///
/// Cold-start reduction (Part B #8): on a metered connection, the very
/// first fetch requests only the top [_coldStartCoinLimit] coins — full
/// sparkline data for 50+ coins is real payload weight to force on a
/// Tier-2/3 mobile-data connection before the Markets screen has even
/// painted once. Every fetch after that first one requests the full list,
/// so the rest arrives within one 45s poll cycle rather than never.
const _coldStartCoinLimit = 15;

final coinMarketSnapshotProvider = StreamProvider<CoinMarketSnapshot>((ref) async* {
  final source = ref.watch(coinGeckoSourceProvider);
  final coins = ref.watch(supportedCoinsProvider).valueOrNull ?? supportedCoins;
  final isMetered = ref.watch(isOnMeteredConnectionProvider);
  final fullIds = [for (final c in coins) c.coingeckoId];
  final firstFetchIds = (isMetered && fullIds.length > _coldStartCoinLimit)
      ? fullIds.take(_coldStartCoinLimit).toList(growable: false)
      : fullIds;

  var isFirstFetch = true;
  while (true) {
    final ids = isFirstFetch ? firstFetchIds : fullIds;
    isFirstFetch = false;
    try {
      yield await source.fetchMarkets(coingeckoIds: ids);
    } on CoinGeckoException {
      // No cached fallback exists yet (first-ever fetch failed) — nothing
      // to yield this cycle; the Markets screen's "Loading…" state covers
      // it until a fetch succeeds.
    }
    await Future<void>.delayed(const Duration(seconds: 45));
  }
});

/// [coinMarketSnapshotProvider]'s coin list, keyed by Binance-style
/// symbol (e.g. `'BTCUSDT'`) so screens can look values up the same way
/// they already look up [SupportedCoin] entries.
final coinMarketDataBySymbolProvider = Provider<Map<String, CoinMarketData>>((ref) {
  final snapshot = ref.watch(coinMarketSnapshotProvider).valueOrNull;
  if (snapshot == null) return const {};
  final coins = ref.watch(supportedCoinsProvider).valueOrNull ?? supportedCoins;
  final byGeckoId = {for (final c in snapshot.coins) c.coingeckoId: c};
  return {
    for (final coin in coins)
      if (byGeckoId[coin.coingeckoId] != null) coin.symbol: byGeckoId[coin.coingeckoId]!,
  };
});
