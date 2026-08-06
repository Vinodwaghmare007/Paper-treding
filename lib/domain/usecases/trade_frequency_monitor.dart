import '../entities/order.dart';

/// Default anti-gamification threshold: more than this many trades inside
/// the trailing window is flagged, matching the product spec's ">10 in
/// 60 minutes".
const int highFrequencyTradeThreshold = 10;

const Duration highFrequencyWindow = Duration(minutes: 60);

/// Counts trades within [window] of [now]. Purely informational — unlike
/// the revenge-blocker, nothing in this app uses this count to block a
/// trade. It exists to power a non-blocking banner nudging the user that
/// high-frequency trading historically correlates with lower average
/// returns, not to enforce a limit.
int countTradesInTrailingWindow(
  List<Order> orders, {
  required DateTime now,
  Duration window = highFrequencyWindow,
}) {
  final cutoff = now.subtract(window);
  return orders.where((order) => order.timestamp.isAfter(cutoff)).length;
}
