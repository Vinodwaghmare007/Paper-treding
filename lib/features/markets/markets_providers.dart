import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/entities/supported_coin.dart';
import '../../data/repositories/watchlist_repository.dart';
import '../../data/sources/binance_rest_service.dart';
import '../auth/auth_providers.dart';
import '../ticker/ticker_providers.dart';

final watchlistRepositoryProvider = Provider<WatchlistRepository>((ref) {
  return WatchlistRepository(ref.watch(firebaseFirestoreProvider));
});

/// Requires a signed-in user — only meant to be watched beneath AuthGate,
/// same contract as portfolio_providers.dart's `_uidOrThrow`.
String _uidOrThrow(Ref ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) {
    throw StateError('followedSymbolsProvider read outside of AuthGate');
  }
  return uid;
}

final followedSymbolsProvider = StreamProvider<Set<String>>((ref) {
  final uid = _uidOrThrow(ref);
  return ref.watch(watchlistRepositoryProvider).watchFollowedSymbols(uid);
});

/// Every curated coin's live price + 24h change, polled every 20s in one
/// batched call — the whole point of a fixed, small curated list rather
/// than a live "top N" feed is that this stays one cheap REST call instead
/// of N.
final marketTickersProvider = StreamProvider<Map<String, TickerSnapshot>>((ref) async* {
  final rest = ref.watch(binanceRestServiceProvider);
  final symbols = [for (final c in supportedCoins) c.symbol];

  while (true) {
    final snapshots = await rest.fetch24hrTickers(symbols: symbols);
    if (snapshots.isNotEmpty) {
      yield {for (final s in snapshots) s.symbol: s};
    }
    await Future<void>.delayed(const Duration(seconds: 20));
  }
});
