import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Local device storage for the user's chosen chat username.
///
/// Deliberately never synced to Firestore under the user's real account —
/// the chat schema takes `display_name` as a per-message field (see
/// send_chat_message.dart), not a profile field, so there is nothing here
/// that could leak a real name: a fresh install gets an auto-generated
/// pseudonym, and any edit stays on-device.
class ChatDisplayNameStore {
  static const _prefsKey = 'chat_display_name';

  Future<String> read() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_prefsKey);
    if (existing != null) return existing;

    // First read on this device: mint a pseudonym and persist it
    // immediately so it's stable across app restarts, not re-rolled every
    // time nothing has been explicitly set yet.
    final generated = _generatePseudonym();
    await prefs.setString(_prefsKey, generated);
    return generated;
  }

  Future<void> write(String displayName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, displayName);
  }

  String _generatePseudonym() {
    final suffix = Random().nextInt(9000) + 1000;
    return 'Trader$suffix';
  }
}
