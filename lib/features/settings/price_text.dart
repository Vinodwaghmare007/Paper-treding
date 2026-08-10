import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'currency_providers.dart';

/// Drop-in replacement for `Text(usdAmount.toStringAsFixed(2))` that
/// respects [currencyPreferenceProvider] — every screen showing a price
/// should use this instead of formatting a raw USD double directly, so the
/// USD/INR toggle in Settings actually applies app-wide rather than to
/// whichever screens happened to be updated.
class PriceText extends ConsumerWidget {
  const PriceText(
    this.usdAmount, {
    super.key,
    this.style,
    this.decimals = 2,
    this.prefix = '',
    this.suffix = '',
  });

  final double usdAmount;
  final TextStyle? style;
  final int decimals;
  final String prefix;
  final String suffix;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(currencyPreferenceProvider);
    final rate = ref.watch(usdToInrRateProvider).valueOrNull;
    final formatted = formatCurrency(usdAmount, currency, rate, decimals: decimals);
    return Text('$prefix$formatted$suffix', style: style);
  }
}
