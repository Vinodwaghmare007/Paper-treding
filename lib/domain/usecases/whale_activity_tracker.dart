import '../entities/whale_transaction.dart';

/// Turns mempool.space's rolling ~10-transaction snapshot (see
/// [WhaleAlertSource]) into an "N large transactions in the last hour"
/// count, by repeatedly ingesting fetches and keeping whatever's still
/// within [window] of the most recent [ingest] call.
///
/// This is a best-effort count, not an exhaustive one: a transaction that
/// enters and is pushed out of mempool.space's top-10 snapshot between two
/// polls is never seen at all. Honest for an educational badge; not a
/// substitute for a real historical/streaming feed.
class WhaleActivityTracker {
  WhaleActivityTracker({
    this.largeTxThresholdSats = 1000000000, // 10 BTC
    this.window = const Duration(hours: 1),
  });

  /// 10 BTC — an arbitrary but round "clearly not a retail-sized trade"
  /// cutoff, not sourced from any provider's own definition of "whale."
  final int largeTxThresholdSats;
  final Duration window;

  final Map<String, WhaleTransaction> _seen = {};

  /// Feeds newly-fetched candidates in (deduplicated by txid — a
  /// transaction seen on multiple polls is only counted once, at its
  /// first-seen time) and returns the current large-transaction count
  /// within [window] of [now].
  int ingest(List<WhaleTransaction> candidates, {DateTime? now}) {
    final reference = now ?? DateTime.now().toUtc();
    for (final tx in candidates) {
      if (tx.valueSats < largeTxThresholdSats) continue;
      _seen.putIfAbsent(tx.txid, () => tx);
    }
    _seen.removeWhere((_, tx) => reference.difference(tx.observedAt) > window);
    return _seen.length;
  }

  int get count => _seen.length;
}
