// Standalone connectivity check for the Binance kline stream.
//
// Usage (from the repo root, on a machine with open internet):
//   dart run tool/ws_smoke_test.dart
//
// Connects to wss://stream.binance.com:9443/ws/btcusdt@kline_1m, prints the
// first 10 ticks, and exits 0 on success / 1 on failure.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  const url = 'wss://stream.binance.com:9443/ws/btcusdt@kline_1m';
  stdout.writeln('Connecting to $url …');

  WebSocket socket;
  try {
    socket = await WebSocket.connect(url).timeout(const Duration(seconds: 15));
  } catch (e) {
    stderr.writeln('FAILED to connect: $e');
    exitCode = 1;
    return;
  }
  stdout.writeln('Connected. Waiting for ticks…');

  var count = 0;
  final done = Completer<void>();
  final sub = socket.listen((raw) {
    final json = jsonDecode(raw as String) as Map<String, dynamic>;
    final k = json['k'] as Map<String, dynamic>;
    count++;
    stdout.writeln(
      '#$count ${json['s']} O:${k['o']} H:${k['h']} L:${k['l']} C:${k['c']} '
      'closed:${k['x']}',
    );
    if (count >= 10 && !done.isCompleted) done.complete();
  }, onError: (Object e) {
    stderr.writeln('Stream error: $e');
    if (!done.isCompleted) done.completeError(e);
  }, onDone: () {
    if (!done.isCompleted) {
      done.completeError(StateError('Socket closed early'));
    }
  });

  try {
    await done.future.timeout(const Duration(seconds: 60));
    stdout.writeln('OK — received $count live ticks.');
  } catch (e) {
    stderr.writeln('FAILED: $e');
    exitCode = 1;
  } finally {
    await sub.cancel();
    await socket.close();
  }
}
