// Covers Part A #3's "WebSocket disconnect/reconnect mid-session" edge
// case against a fake channel — no real network needed, and deterministic
// via fake_async rather than real wall-clock waits for the backoff delay.
import 'dart:async';
import 'dart:math';

import 'package:crypto_paper_trader/data/models/kline_tick.dart';
import 'package:crypto_paper_trader/data/sources/binance_websocket_service.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const _validFrame = '{"e":"kline","E":1723000000123,"s":"BTCUSDT",'
    '"k":{"t":1723000000000,"T":1723000059999,"s":"BTCUSDT","i":"1m",'
    '"f":100,"L":200,"o":"60000.10","c":"60050.55","h":"60100.00",'
    '"l":"59990.00","v":"12.345","n":100,"x":false,"q":"740000.00",'
    '"V":"6.0","Q":"360000.00","B":"0"}}';

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
  Future get done => Completer<void>().future; // never completes on its own
}

/// A controllable [WebSocketChannel] double: tests drive `controller` to
/// simulate incoming frames, stream errors, and server-initiated closes,
/// without opening a real socket.
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
  group('BinanceWebSocketService reconnect behavior', () {
    test('parses a valid frame into a tick and reports connected', () {
      fakeAsync((async) {
        final fakeChannel = FakeWebSocketChannel();
        final service = BinanceWebSocketService(
          random: Random(1),
          channelFactory: (uri) => fakeChannel,
        );
        addTearDown(service.dispose);

        KlineTick? received;
        service.ticks.listen((tick) => received = tick);
        var states = <BinanceConnectionState>[];
        service.connectionState.listen(states.add);

        service.start();
        async.flushMicrotasks();
        expect(service.currentState, BinanceConnectionState.connected);

        fakeChannel.controller.add(_validFrame);
        async.flushMicrotasks();

        expect(received, isNotNull);
        expect(received!.symbol, 'BTCUSDT');
        expect(states, contains(BinanceConnectionState.connected));
      });
    });

    test('a malformed frame is skipped without crashing or reconnecting', () {
      fakeAsync((async) {
        final fakeChannel = FakeWebSocketChannel();
        final service = BinanceWebSocketService(
          random: Random(1),
          channelFactory: (uri) => fakeChannel,
        );
        addTearDown(service.dispose);

        var tickCount = 0;
        service.ticks.listen((_) => tickCount++);

        service.start();
        async.flushMicrotasks();

        fakeChannel.controller.add('not even json');
        async.flushMicrotasks();
        expect(tickCount, 0);
        expect(service.currentState, BinanceConnectionState.connected);

        // Still alive afterwards — one bad frame doesn't kill the stream.
        fakeChannel.controller.add(_validFrame);
        async.flushMicrotasks();
        expect(tickCount, 1);
      });
    });

    test('a stream error triggers reconnect-with-backoff, and the new '
        'connection replaces the old one', () {
      fakeAsync((async) {
        final channels = <FakeWebSocketChannel>[];
        final service = BinanceWebSocketService(
          random: Random(1),
          channelFactory: (uri) {
            final channel = FakeWebSocketChannel();
            channels.add(channel);
            return channel;
          },
        );
        addTearDown(service.dispose);

        final states = <BinanceConnectionState>[];
        service.connectionState.listen(states.add);

        service.start();
        async.flushMicrotasks();
        expect(channels, hasLength(1));
        expect(service.currentState, BinanceConnectionState.connected);

        channels[0].controller.addError(Exception('connection reset'));
        async.flushMicrotasks();
        expect(service.currentState, BinanceConnectionState.reconnecting);

        // The initial backoff window is at most 1s (with full jitter);
        // 2s clears it with margin regardless of the jittered value.
        async.elapse(const Duration(seconds: 2));
        expect(channels, hasLength(2), reason: 'a second connection attempt should have fired');
        expect(service.currentState, BinanceConnectionState.connected);

        // The new channel actually carries live ticks again — this is the
        // "no stale price shown as live" guarantee in practice: once
        // reconnected, fresh ticks flow exactly as before.
        KlineTick? received;
        service.ticks.listen((tick) => received = tick);
        channels[1].controller.add(_validFrame);
        async.flushMicrotasks();
        expect(received, isNotNull);
      });
    });

    test('the server closing the connection (onDone) also triggers reconnect', () {
      fakeAsync((async) {
        final channels = <FakeWebSocketChannel>[];
        final service = BinanceWebSocketService(
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

        unawaited(channels[0].controller.close());
        async.flushMicrotasks();
        expect(service.currentState, BinanceConnectionState.reconnecting);

        async.elapse(const Duration(seconds: 2));
        expect(channels, hasLength(2));
        expect(service.currentState, BinanceConnectionState.connected);
      });
    });

    test('dispose() stops future reconnect attempts', () {
      fakeAsync((async) {
        final channels = <FakeWebSocketChannel>[];
        final service = BinanceWebSocketService(
          random: Random(1),
          channelFactory: (uri) {
            final channel = FakeWebSocketChannel();
            channels.add(channel);
            return channel;
          },
        );

        service.start();
        async.flushMicrotasks();
        expect(channels, hasLength(1));

        channels[0].controller.addError(Exception('dropped'));
        async.flushMicrotasks();
        expect(service.currentState, BinanceConnectionState.reconnecting);

        service.dispose();
        async.elapse(const Duration(seconds: 5));
        expect(channels, hasLength(1), reason: 'no reconnect should fire after dispose');
        expect(service.currentState, BinanceConnectionState.disconnected);
      });
    });
  });
}
