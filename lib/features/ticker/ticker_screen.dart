import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/entities/chart_range.dart';
import '../../data/entities/supported_coin.dart';
import '../../data/models/kline_tick.dart';
import '../../data/sources/binance_websocket_service.dart';
import '../../data/models/forecast.dart';
import '../../data/sources/forecast_api_source.dart';
import '../../l10n/generated/app_localizations.dart';
import '../chart/forecast_providers.dart';
import '../chart/trading_chart_view.dart';
import '../chart/whale_badge.dart';
import '../coins/coin_catalog_providers.dart';
import '../connectivity/connectivity_providers.dart';
import '../connectivity/offline_banner.dart';
import '../home/more_menu_button.dart';
import '../settings/price_text.dart';
import '../trade/high_frequency_banner.dart';
import '../trade/trade_sheet.dart';
import 'ticker_providers.dart';

class TickerScreen extends ConsumerWidget {
  const TickerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Console print of every tick, closed candles flagged — required Phase 1
    // diagnostic output, kept as-is in Phase 2.
    ref.listen<AsyncValue<KlineTick>>(klineTickProvider, (_, next) {
      final tick = next.valueOrNull;
      if (tick != null) {
        debugPrint(
          '[Tick] ${tick.symbol} ${tick.interval} '
          'O:${tick.candle.open} H:${tick.candle.high} '
          'L:${tick.candle.low} C:${tick.candle.close} '
          'V:${tick.candle.volume}'
          '${tick.isCandleClosed ? '  << CANDLE CLOSED' : ''}',
        );
      }
    });

    final selectedSymbol = ref.watch(selectedCoinProvider);
    final selectedRange = ref.watch(selectedChartRangeProvider);
    final tickAsync = ref.watch(klineTickProvider);
    final wsService = ref.watch(binanceWebSocketServiceProvider);
    final restService = ref.watch(binanceRestServiceProvider);
    final appDatabase = ref.watch(appDatabaseProvider);
    final forecastAsync = ref.watch(forecastControllerProvider);
    final isOnline = ref.watch(isOnlineProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E222D),
        title: const _CoinPickerTitle(),
        actions: const [
          _ConnectionBadge(),
          SizedBox(width: 12),
          MoreMenuButton(),
        ],
      ),
      body: Column(
        children: [
          if (!isOnline)
            OfflineBanner(asOf: ref.watch(cachedSeedCandlesProvider).valueOrNull?.fetchedAt),
          const HighFrequencyBanner(),
          _PriceHeader(tickAsync: tickAsync),
          const _SentimentBadge(),
          // Whale Shadow Mode reads on-chain Bitcoin mempool data — it has
          // no meaning for any other coin, so it only shows while BTC is
          // the active chart symbol rather than mislabeling another coin's
          // screen with Bitcoin whale activity.
          if (selectedSymbol == 'BTCUSDT') const WhaleBadge(),
          const _ChartRangeSelector(),
          Expanded(
            child: Stack(
              children: [
                TradingChartView(
                  // Re-keys the chart's State on coin OR range switch so it
                  // re-seeds from scratch instead of showing the new
                  // symbol/interval's ticks layered onto old candles.
                  key: ValueKey('$selectedSymbol-${selectedRange.name}'),
                  fetchSeedCandles: () => fetchSeedCandlesWithCache(
                    restService: restService,
                    appDatabase: appDatabase,
                    symbol: selectedSymbol,
                    interval: selectedRange.klineInterval,
                    limit: selectedRange.candleLimit,
                  ),
                  ticks: wsService.ticks,
                  interval: selectedRange.klineInterval,
                  // The AI forecast is always a fixed near-term (next ~15
                  // minutes) projection regardless of chart zoom — showing
                  // it on a zoomed-out 1W-5Y chart would be either
                  // invisible or, worse, misplaced, so it's suppressed
                  // outside the 1D range regardless of the toggle's state.
                  forecast: selectedRange == ChartRange.day1 ? forecastAsync.valueOrNull : null,
                ),
                if (selectedRange == ChartRange.day1)
                  Positioned(
                    top: 8,
                    left: 8,
                    right: 8,
                    child: _ForecastToggle(forecastAsync: forecastAsync),
                  ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: tickAsync.maybeWhen(
        data: (tick) => _BuySellFabs(symbol: tick.symbol, currentPrice: tick.candle.close),
        orElse: () => null,
      ),
    );
  }
}

/// Separate green Buy / red Sell buttons, replacing what used to be a
/// single neutral "Trade" FAB — color-coded intent recognition is the
/// convention every real trading app (Zerodha, Groww, Binance) already
/// uses, and it saves the one extra tap of picking a side inside the
/// sheet first. Compact `FloatingActionButton.extended` pair rather than
/// two full-width buttons, since this bottom-right corner already
/// competes with the SIMULATED footer and the 4-tab bottom nav for
/// space. Each still opens the same [TradeSheet] — the segmented control
/// in there is untouched, just pre-selected to whichever side was
/// tapped, so switching sides mid-sheet still works exactly as before.
class _BuySellFabs extends StatelessWidget {
  const _BuySellFabs({required this.symbol, required this.currentPrice});

  final String symbol;
  final double currentPrice;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton.extended(
          heroTag: 'fab-sell',
          backgroundColor: const Color(0xFFEF5350),
          onPressed: () => showTradeSheet(
            context,
            coinSymbol: symbol,
            currentPrice: currentPrice,
            initialSide: TradeSide.sell,
          ),
          icon: const Icon(Icons.arrow_downward),
          label: Text(l10n.tradeSheetSell),
        ),
        const SizedBox(width: 12),
        FloatingActionButton.extended(
          heroTag: 'fab-buy',
          backgroundColor: const Color(0xFF26A69A),
          onPressed: () => showTradeSheet(
            context,
            coinSymbol: symbol,
            currentPrice: currentPrice,
            initialSide: TradeSide.buy,
          ),
          icon: const Icon(Icons.arrow_upward),
          label: Text(l10n.tradeSheetBuy),
        ),
      ],
    );
  }
}

