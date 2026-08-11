import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'binance_websocket_service.dart' show BinanceConnectionState;

/// Streams live last-traded prices for MANY symbols over a single Binance
/// WebSocket connection, using Binance's combined-stream endpoint
/// (`/stream?streams=btcusdt@miniTicker/ethusdt@miniTicker/...`) instead of
/// opening one socket per symbol — the thing to avoid at 50+ coins. Used by
/// heldCoinPricesProvider to keep every portfolio holding priced live
/// (previously a 15s REST poll; this gives sub-second updates for the same
/// one-connection cost).
///
/// `@miniTicker` (not the heavier `@ticker`) is deliberate: the only field
/// this needs is last price, and miniTicker is the smaller payload —
/// see BinanceRestService.fetchPrices, which this replaces, for the same
/// "last price only" contract.
///
/// This intentionally duplicates BinanceWebSocketService's reconnect/
/// backoff state machine rather than sharing a base class with it — that
/// class is exercised by every live chart on every screen, and refactoring
/// it to serve two different message shapes (single-symbol kline frames vs.
/// this class's multi-symbol combined-stream envelope) is a bigger, riskier
/// change than a second, smaller implementation of the same reconnect
/// policy. Same tradeoff already accepted for the Cloud Functions coin-list
/// mirrors (see functions/src/lib/supportedCoins.ts).
class BinanceCombinedStreamService {
  BinanceCombinedStreamService({
    required Set<String> symbols,
    this.baseUrl = 'wss://stream.binance.com:9443/stream',
    Random? random,
    WebSocketChannel Function(Uri uri)? channelFactory,
  })  : _symbols = symbols.map((s) => s.toLowerCase()).toSet(),
        _random = random ?? Random(),
        _channelFactory = channelFactory ?? WebSocketChannel.connect;

  final Set<String> _symbols;
  final String baseUrl;
  final Random _random;
  final WebSocketChannel Function(Uri uri) _channelFactory;

  static const _initialBackoff = Duration(seconds: 1);
  static const _maxBackoff = Duration(seconds: 60);
  static const _proactiveReconnectAfter = Duration(hours: 23);

  final _pricesController = StreamController<Map<String, double>>.broadcast();
  final _stateController = StreamController<BinanceConnectionState>.broadcast();
  final _latestPrices = <String, double>{};

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _channelSubscription;
  Timer? _reconnectTimer;
  Timer? _proactiveReconnectTimer;
  Duration _currentBackoff = _initialBackoff;
  bool _started = false;
  bool _disposed = false;
  BinanceConnectionState _state = BinanceConnectionState.disconnected;

  /// Cumulative last-known price per (uppercase) symbol — every emission is
  /// the full map so far, not a delta, so a late listener (or one that
  /// hasn't received every symbol's first tick yet) always sees a complete,
  /// consistent snapshot rather than having to merge deltas itself.
  Stream<Map<String, double>> get prices => _pricesController.stream;

  Stream<BinanceConnectionState> get connectionState => _stateController.stream;

  BinanceConnectionState get currentState => _state;

  Uri get _streamUri {
    final streams = _symbols.map((s) => '$s@miniTicker').join('/');
    return Uri.parse('$baseUrl?streams=$streams');
  }

  /// Opens the stream. Idempotent — calling twice is a no-op. A no-op (no
  /// connection ever opened) when constructed with an empty symbol set,
  /// since `streams=` with nothing after it isn't a valid subscription.
  void start() {
    if (_started || _disposed || _symbols.isEmpty) return;
    _started = true;
    _connect(isReconnect: false);
  }

  void _connect({required bool isReconnect}) {
    if (_disposed) return;
    _setState(isReconnect
        ? BinanceConnectionState.reconnecting
        : BinanceConnectionState.connecting);

    debugPrint('[BinanceCombinedWS] connecting to $_streamUri');
    final channel = _channelFactory(_streamUri);
    _channel = channel;

    _channelSubscription = channel.stream.listen(
      _onMessage,
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('[BinanceCombinedWS] stream error: $error');
        _scheduleReconnect();
      },
      onDone: () {
        debugPrint(
          '[BinanceCombinedWS] closed (code=${channel.closeCode}, '
          'reason=${channel.closeReason})',
        );
        _scheduleReconnect();
      },
      cancelOnError: true,
    );

    channel.ready.then((_) {
      if (_disposed || _channel != channel) return;
      debugPrint('[BinanceCombinedWS] connected (${_symbols.length} symbols)');
      _currentBackoff = _initialBackoff;
      _setState(BinanceConnectionState.connected);
      _armProactiveReconnect();
    }).catchError((Object error) {
      debugPrint('[BinanceCombinedWS] connect failed: $error');
    });
  }

  void _onMessage(dynamic raw) {
    if (raw is! String) return;
    try {
      final envelope = jsonDecode(raw);
      if (envelope is! Map<String, dynamic>) return;
      final data = envelope['data'];
      if (data is! Map<String, dynamic>) return;
      final symbol = data['s'] as String?;
      final closePriceStr = data['c'] as String?;
      if (symbol == null || closePriceStr == null) return;
      final price = double.tryParse(closePriceStr);
      if (price == null) return;

      _latestPrices[symbol] = price;
      if (!_pricesController.isClosed) {
        _pricesController.add(Map.unmodifiable(_latestPrices));
      }
    } catch (e) {
      // Non-ticker control payloads (subscribe/unsubscribe acks) or schema
      // drift: skip, keep streaming — one bad frame must not kill the feed.
      debugPrint('[BinanceCombinedWS] skipped unparseable frame: $e');
    }
  }

  void _armProactiveReconnect() {
    _proactiveReconnectTimer?.cancel();
    _proactiveReconnectTimer = Timer(_proactiveReconnectAfter, () {
      debugPrint('[BinanceCombinedWS] 23h proactive reconnect');
      _teardownChannel();
      _connect(isReconnect: true);
    });
  }

  void _scheduleReconnect() {
    if (_disposed || _reconnectTimer != null) return;
    _teardownChannel();
    _setState(BinanceConnectionState.reconnecting);

    final delayMs = _random.nextInt(_currentBackoff.inMilliseconds + 1);
    final delay = Duration(milliseconds: delayMs);
    debugPrint(
      '[BinanceCombinedWS] reconnecting in ${delay.inMilliseconds}ms '
      '(window=${_currentBackoff.inSeconds}s)',
    );
    _currentBackoff = _currentBackoff * 2 > _maxBackoff ? _maxBackoff : _currentBackoff * 2;

    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      _connect(isReconnect: true);
    });
  }

  void _teardownChannel() {
    _proactiveReconnectTimer?.cancel();
    _proactiveReconnectTimer = null;
    _channelSubscription?.cancel();
    _channelSubscription = null;
    _channel?.sink.close();
    _channel = null;
  }

  void _setState(BinanceConnectionState state) {
    if (_state == state) return;
    _state = state;
    if (!_stateController.isClosed) _stateController.add(state);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _reconnectTimer?.cancel();
    _teardownChannel();
    _setState(BinanceConnectionState.disconnected);
    await _pricesController.close();
    await _stateController.close();
  }
}
