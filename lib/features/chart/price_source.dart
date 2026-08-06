import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/kline_tick.dart';
import '../../data/sources/binance_websocket_service.dart';
import '../../domain/usecases/market_replay_engine.dart';
import '../ticker/ticker_providers.dart';

/// Where a [KlineTick] stream comes from: the live Binance WebSocket, or a
/// [MarketReplayEngine] stepping through cached history.
///
/// This is the seam that lets [TradeSheet], [TradingChartView], and every
/// other price-consuming widget stay identical between live trading and
/// Market Replay — they depend on whatever [PriceSource] is in scope via
/// [priceSourceProvider], never on the live WebSocket directly. Swapping
/// modes is a [ProviderScope] override at the screen boundary (see
/// `market_replay_screen.dart`), not a fork of the trading UI.
abstract class PriceSource {
  String get symbol;
  String get interval;

  /// Ticks in the same [KlineTick] shape live data already uses — replay
  /// synthesizes these from cached candles rather than parsing Binance
  /// WebSocket frames, but downstream code can't tell the difference.
  Stream<KlineTick> get ticks;
}

class LivePriceSource implements PriceSource {
  LivePriceSource(this._service);

  final BinanceWebSocketService _service;

  @override
  String get symbol => _service.symbol.toUpperCase();

  @override
  String get interval => _service.interval;

  @override
  Stream<KlineTick> get ticks => _service.ticks;
}

class ReplayPriceSource implements PriceSource {
  ReplayPriceSource(this._engine);

  final MarketReplayEngine _engine;

  @override
  String get symbol => _engine.period.symbol;

  @override
  String get interval => _engine.period.interval;

  @override
  Stream<KlineTick> get ticks => _engine.ticks;
}

/// Default: the live WebSocket. Overridden with a replay-backed
/// [PriceSource] inside Market Replay's [ProviderScope].
final priceSourceProvider = Provider<PriceSource>((ref) {
  return LivePriceSource(ref.watch(binanceWebSocketServiceProvider));
});

/// The active [PriceSource]'s tick stream, watchable like any other
/// provider — this is what price-consuming widgets (chart, trade sheet)
/// actually watch, so they never need to know whether [priceSourceProvider]
/// resolves to live or replay data.
final activeTickProvider = StreamProvider<KlineTick>((ref) {
  return ref.watch(priceSourceProvider).ticks;
});