class _PriceHeader extends StatelessWidget {
  const _PriceHeader({required this.tickAsync});

  final AsyncValue<KlineTick> tickAsync;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      width: double.infinity,
      color: const Color(0xFF1E222D),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: tickAsync.when(
        data: (tick) {
          final c = tick.candle;
          final rising = c.close >= c.open;
          final color = rising ? const Color(0xFF26A69A) : const Color(0xFFEF5350);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              PriceText(
                c.close,
                style: TextStyle(
                  color: color,
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${l10n.tickerOpenLabel} ',
                        style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    PriceText(c.open, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    Text('  ${l10n.tickerHighLabel} ',
                        style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    PriceText(c.high, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    Text('  ${l10n.tickerLowLabel} ',
                        style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    PriceText(c.low, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  ],
                ),
              ),
            ],
          );
        },
        error: (e, _) => Text(
          l10n.tickerLiveFeedError(e.toString()),
          style: const TextStyle(color: Color(0xFFEF5350)),
        ),
        loading: () => Text(
          l10n.tickerWaitingForFirstTick,
          style: const TextStyle(color: Colors.white54),
        ),
      ),
    );
  }
}

/// "X% of the community is bullish on BTC this hour" — anonymized,
/// aggregate-only sentiment from functions/src/sentiment/aggregateSentiment
/// .ts. Renders nothing while there isn't yet a meaningful aggregate to
/// show (no doc written yet, or zero orders in the trailing hour) rather
/// than a misleading "50/50" placeholder.
class _SentimentBadge extends ConsumerWidget {
  const _SentimentBadge();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sentiment = ref.watch(communitySentimentProvider).valueOrNull;
    if (sentiment == null || !sentiment.hasEnoughData) {
      return const SizedBox.shrink();
    }

    final bullish = sentiment.bullishPct!;
    final isBullish = bullish >= 50;
    final color = isBullish ? const Color(0xFF26A69A) : const Color(0xFFEF5350);
    final pct = (isBullish ? bullish : sentiment.bearishPct!).toStringAsFixed(0);

    return Container(
      width: double.infinity,
      color: const Color(0xFF1E222D),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                isBullish ? Icons.trending_up : Icons.trending_down,
                color: color,
                size: 14,
              ),
              const SizedBox(width: 6),
              Text(
                '$pct% of the community is ${isBullish ? 'bullish' : 'bearish'} '
                'on ${sentiment.symbol} this hour',
                style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const Text(
            'Reflects paper-trading orders on this app, not professional market sentiment.',
            style: TextStyle(color: Colors.white38, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _ForecastToggle extends ConsumerWidget {
  const _ForecastToggle({required this.forecastAsync});

  final AsyncValue<PriceForecast?> forecastAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(showAiForecastProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFF1E222D).withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.auto_graph, color: Color(0xFFFFC107), size: 16),
              const SizedBox(width: 6),
              Text(AppLocalizations.of(context)!.forecastToggleLabel,
                  style: const TextStyle(color: Colors.white, fontSize: 13)),
              Switch(
                value: enabled,
                onChanged: (value) =>
                    ref.read(showAiForecastProvider.notifier).state = value,
                activeColor: const Color(0xFFFFC107),
              ),
              if (enabled && forecastAsync.isLoading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
        ),
        if (enabled && forecastAsync.hasError)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFEF5350).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                forecastAsync.error is ForecastApiException
                    ? (forecastAsync.error as ForecastApiException).message
                    : 'Forecast unavailable: ${forecastAsync.error}',
                style: const TextStyle(color: Color(0xFFEF5350), fontSize: 11),
              ),
            ),
          ),
        if (enabled && forecastAsync.valueOrNull != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(
              forecastAsync.valueOrNull!.disclaimer,
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
          ),
      ],
    );
  }
}

