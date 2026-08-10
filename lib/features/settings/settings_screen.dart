import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/generated/app_localizations.dart';
import 'currency_providers.dart';
import 'language_picker.dart';
import 'translation_report_sheet.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final currency = ref.watch(currencyPreferenceProvider);
    final rateAsync = ref.watch(usdToInrRateProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E222D),
        title: Text(l10n.settingsTitle),
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
                  Text(
                    l10n.settingsLanguageSectionTitle,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  LanguagePickerList(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            color: const Color(0xFF1E222D),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.settingsCurrencySectionTitle,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.settingsCurrencyDescription,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<AppCurrency>(
                    segments: [
                      ButtonSegment(
                          value: AppCurrency.usd, label: Text(l10n.settingsCurrencyUsdLabel)),
                      ButtonSegment(
                          value: AppCurrency.inr, label: Text(l10n.settingsCurrencyInrLabel)),
                    ],
                    selected: {currency},
                    onSelectionChanged: (selection) =>
                        ref.read(currencyPreferenceProvider.notifier).setCurrency(selection.first),
                  ),
                  if (currency == AppCurrency.inr) ...[
                    const SizedBox(height: 10),
                    rateAsync.when(
                      data: (rate) => Text(
                        l10n.settingsExchangeRateLine(formatCurrency(1, AppCurrency.inr, rate)) +
                            (rate.isStale ? l10n.settingsExchangeRateStale : ''),
                        style: TextStyle(
                          color: rate.isStale ? const Color(0xFFFFC107) : Colors.white38,
                          fontSize: 11,
                        ),
                      ),
                      loading: () => Text(
                        l10n.settingsExchangeRateLoading,
                        style: const TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                      error: (e, _) => Text(
                        l10n.settingsExchangeRateError,
                        style: const TextStyle(color: Color(0xFFEF5350), fontSize: 11),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            color: const Color(0xFF1E222D),
            child: ListTile(
              leading: const Icon(Icons.translate, color: Colors.white54),
              title: Text(
                l10n.settingsReportTranslationIssue,
                style: const TextStyle(color: Colors.white),
              ),
              onTap: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                backgroundColor: const Color(0xFF1E222D),
                builder: (_) => const TranslationReportSheet(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
