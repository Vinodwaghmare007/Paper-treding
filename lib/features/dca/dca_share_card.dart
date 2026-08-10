import 'package:flutter/material.dart';

import '../../data/entities/supported_coin.dart';
import '../../domain/usecases/dca_simulator.dart';
import '../settings/currency_providers.dart';

/// The visual card captured for sharing (see dca_simulator_screen.dart's
/// [ScreenshotController] usage) — sized to a 9:16 aspect ratio so it fits
/// a WhatsApp/Instagram Story without letterboxing or cropping, matching
/// whatif_share_card.dart's convention.
class DcaShareCard extends StatelessWidget {
  const DcaShareCard({
    super.key,
    required this.coin,
    required this.result,
    required this.frequency,
    required this.currency,
    required this.rate,
  });

  final SupportedCoin coin;
  final DcaResult result;
  final DcaFrequency frequency;
  final AppCurrency currency;
  final ExchangeRate? rate;

  @override
  Widget build(BuildContext context) {
    final profit = result.returnPercent >= 0;
    final accentColor = profit ? const Color(0xFF26A69A) : const Color(0xFFEF5350);
    final startYear = result.series.isEmpty ? '' : result.series.first.date.year.toString();

    return AspectRatio(
      aspectRatio: 9 / 16,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF131722), Color(0xFF1E222D)],
          ),
        ),
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(Icons.savings_outlined, color: Color(0xFF26A69A), size: 40),
            const SizedBox(height: 16),
            const Text(
              'DCA SIMULATOR',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              "If I'd invested",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              '${formatCurrency(result.totalInvested / result.series.length, currency, rate)} '
              '/ ${frequency.label.toLowerCase()}',
              style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'in ${coin.baseAsset} since $startYear',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 18),
            ),
            const SizedBox(height: 32),
            Text(
              "I'd have today:",
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 14),
            ),
            const SizedBox(height: 8),
            Text(
              formatCurrency(result.currentValue, currency, rate),
              style: TextStyle(color: accentColor, fontSize: 44, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              '${profit ? '+' : ''}${result.returnPercent.toStringAsFixed(1)}%  '
              '(invested ${formatCurrency(result.totalInvested, currency, rate)})',
              textAlign: TextAlign.center,
              style: TextStyle(color: accentColor, fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            Text(
              'Simulated with historical price data on Crypto Paper Trader.\n'
              'Educational only — not financial advice.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