class _ConnectionBadge extends ConsumerWidget {
  const _ConnectionBadge();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(connectionStateProvider).valueOrNull ??
        BinanceConnectionState.connecting;
    final (color, label) = switch (state) {
      BinanceConnectionState.connected => (const Color(0xFF26A69A), l10n.connectionLive),
      BinanceConnectionState.connecting => (Colors.amber, l10n.connectionConnecting),
      BinanceConnectionState.reconnecting => (Colors.amber, l10n.connectionReconnecting),
      BinanceConnectionState.disconnected => (const Color(0xFFEF5350), l10n.connectionOffline),
    };
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, size: 8, color: color),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: color, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

/// Row of range chips (1D/1W/30D/90D/1Y/5Y) — switching range re-seeds the
/// chart at a coarser/finer kline interval (see chart_range.dart) rather
/// than fetching literal years of 1-minute candles.
class _ChartRangeSelector extends ConsumerWidget {
  const _ChartRangeSelector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedChartRangeProvider);

    return Container(
      width: double.infinity,
      color: const Color(0xFF1E222D),
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (final range in ChartRange.values)
            _RangeChip(
              range: range,
              isSelected: range == selected,
              onTap: () => ref.read(selectedChartRangeProvider.notifier).state = range,
            ),
        ],
      ),
    );
  }
}

class _RangeChip extends StatelessWidget {
  const _RangeChip({required this.range, required this.isSelected, required this.onTap});

  final ChartRange range;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF6FD3C7).withValues(alpha: 0.15) : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          range.label,
          style: TextStyle(
            color: isSelected ? const Color(0xFF6FD3C7) : Colors.white54,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

/// AppBar title doubling as the coin switcher — tap to pick any of the
/// curated [supportedCoins] instead of leaving the chart pinned to BTC.
class _CoinPickerTitle extends ConsumerWidget {
  const _CoinPickerTitle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedSymbol = ref.watch(selectedCoinProvider);
    final coin = coinForSymbol(selectedSymbol);

    return InkWell(
      onTap: () => _openPicker(context, ref, selectedSymbol),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${coin.baseAsset}/USDT · 1m'),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down, size: 20),
          ],
        ),
      ),
    );
  }

  void _openPicker(BuildContext context, WidgetRef ref, String selectedSymbol) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E222D),
      isScrollControlled: true,
      builder: (sheetContext) => _CoinPickerSheet(selectedSymbol: selectedSymbol),
    );
  }
}

/// The coin-picker bottom sheet's own widget (rather than an inline
/// `builder:` closure) so it can hold local search-query state — with
/// [supportedCoins] now 50+ entries (see coin_catalog_providers.dart), an
/// unfiltered list is a lot of scrolling to find one coin.
class _CoinPickerSheet extends ConsumerStatefulWidget {
  const _CoinPickerSheet({required this.selectedSymbol});

  final String selectedSymbol;

  @override
  ConsumerState<_CoinPickerSheet> createState() => _CoinPickerSheetState();
}

class _CoinPickerSheetState extends ConsumerState<_CoinPickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final coins = ref.watch(supportedCoinsProvider).valueOrNull ?? supportedCoins;
    final query = _query.trim().toLowerCase();
    final filtered = query.isEmpty
        ? coins
        : coins
            .where((c) =>
                c.baseAsset.toLowerCase().contains(query) ||
                c.displayName.toLowerCase().contains(query))
            .toList(growable: false);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              l10n.coinPickerTitle,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: l10n.coinSearchHint,
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search, color: Colors.white38),
                isDense: true,
                filled: true,
                fillColor: const Color(0xFF131722),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Flexible(
            child: filtered.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(l10n.coinSearchNoResults,
                        style: const TextStyle(color: Colors.white38)),
                  )
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final coin in filtered)
                        ListTile(
                          leading: Icon(
                            coin.symbol == widget.selectedSymbol
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            color: coin.symbol == widget.selectedSymbol
                                ? const Color(0xFF6FD3C7)
                                : Colors.white38,
                          ),
                          title: Text('${coin.baseAsset} · ${coin.displayName}'),
                          onTap: () {
                            ref.read(selectedCoinProvider.notifier).state = coin.symbol;
                            Navigator.of(context).pop();
                          },
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
