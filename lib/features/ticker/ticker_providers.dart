import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/kline_tick.dart';
import '../../data/sources/binance_rest_service.dart';
import '../../data/sources/binance_websocket_service.dart';

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
