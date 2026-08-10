import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'currency_providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(currencyPreferenceProvider);
    final rateAsync = ref.watch(usdToInrRateProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E222D),
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: const Color(0xFF1E222D),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Display currency',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Applies to every price shown in the app — the chart, '
                    'portfolio, orders, and Markets screen. Trades are always '
                    'recorded in USD underneath; this only changes the display.',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<AppCurrency>(
                    segments: const [
                      ButtonSegment(value: AppCurrency.usd, label: Text('USD (\$)')),
                      ButtonSegment(value: AppCurrency.inr, label: Text('INR (₹)')),
                    ],
                    selected: {currency},
                    onSelectionChanged: (selection) =>
                        ref.read(currencyPreferenceProvider.notifier).setCurrency(selection.first),
                  ),
                  if (currency == AppCurrency.inr) ...[
                    const SizedBox(height: 10),
                    rateAsync.when(
                      data: (rate) => Text(
                        '1 USD ≈ ₹${rate.usdToInr.toStringAsFixed(2)}'
                        '${rate.isStale ? '  (last known rate — refresh failed)' : ''}',
                        style: TextStyle(
                          color: rate.isStale ? const Color(0xFFFFC107) : Colors.white38,
                          fontSize: 11,
                        ),
                      ),
                      loading: () => const Text(
                        'Loading exchange rate…',
                        style: TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                      error: (e, _) => const Text(
                        'Could not load an exchange rate yet — showing USD until it does.',
                        style: TextStyle(color: Color(0xFFEF5350), fontSize: 11),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
