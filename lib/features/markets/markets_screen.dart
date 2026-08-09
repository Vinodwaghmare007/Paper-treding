import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/entities/supported_coin.dart';
import '../../data/sources/binance_rest_service.dart';
import '../auth/auth_providers.dart';
import '../home/home_deep_link.dart';
import '../ticker/ticker_providers.dart';
import 'markets_providers.dart';

/// "All" vs "Following" filter for the Markets list — local to this
/// screen, not worth persisting.
final _showFollowedOnlyProvider = StateProvider.autoDispose<bool>((ref) => false);

/// Live price + 24h change for every curated coin (see supported_coin.dart
/// for why this is a fixed list, not a live top-N feed), with a star to
/// follow/unfollow and a tap to switch the Chart tab to that coin —
/// ties the "price ticker list" and "watchlist" asks into one screen.
class MarketsScreen extends ConsumerWidget {
  const MarketsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tickers = ref.watch(marketTickersProvider).valueOrNull ?? const {};
    final followed = ref.watch(followedSymbolsProvider).valueOrNull ?? const {};
    final showFollowedOnly = ref.watch(_showFollowedOnlyProvider);

    final coins = showFollowedOnly
        ? supportedCoins.where((c) => followed.contains(c.symbol)).toList()
        : supportedCoins;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E222D),
        title: const Text('Markets'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('All'),
                  selected: !showFollowedOnly,
                  onSelected: (_) => ref.read(_showFollowedOnlyProvider.notifier).state = false,
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('★ Following'),
                  selected: showFollowedOnly,
                  onSelected: (_) => ref.read(_showFollowedOnlyProvider.notifier).state = true,
                ),
              ],
            ),
          ),
          Expanded(
            child: coins.isEmpty
                ? const Center(
                    child: Text(
                      "You're not following any coins yet — tap the star on a coin to add it.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    itemCount: coins.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final coin = coins[index];
                      return _MarketTile(
                        coin: coin,
                        snapshot: tickers[coin.symbol],
                        isFollowed: followed.contains(coin.symbol),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _MarketTile extends ConsumerWidget {
  const _MarketTile({
    required this.coin,
    required this.snapshot,
    required this.isFollowed,
  });

  final SupportedCoin coin;
  final TickerSnapshot? snapshot;
  final bool isFollowed;

  Future<void> _toggleFollow(WidgetRef ref) async {
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;
    final repo = ref.read(watchlistRepositoryProvider);
    if (isFollowed) {
      await repo.unfollow(uid, coin.symbol);
    } else {
      await repo.follow(uid, coin.symbol);
    }
  }

  void _openOnChart(BuildContext context, WidgetRef ref) {
    ref.read(selectedCoinProvider.notifier).state = coin.symbol;
    ref.read(pendingDeepLinkTabProvider.notifier).state = chartTabIndex;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final changePct = snapshot?.changePercent24h;
    final rising = (changePct ?? 0) >= 0;
    final changeColor = rising ? const Color(0xFF26A69A) : const Color(0xFFEF5350);

    return Card(
      color: const Color(0xFF1E222D),
      child: ListTile(
        onTap: () => _openOnChart(context, ref),
        title: Text(
          '${coin.baseAsset} · ${coin.displayName}',
          style: const TextStyle(color: Colors.white),
        ),
        subtitle: snapshot == null
            ? const Text('Loading…', style: TextStyle(color: Colors.white38, fontSize: 12))
            : Text(
                snapshot!.lastPrice.toStringAsFixed(snapshot!.lastPrice >= 100 ? 2 : 4),
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (changePct != null)
              Text(
                '${rising ? '+' : ''}${changePct.toStringAsFixed(2)}%',
                style: TextStyle(color: changeColor, fontWeight: FontWeight.w600, fontSize: 13),
              ),
            IconButton(
              icon: Icon(
                isFollowed ? Icons.star : Icons.star_border,
                color: isFollowed ? const Color(0xFFFFC107) : Colors.white38,
              ),
              tooltip: isFollowed ? 'Unfollow' : 'Follow',
              onPressed: () => _toggleFollow(ref),
            ),
          ],
        ),
      ),
    );
  }
}
