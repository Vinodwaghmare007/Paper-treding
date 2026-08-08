import 'package:crypto_paper_trader/domain/entities/whale_transaction.dart';
import 'package:crypto_paper_trader/domain/usecases/whale_activity_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

WhaleTransaction _tx(String id, {required double btc, required DateTime at}) =>
    WhaleTransaction(txid: id, valueSats: (btc * 100000000).round(), observedAt: at);

void main() {
  group('WhaleActivityTracker.ingest', () {
    test('counts only transactions at or above the threshold', () {
      final tracker = WhaleActivityTracker(largeTxThresholdSats: 1000000000); // 10 BTC
      final now = DateTime.utc(2026, 1, 1, 12);

      final count = tracker.ingest([
        _tx('a', btc: 9.99, at: now),
        _tx('b', btc: 10, at: now),
        _tx('c', btc: 50, at: now),
      ], now: now);

      expect(count, 2);
    });

    test('deduplicates the same txid seen across multiple polls', () {
      final tracker = WhaleActivityTracker(largeTxThresholdSats: 1000000000);
      final now = DateTime.utc(2026, 1, 1, 12);

      tracker.ingest([_tx('a', btc: 20, at: now)], now: now);
      final count = tracker.ingest([_tx('a', btc: 20, at: now)], now: now);

      expect(count, 1);
    });

    test('drops transactions once they fall outside the window', () {
      final tracker = WhaleActivityTracker(
        largeTxThresholdSats: 1000000000,
        window: const Duration(hours: 1),
      );
      final firstSeen = DateTime.utc(2026, 1, 1, 12, 0);
      tracker.ingest([_tx('old', btc: 20, at: firstSeen)], now: firstSeen);

      final justInside = firstSeen.add(const Duration(minutes: 59));
      expect(tracker.ingest([], now: justInside), 1);

      final justOutside = firstSeen.add(const Duration(hours: 1, minutes: 1));
      expect(tracker.ingest([], now: justOutside), 0);
    });

    test('accumulates distinct large transactions across separate ingests', () {
      final tracker = WhaleActivityTracker(largeTxThresholdSats: 1000000000);
      final now = DateTime.utc(2026, 1, 1, 12);

      tracker.ingest([_tx('a', btc: 20, at: now)], now: now);
      final count = tracker.ingest(
        [_tx('b', btc: 30, at: now.add(const Duration(minutes: 5)))],
        now: now.add(const Duration(minutes: 5)),
      );

      expect(count, 2);
    });
  });
}
