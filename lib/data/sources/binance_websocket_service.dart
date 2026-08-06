import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/kline_tick.dart';

/// Connection lifecycle states exposed to the UI.
enum BinanceConnectionState { connecting, connected, reconnecting, disconnected }

/// Streams live kline ticks from the Binance spot WebSocket API.
///
/// Reliability behaviour:
/// * Reconnects on any error or unexpected close with exponential backoff
///   (1s base, doubling to a 60s cap) plus full jitter, so a fleet of clients
///   does not thunder-herd Binance after an outage.
/// * Binance force-closes connections after 24h; a proactive reconnect fires
///   at 23h so the drop happens on our schedule, not theirs.
/// * Malformed frames are logged and skipped — one bad payload must not kill
///   the stream.
class BinanceWebSocketService {
  BinanceWebSocketService({
    this.symbol = 'btcusdt',
    this.interval = '1m',
    this.baseUrl = 'wss://stream.binance.com:9443/ws',
    Random? random,
  }) : _random = random ?? Random();

  final String symbol;
  final String interval;
  final String baseUrl;
  final Random _random;

  static const _initialBackoff = Duration(seconds: 1);
  static const _maxBackoff = Duration(seconds: 60);
  static const _proactiveReconnectAfter = Duration(hours: 23);

  final _tickController = StreamController<KlineTick>.broadcast();
  final _stateController = StreamController<BinanceConnectionState>.broadcast();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _channelSubscription;
  Timer? _reconnectTimer;
  Timer? _proactiveReconnectTimer;
  Duration _currentBackoff = _initialBackoff;
  bool _started = false;
  bool _disposed = false;
  BinanceConnectionState _state = BinanceConnectionState.disconnected;

  /// Live parsed ticks. Broadcast: safe to listen from several places.
  Stream<KlineTick> get ticks => _tickController.stream;

  /// Connection state changes, for status indicators in the UI.
  Stream<BinanceConnectionState> get connectionState =>
      _stateController.stream;

  BinanceConnectionState get currentState => _state;

  Uri get _streamUri => Uri.parse('$baseUrl/$symbol@kline_$interval');

  /// Opens the stream. Idempotent — calling twice is a no-op.
  void start() {
    if (_started || _disposed) return;
    _started = true;
    _connect(isReconnect: false);
  }

  void _connect({required bool isReconnect}) {
    if (_disposed) return;
    _setState(isReconnect
        ? BinanceConnectionState.reconnecting
        : BinanceConnectionState.connecting);

    debugPrint('[BinanceWS] connecting to $_streamUri');
    final channel = WebSocketChannel.connect(_streamUri);
    _channel = channel;

    _channelSubscription = channel.stream.listen(
      _onMessage,
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('[BinanceWS] stream error: $error');
        _scheduleReconnect();
      },
      onDone: () {
        debugPrint(
          '[BinanceWS] closed (code=${channel.closeCode}, '
          'reason=${channel.closeReason})',
        );
        _scheduleReconnect();
      },
      cancelOnError: true,
    );

    // WebSocketChannel.connect reports connection failures through the stream,
    // so `ready` failures are also routed into the reconnect path.
    channel.ready.then((_) {
      if (_disposed || _channel != channel) return;
      debugPrint('[BinanceWS] connected');
      _currentBackoff = _initialBackoff;
      _setState(BinanceConnectionState.connected);
      _armProactiveReconnect();
    }).catchError((Object error) {
      debugPrint('[BinanceWS] connect failed: $error');
      // The stream's onError/onDone handles scheduling; nothing else to do.
    });
  }

  void _onMessage(dynamic raw) {
    if (raw is! String) return;
    try {
      final tick = KlineTick.fromRawMessage(raw);
      if (!_tickController.isClosed) _tickController.add(tick);
    } on FormatException catch (e) {
      // Non-kline control payloads or schema drift: skip, keep streaming.
      debugPrint('[BinanceWS] skipped unparseable frame: $e');
    }
  }

  void _armProactiveReconnect() {
    _proactiveReconnectTimer?.cancel();
    _proactiveReconnectTimer = Timer(_proactiveReconnectAfter, () {
      debugPrint('[BinanceWS] 23h proactive reconnect');
      _teardownChannel();
      _connect(isReconnect: true);
    });
  }

  void _scheduleReconnect() {
    if (_disposed || _reconnectTimer != null) return;
    _teardownChannel();
    _setState(BinanceConnectionState.reconnecting);

    // Full jitter: wait a uniformly random slice of the current backoff
    // window, then double the window up to the cap.
    final delayMs = _random.nextInt(_currentBackoff.inMilliseconds + 1);
    final delay = Duration(milliseconds: delayMs);
    debugPrint(
      '[BinanceWS] reconnecting in ${delay.inMilliseconds}ms '
      '(window=${_currentBackoff.inSeconds}s)',
    );
    _currentBackoff = _currentBackoff * 2 > _maxBackoff
        ? _maxBackoff
        : _currentBackoff * 2;

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
    await _tickController.close();
    await _stateController.close();
  }
}
