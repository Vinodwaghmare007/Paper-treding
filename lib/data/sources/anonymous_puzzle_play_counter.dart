import 'package:shared_preferences/shared_preferences.dart';

/// On-device count of daily puzzles played while signed out — powers the
/// soft signup prompt after 3 plays. Never synced anywhere; a fresh
/// install (or a user who signs in) simply starts the count over, which is
/// fine since this only exists to pace a nudge, not to track identity.
class AnonymousPuzzlePlayCounter {
  static const _prefsKey = 'anonymous_puzzle_plays';

  Future<int> read() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_prefsKey) ?? 0;
  }

  Future<int> increment() async {
    final prefs = await SharedPreferences.getInstance();
    final next = (prefs.getInt(_prefsKey) ?? 0) + 1;
    await prefs.setInt(_prefsKey, next);
    return next;
  }
}
