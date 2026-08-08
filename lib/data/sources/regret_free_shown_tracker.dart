import 'package:shared_preferences/shared_preferences.dart';

/// On-device "which SELL orders has the Regret-Free card already been
/// shown for" set, keyed by order id — mirrors [FirstTradeTracker]'s
/// pattern. Purely local UI state (not account data), since the
/// "shown once per sell, dismissible" requirement doesn't need a
/// server-verifiable record and shouldn't cost a Firestore write per sell.
class RegretFreeShownTracker {
  static const _prefsKey = 'regret_free_shown_order_ids';

  Future<bool> hasShown(String orderId) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_prefsKey) ?? const []).contains(orderId);
  }

  Future<void> markShown(String orderId) async {
    final prefs = await SharedPreferences.getInstance();
    final shown = {...prefs.getStringList(_prefsKey) ?? const [], orderId};
    await prefs.setStringList(_prefsKey, shown.toList(growable: false));
  }
}
