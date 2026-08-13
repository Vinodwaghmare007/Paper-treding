import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/sources/currency_converter.dart';

// Re-exported so every screen that imports this file for AppCurrency/
// formatCurrency/etc. can also write `ExchangeRate` (e.g. as a field type)
// without a second import of data/sources/currency_converter.dart directly
// — Dart imports aren't transitive, so without this `export`, a file that
// only imports currency_providers.dart and references the ExchangeRate
// type by name fails to compile ("Type 'ExchangeRate' not found"), exactly
// as dca_simulator_screen.dart and dca_share_card.dart did before this was
// added.
export '../../data/sources/currency_converter.dart' show ExchangeRate;

/// The two display currencies this app supports. USD is the "native"
/// currency everywhere internally (Binance quotes, Firestore balances,
/// order prices are all USD) — INR is purely a display-time conversion,
/// never stored.
enum AppCurrency {
  usd('\$', 'USD'),
  inr('₹', 'INR');

  const AppCurrency(this.symbol, this.code);
  final String symbol;
  final String code;
}

const _prefsKey = 'display_currency';

/// Persists the chosen display currency across app restarts via
/// shared_preferences — loaded asynchronously on first read, so this
/// starts at [AppCurrency.usd] for one frame before the saved value (if
/// any) applies.
class CurrencyPreferenceNotifier extends Notifier<AppCurrency> {
  @override
  AppCurrency build() {
    _loadSaved();
    return AppCurrency.usd;
  }

  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    if (saved == AppCurrency.inr.name) state = AppCurrency.inr;
  }

  Future<void> setCurrency(AppCurrency currency) async {
    state = currency;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, currency.name);
  }
}

final currencyPreferenceProvider =
    NotifierProvider<CurrencyPreferenceNotifier, AppCurrency>(CurrencyPreferenceNotifier.new);

final currencyConverterProvider = Provider<CurrencyConverter>((ref) {
  final converter = CurrencyConverter();
  ref.onDispose(converter.dispose);
  return converter;
});

/// Re-polled every 15 minutes, but [CurrencyConverter] itself only makes an
/// actual HTTP call once per hour — the extra polls in between are free,
/// they just re-serve the in-memory cache — so this notices a refreshed
/// rate reasonably promptly without adding real request volume.
final usdToInrRateProvider = StreamProvider<ExchangeRate>((ref) async* {
  final converter = ref.watch(currencyConverterProvider);
  while (true) {
    try {
      yield await converter.fetchUsdToInr();
    } on CurrencyConverterException catch (e) {
      // No cached fallback exists yet (first-ever fetch failed) — nothing
      // to yield; PriceText/formatCurrency callers fall back to USD in
      // this case, see their doc comments.
      debugPrint('[CurrencyProviders] no rate available yet: $e');
    }
    await Future<void>.delayed(const Duration(minutes: 15));
  }
});

/// Converts a USD amount to [currency] using [rate] — falls back to
/// showing the raw USD amount (still correctly labeled '$') if no rate has
/// loaded yet, rather than blocking the whole screen on a forex fetch.
double convertFromUsd(double usdAmount, AppCurrency currency, ExchangeRate? rate) {
  if (currency == AppCurrency.usd || rate == null) return usdAmount;
  return usdAmount * rate.usdToInr;
}

/// `$1,234.56` / `₹1,02,345.67`-style formatting for a USD-denominated
/// amount, converted to [currency]. Indian digit grouping (lakh/crore,
/// commas after the last 3 digits then every 2) is used for INR since
/// that's the convention Indian users expect for money.
String formatCurrency(
  double usdAmount,
  AppCurrency currency,
  ExchangeRate? rate, {
  int decimals = 2,
}) {
  final converted = convertFromUsd(usdAmount, currency, rate);
  final grouped = currency == AppCurrency.inr
      ? _groupIndian(converted, decimals)
      : _groupWestern(converted, decimals);
  return '${currency.symbol}$grouped';
}

String _groupWestern(double value, int decimals) {
  final negative = value < 0;
  final fixed = value.abs().toStringAsFixed(decimals);
  final parts = fixed.split('.');
  final whole = parts[0];
  final buffer = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buffer.write(',');
    buffer.write(whole[i]);
  }
  final result = parts.length > 1 ? '${buffer.toString()}.${parts[1]}' : buffer.toString();
  return negative ? '-$result' : result;
}

/// Indian numbering: last 3 digits together, then groups of 2 —
/// e.g. 1234567.89 -> "12,34,567.89".
String _groupIndian(double value, int decimals) {
  final negative = value < 0;
  final fixed = value.abs().toStringAsFixed(decimals);
  final parts = fixed.split('.');
  final whole = parts[0];

  String result;
  if (whole.length <= 3) {
    result = whole;
  } else {
    final last3 = whole.substring(whole.length - 3);
    var rest = whole.substring(0, whole.length - 3);
    final groups = <String>[];
    while (rest.length > 2) {
      groups.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) groups.insert(0, rest);
    result = '${groups.join(',')},$last3';
  }

  final withDecimals = parts.length > 1 ? '$result.${parts[1]}' : result;
  return negative ? '-$withDecimals' : withDecimals;
}
