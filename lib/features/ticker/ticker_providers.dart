import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/kline_tick.dart';
import '../../data/repositories/sentiment_repository.dart';
import '../../data/sources/binance_rest_service.dart';
import '../../data/sources/binance_websocket_service.dart';
import '../../domain/entities/community_sentiment.dart';
import '../auth/auth_providers.dart';

/// Owns the WebSocket service lifecycle: created lazily, started on first
/// read, disposed with the container.
final binanceWebSocketServiceProvider =
    Provider<BinanceWebSocketService>((ref) {
  final service = BinanceWebSocketService(symbol: 'btcusdt', interval: '1m');
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

/// Anonymized community sentiment for BTCUSDT, refreshed hourly by
/// functions/src/sentiment/aggregateSentiment.ts.
final communitySentimentProvider = StreamProvider<CommunitySentiment?>((ref) {
  return ref.watch(sentimentRepositoryProvider).watchSentiment('BTCUSDT');
});
