import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Every language this app ships a translation for — `flutter gen-l10n`
/// generates `AppLocalizations` from exactly these locales' ARB files
/// (see l10n.yaml/lib/l10n/). Kept as a single source of truth here so
/// the language picker, MaterialApp's `supportedLocales`, and the
/// device-locale-fallback resolution below can't drift out of sync.
const supportedAppLocales = [
  Locale('en'),
  Locale('hi'),
  Locale('mr'),
  Locale('ta'),
  Locale('te'),
  Locale('kn'),
];

/// Each language's own name, written in its own script — never list these
/// in English. Someone who only reads Tamil needs to recognize தமிழ் on
/// sight; they can't be expected to find "Tamil" spelled in Latin script.
const localeDisplayNames = {
  'en': 'English',
  'hi': 'हिंदी',
  'mr': 'मराठी',
  'ta': 'தமிழ்',
  'te': 'తెలుగు',
  'kn': 'ಕನ್ನಡ',
};

const _prefsKey = 'app_locale';

/// Resolution order on first read: saved preference -> device locale (if
/// it's one of [supportedAppLocales]) -> English. Only an *explicit*
/// choice (via [setLocale], from either the first-run picker or Settings)
/// is ever persisted — the device-locale fallback is applied live but not
/// written to prefs, so [hasChosenLanguage] stays false until a real
/// choice happens and the first-run picker keeps showing until then.
class LocaleNotifier extends Notifier<Locale> {
  @override
  Locale build() {
    _resolveSaved();
    // Synchronous default for the very first frame, before the async
    // SharedPreferences/device-locale resolution below completes —
    // usually resolves within a frame or two.
    return const Locale('en');
  }

  Future<void> _resolveSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    if (saved != null) {
      final match = supportedAppLocales.where((l) => l.languageCode == saved);
      if (match.isNotEmpty) {
        state = match.first;
        return;
      }
    }

    final deviceLocale = PlatformDispatcher.instance.locale;
    final deviceMatch =
        supportedAppLocales.where((l) => l.languageCode == deviceLocale.languageCode);
    state = deviceMatch.isNotEmpty ? deviceMatch.first : const Locale('en');
  }

  /// Persists an explicit choice — from the first-run picker or Settings.
  /// Changing [state] here immediately rebuilds every widget watching
  /// `AppLocalizations.of(context)` (via MaterialApp's `locale:` param
  /// watching this same provider) — no app restart needed.
  Future<void> setLocale(Locale locale) async {
    state = locale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, locale.languageCode);
  }
}

final localeProvider = NotifierProvider<LocaleNotifier, Locale>(LocaleNotifier.new);

/// True once a language has been explicitly chosen (first-run picker or
/// Settings) — false means the device-locale/English fallback is only a
/// live guess, not a real choice yet, so the first-run picker should
/// still show.
final hasChosenLanguageProvider = FutureProvider<bool>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.containsKey(_prefsKey);
});
