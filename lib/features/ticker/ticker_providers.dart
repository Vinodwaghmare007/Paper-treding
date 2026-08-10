import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/entities/chart_range.dart';
import '../../data/models/kline_tick.dart';
import '../../data/repositories/sentiment_repository.dart';
import '../../data/sources/binance_rest_service.dart';
import '../../data/sources/binance_websocket_service.dart';
import '../../domain/entities/community_sentiment.dart';
import '../auth/auth_providers.dart';

/// The coin currently open on the chart/trade screen — defaults to the
/// original single-coin symbol so existing behaviour is unchanged until
/// someone actually uses the coin picker. Everything downstream (the
/// WebSocket tick stream, sentiment badge, AI forecast) rebuilds off this
/// one source of truth when it changes.
final selectedCoinProvider = StateProvider<String>((ref) => 'BTCUSDT');

/// The chart's active time range — drives both the seed-candle REST
/// fetch's interval/limit and the live WebSocket subscription's interval
/// (they have to match, or a live tick's candle bucket won't line up with
/// the seeded history's bucket size). Defaults to 1D, closest to the
/// original fixed "500 x 1-minute candles" behaviour.
final selectedChartRangeProvider = StateProvider<ChartRange>((ref) => ChartRange.day1);

/// Owns the WebSocket service lifecycle: rebuilt (old socket torn down via
/// `ref.onDispose`, new one opened) whenever [selectedCoinProvider] or
/// [selectedChartRangeProvider] changes, since [BinanceWebSocketService]'s
/// symbol/interval are fixed at construction.
final binanceWebSocketServiceProvider =
    Provider<BinanceWebSocketService>((ref) {
  final symbol = ref.watch(selectedCoinProvider).toLowerCase();
  final interval = ref.watch(selectedChartRangeProvider).klineInterval;
  final service = BinanceWebSocketService(symbol: symbol, interval: interval);
  service.start();
  ref.onDispose(service.dispose);
  return service;
});

final binanceRestServiceProvider = Provider<BinanceRestService>((ref) {
  final service = BinanceRestService();
  ref.onDispose(service.dispose);
  return service;
});

/// Live kline ticks (every ~250ms–2s from Binance while the market moves).
final klineTickProvider = StreamProvider<KlineTick>((ref) {
  return ref.watch(binanceWebSocketServiceProvider).ticks;
});

/// Connection status for the UI indicator.
final connectionStateProvider = StreamProvider<BinanceConnectionState>((ref) {
  final service = ref.watch(binanceWebSocketServiceProvider);
  return service.connectionState;
});

final sentimentRepositoryProvider = Provider<SentimentRepository>((ref) {
  return SentimentRepository(ref.watch(firebaseFirestoreProvider));
});

/// Anonymized community sentiment for the selected coin, refreshed hourly
/// by functions/src/sentiment/aggregateSentiment.ts — that function only
/// tracks a fixed symbol list of its own, so this can come back empty for
/// a symbol it doesn't cover yet; the badge already renders nothing rather
/// than a misleading placeholder in that case.
final communitySentimentProvider = StreamProvider<CommunitySentiment?>((ref) {
  final symbol = ref.watch(selectedCoinProvider);
  return ref.watch(sentimentRepositoryProvider).watchSentiment(symbol);
});
