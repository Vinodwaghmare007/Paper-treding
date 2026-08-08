import 'package:shared_preferences/shared_preferences.dart';

/// On-device "has this install ever completed a trade" flag, purely to
/// gate the one-time `first_trade` analytics event (see
/// AnalyticsService.logFirstTrade) — not a source of truth for anything
/// account- or money-related.
class FirstTradeTracker {
  static const _prefsKey = 'has_completed_first_trade';

  Future<bool> markFirstTradeIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_prefsKey) ?? false) return false;
    await prefs.setBool(_prefsKey, true);
    return true;
  }
}
