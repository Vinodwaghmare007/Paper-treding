/// A large Bitcoin on-chain transaction observed via [WhaleAlertSource].
/// [observedAt] is when this app's poll first saw it (its own clock, not an
/// on-chain confirmation timestamp) — see whale_activity_tracker.dart for
/// why that distinction matters for the "in the last hour" window.
class WhaleTransaction {
  const WhaleTransaction({
    required this.txid,
    required this.valueSats,
    required this.observedAt,
  });

  final String txid;
  final int valueSats;
  final DateTime observedAt;

  double get valueBtc => valueSats / 100000000;
}
