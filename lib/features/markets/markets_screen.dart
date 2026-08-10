import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/entities/supported_coin.dart';
import '../../data/sources/coingecko_source.dart';
import '../../l10n/generated/app_localizations.dart';
import '../auth/auth_providers.dart';
import '../home/home_deep_link.dart';
import '../settings/price_text.dart';
import '../ticker/ticker_providers.dart';
import 'markets_providers.dart';

enum _SortField { change, name, price }

/// Sort state — local to this screen (not persisted, resets each visit).
final _sortFieldProvider = StateProvider.autoDispose<_SortField>((ref) => _SortField.change);
final _sortAscendingProvider = StateProvider.autoDispose<bool>((ref) => false);

/// Live price + 24h change + sparkline for every curated coin (see
/// supported_coin.dart for why this is a fixed list, not a live top-N
/// feed), with a star to follow/unfollow — followed coins stay pinned to
/// the top regardless of sort — and a tap to switch the Chart tab to that
/// coin.
class MarketsScreen extends ConsumerWidget {
  const MarketsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshotAsync = ref.watch(coinMarketSnapshotProvider);
    final marketData = ref.watch(coinMarketDataBySymbolProvider);
    final followedSymbols = ref.watch(followedSymbolsProvider);
    final sortField = ref.watch(_sortFieldProvider);
    final sortAscending = ref.watch(_sortAscendingProvider);

    int compare(SupportedCoin a, SupportedCoin b) {
      final dataA = marketData[a.symbol];
      final dataB = marketData[b.symbol];
      final result = switch (sortField) {
        _SortField.change =>
          (dataA?.priceChangePercent24h ?? 0).compareTo(dataB?.priceChangePercent24h ?? 0),
        _SortField.name => a.displayName.compareTo(b.displayName),
        _SortField.price => (dataA?.currentPriceUsd ?? 0).compareTo(dataB?.currentPriceUsd ?? 0),
      };
      return sortAscending ? result : -result;
    }

    final followed = supportedCoins.where((c) => followedSymbols.contains(c.symbol)).toList()
      ..sort(compare);
    final rest = supportedCoins.where((c) => !followedSymbols.contains(c.symbol)).toList()
      ..sort(compare);
    final coins = [...followed, ...rest];

    final isStale = snapshotAsync.valueOrNull?.isStale ?? false;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E222D),
        title: Text(l10n.marketsTitle),
      ),
      body: Column(
        children: [
          if (isStale)
            Container(
              width: double.infinity,
              color: const Color(0xFFFFC107).withValues(alpha: 0.15),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Text(
                l10n.marketsStalePrices,
                style: const TextStyle(color: Color(0xFFFFC107), fontSize: 11),
              ),
            ),
          _SortHeader(sortField: sortField, sortAscending: sortAscending),
          Expanded(
            child: snapshotAsync.hasError && snapshotAsync.valueOrNull == null
                ? Center(
                    child: Text(l10n.marketsLoadError, style: const TextStyle(color: Colors.white54)),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    itemCount: coins.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final coin = coins[index];
                      return _MarketTile(
                        coin: coin,
                        data: marketData[coin.symbol],
                        isFollowed: followedSymbols.contains(coin.symbol),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _SortHeader extends ConsumerWidget {
  const _SortHeader({required this.sortField, required this.sortAscending});

  final _SortField sortField;
  final bool sortAscending;

  void _tapField(WidgetRef ref, _SortField field) {
    if (ref.read(_sortFieldProvider) == field) {
      ref.read(_sortAscendingProvider.notifier).state = !ref.read(_sortAscendingProvider);
    } else {
      ref.read(_sortFieldProvider.notifier).state = field;
      // Gainers-first / Z-A / highest-price-first reads as the natural
      // "top of the list" default for each field.
      ref.read(_sortAscendingProvider.notifier).state = false;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          _SortChip(
            label: sortField == _SortField.change
                ? (sortAscending ? l10n.marketsSortLosers : l10n.marketsSortGainers)
                : l10n.marketsSortChange,
            selected: sortField == _SortField.change,
            onTap: () => _tapField(ref, _SortField.change),
          ),
          const SizedBox(width: 8),
          _SortChip(
            label: sortField == _SortField.name
                ? (sortAscending ? l10n.marketsSortNameAZ : l10n.marketsSortNameZA)
                : l10n.marketsSortName,
            selected: sortField == _SortField.name,
            onTap: () => _tapField(ref, _SortField.name),
          ),
          const SizedBox(width: 8),
          _SortChip(
            label: sortField == _SortField.price
                ? (sortAscending ? l10n.marketsSortPriceUp : l10n.marketsSortPriceDown)
                : l10n.marketsSortPrice,
            selected: sortField == _SortField.price,
            onTap: () => _tapField(ref, _SortField.price),
          ),
        ],
      ),
    );
  }
}

class _SortChip extends StatelessWidget {
  const _SortChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF6FD3C7).withValues(alpha: 0.15) : null,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? const Color(0xFF6FD3C7) : Colors.white24),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? const Color(0xFF6FD3C7) : Colors.white54,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _MarketTile extends ConsumerWidget {
  const _MarketTile({required this.coin, required this.data, required this.isFollowed});

  final SupportedCoin coin;
  final CoinMarketData? data;
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
    final l10n = AppLocalizations.of(context)!;
    final changePct = data?.priceChangePercent24h;
    final rising = (changePct ?? 0) >= 0;
    final changeColor = rising ? const Color(0xFF26A69A) : const Color(0xFFEF5350);

    return Card(
      color: const Color(0xFF1E222D),
      child: ListTile(
        onTap: () => _openOnChart(context, ref),
        leading: SizedBox(
          width: 56,
          height: 32,
          child: data != null && data!.sparkline7d.length > 1
              ? _Sparkline(values: data!.sparkline7d, color: changeColor)
              : null,
        ),
        title: Text(
          '${coin.baseAsset} · ${coin.displayName}',
          style: const TextStyle(color: Colors.white),
        ),
        subtitle: data == null
            ? Text(l10n.commonLoading, style: const TextStyle(color: Colors.white38, fontSize: 12))
            : PriceText(
                data!.currentPriceUsd,
                decimals: data!.currentPriceUsd >= 100 ? 2 : 4,
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
              tooltip: isFollowed ? l10n.marketsUnfollowTooltip : l10n.marketsFollowTooltip,
              onPressed: () => _toggleFollow(ref),
            ),
          ],
        ),
      ),
    );
  }
}

/// A minimal 7-day price sparkline — no axes, labels, or interactivity,
/// deliberately much lighter than the full TradingView candlestick chart
/// (fl_chart instead of the WebView bridge) since this is drawn 15+ times
/// per screen build.
class _Sparkline extends StatelessWidget {
  const _Sparkline({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final spots = [
      for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i]),
    ];
    final minY = values.reduce((a, b) => a < b ? a : b);
    final maxY = values.reduce((a, b) => a > b ? a : b);

    return LineChart(
      LineChartData(
        minY: minY,
        maxY: maxY,
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: color,
            barWidth: 1.5,
            dotData: const FlDotData(show: false),
          ),
        ],
      ),
    );
  }
}
