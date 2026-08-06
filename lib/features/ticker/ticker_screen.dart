import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/kline_tick.dart';
import '../../data/sources/binance_websocket_service.dart';
import '../auth/sign_out_button.dart';
import '../chart/trading_chart_view.dart';
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

    final tickAsync = ref.watch(klineTickProvider);
    final wsService = ref.watch(binanceWebSocketServiceProvider);
    final restService = ref.watch(binanceRestServiceProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E222D),
        title: const Text('BTC/USDT · 1m'),
        actions: const [
          _ConnectionBadge(),
          SizedBox(width: 12),
          SignOutButton(),
        ],
      ),
      body: Column(
        children: [
          _PriceHeader(tickAsync: tickAsync),
          Expanded(
            child: TradingChartView(
              restService: restService,
              ticks: wsService.ticks,
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
