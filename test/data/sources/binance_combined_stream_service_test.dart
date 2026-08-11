// Mirrors binance_websocket_service_test.dart's fake-channel approach —
// no real network needed, deterministic via fake_async for the backoff
// delay.
import 'dart:async';
import 'dart:math';

import 'package:crypto_paper_trader/data/sources/binance_combined_stream_service.dart';
import 'package:crypto_paper_trader/data/sources/binance_websocket_service.dart' show BinanceConnectionState;
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

String _miniTickerFrame(String symbol, String closePrice) =>
    '{"stream":"${symbol.toLowerCase()}@miniTicker","data":{"e":"24hrMiniTicker",'
    '"E":1723000000123,"s":"$symbol","c":"$closePrice","o":"100.00","h":"105.00",'
    '"l":"95.00","v":"1000","q":"100000"}}';

class _NoopSink implements WebSocketSink {
  @override
  void add(dynamic event) {}
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future addStream(Stream stream) async {}
  @override
  Future close([int? closeCode, String? closeReason]) async => null;
  @override
  Future get done => Completer<void>().future;
}

class FakeWebSocketChannel extends StreamChannelMixin<dynamic> implements WebSocketChannel {
  FakeWebSocketChannel({Future<void>? ready}) : ready = ready ?? Future<void>.value();

  final StreamController<dynamic> controller = StreamController<dynamic>();

  @override
  Stream<dynamic> get stream => controller.stream;

  @override
  final Future<void> ready;

  @override
  String? protocol;

  @override
  int? closeCode;

  @override
  String? closeReason;

  @override
  WebSocketSink get sink => _NoopSink();
}

void main() {
  group('BinanceCombinedStreamService', () {
    test('combines multiple symbols into one stream: url and price map', () {
      fakeAsync((async) {
        Uri? requestedUri;
        final fakeChannel = FakeWebSocketChannel();
        final service = BinanceCombinedStreamService(
          symbols: {'BTCUSDT', 'ETHUSDT'},
          random: Random(1),
          channelFactory: (uri) {
            requestedUri = uri;
            return fakeChannel;
          },
        );
        addTearDown(service.dispose);

        Map<String, double>? latest;
        service.prices.listen((prices) => latest = prices);

        service.start();
        async.flushMicrotasks();

        // One connection carrying both symbols via the combined-stream
        // query param, not two separate connections.
        expect(requestedUri.toString(), contains('streams=btcusdt@miniTicker/ethusdt@miniTicker'));
        expect(service.currentState, BinanceConnectionState.connected);

        fakeChannel.controller.add(_miniTickerFrame('BTCUSDT', '65000.50'));
        async.flushMicrotasks();
        expect(latest, {'BTCUSDT': 65000.50});

        // A second symbol's tick is additive, not a replacement — the
        // emitted map is always the full cumulative snapshot.
        fakeChannel.controller.add(_miniTickerFrame('ETHUSDT', '3200.10'));
        async.flushMicrotasks();
        expect(latest, {'BTCUSDT': 65000.50, 'ETHUSDT': 3200.10});
      });
    });

    test('a malformed frame is skipped without crashing or reconnecting', () {
      fakeAsync((async) {
        final fakeChannel = FakeWebSocketChannel();
        final service = BinanceCombinedStreamService(
          symbols: {'BTCUSDT'},
          random: Random(1),
          channelFactory: (uri) => fakeChannel,
        );
        addTearDown(service.dispose);

        var emitCount = 0;
        service.prices.listen((_) => emitCount++);

        service.start();
        async.flushMicrotasks();

        fakeChannel.controller.add('not even json');
        async.flushMicrotasks();
        expect(emitCount, 0);
        expect(service.currentState, BinanceConnectionState.connected);

        fakeChannel.controller.add(_miniTickerFrame('BTCUSDT', '65000.50'));
        async.flushMicrotasks();
        expect(emitCount, 1);
      });
    });

    test('a stream error triggers reconnect-with-backoff against a fresh connection', () {
      fakeAsync((async) {
        final channels = <FakeWebSocketChannel>[];
        final service = BinanceCombinedStreamService(
          symbols: {'BTCUSDT'},
          random: Random(1),
          channelFactory: (uri) {
            final channel = FakeWebSocketChannel();
            channels.add(channel);
            return channel;
          },
        );
        addTearDown(service.dispose);

        service.start();
        async.flushMicrotasks();
        expect(channels, hasLength(1));

        channels[0].controller.addError(Exception('connection reset'));
        async.flushMicrotasks();
        expect(service.currentState, BinanceConnectionState.reconnecting);

        async.elapse(const Duration(seconds: 2));
        expect(channels, hasLength(2));
        expect(service.currentState, BinanceConnectionState.connected);
      });
    });

    test('an empty symbol set never opens a connection', () {
      fakeAsync((async) {
        var connectCount = 0;
        final service = BinanceCombinedStreamService(
          symbols: const {},
          random: Random(1),
          channelFactory: (uri) {
            connectCount++;
            return FakeWebSocketChannel();
          },
        );
        addTearDown(service.dispose);

        service.start();
        async.flushMicrotasks();
        expect(connectCount, 0);
      });
    });
  });
}
