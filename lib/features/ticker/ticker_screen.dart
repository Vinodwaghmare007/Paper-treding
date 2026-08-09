import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/entities/supported_coin.dart';
import '../../data/models/kline_tick.dart';
import '../../data/sources/binance_websocket_service.dart';
import '../../data/models/forecast.dart';
import '../../data/sources/forecast_api_source.dart';
import '../chart/forecast_providers.dart';
import '../chart/trading_chart_view.dart';
import '../chart/whale_badge.dart';
import '../home/more_menu_button.dart';
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
    final tickAsync = ref.watch(klineTickProvider);
    final wsService = ref.watch(binanceWebSocketServiceProvider);
    final restService = ref.watch(binanceRestServiceProvider);
    final forecastAsync = ref.watch(forecastControllerProvider);

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
          const HighFrequencyBanner(),
          _PriceHeader(tickAsync: tickAsync),
          const _SentimentBadge(),
          // Whale Shadow Mode reads on-chain Bitcoin mempool data — it has
          // no meaning for any other coin, so it only shows while BTC is
          // the active chart symbol rather than mislabeling another coin's
          // screen with Bitcoin whale activity.
          if (selectedSymbol == 'BTCUSDT') const WhaleBadge(),
          Expanded(
            child: Stack(
              children: [
                TradingChartView(
                  // Re-keys the chart's State on coin switch so it re-seeds
                  // from scratch instead of showing the new symbol's ticks
                  // layered onto the old symbol's candles.
                  key: ValueKey(selectedSymbol),
                  fetchSeedCandles: () => restService.fetchKlines(
                    symbol: selectedSymbol,
                    interval: '1m',
                    limit: 500,
                  ),
                  ticks: wsService.ticks,
                  forecast: forecastAsync.valueOrNull,
                ),
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
        data: (tick) => FloatingActionButton.extended(
          onPressed: () => showTradeSheet(
            context,
            coinSymbol: tick.symbol,
            currentPrice: tick.candle.close,
          ),
          icon: const Icon(Icons.swap_vert),
          label: const Text('Trade'),
        ),
        orElse: () => null,
      ),
    );
  }
}

class _PriceHeader extends StatelessWidget {
  const _PriceHeader({required this.tickAsync});

  final AsyncValue<KlineTick> tickAsync;

  @override
  Widget build(BuildContext context) {
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
              Text(
                c.close.toStringAsFixed(2),
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
                child: Text(
                  'O ${c.open.toStringAsFixed(2)}  '
                  'H ${c.high.toStringAsFixed(2)}  '
                  'L ${c.low.toStringAsFixed(2)}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
            ],
          );
        },
        error: (e, _) => Text(
          'Live feed error: $e',
          style: const TextStyle(color: Color(0xFFEF5350)),
        ),
        loading: () => const Text(
          'Waiting for first tick…',
          style: TextStyle(color: Colors.white54),
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
              const Text('Show AI Forecast', style: TextStyle(color: Colors.white, fontSize: 13)),
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
    final state = ref.watch(connectionStateProvider).valueOrNull ??
        BinanceConnectionState.connecting;
    final (color, label) = switch (state) {
      BinanceConnectionState.connected => (const Color(0xFF26A69A), 'LIVE'),
      BinanceConnectionState.connecting => (Colors.amber, 'CONNECTING'),
      BinanceConnectionState.reconnecting => (Colors.amber, 'RECONNECTING'),
      BinanceConnectionState.disconnected => (const Color(0xFFEF5350), 'OFFLINE'),
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
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                'Switch coin',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            for (final coin in supportedCoins)
              ListTile(
                leading: Icon(
                  coin.symbol == selectedSymbol
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: coin.symbol == selectedSymbol
                      ? const Color(0xFF6FD3C7)
                      : Colors.white38,
                ),
                title: Text('${coin.baseAsset} · ${coin.displayName}'),
                onTap: () {
                  ref.read(selectedCoinProvider.notifier).state = coin.symbol;
                  Navigator.of(sheetContext).pop();
                },
              ),
          ],
        ),
      ),
    );
  }
}
