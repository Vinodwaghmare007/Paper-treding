import 'package:flutter/material.dart';

import '../../domain/usecases/whatif_generator.dart';

/// The visual card captured for sharing (see whatif_screen.dart's
/// [ScreenshotController] usage) — sized to a 9:16 aspect ratio so it fits
/// a WhatsApp/Instagram Story without letterboxing or cropping.
class WhatIfShareCard extends StatelessWidget {
  const WhatIfShareCard({super.key, required this.result});

  final WhatIfResult result;

  @override
  Widget build(BuildContext context) {
    final profit = result.profitLoss >= 0;
    final accentColor = profit ? const Color(0xFF26A69A) : const Color(0xFFEF5350);
    final date = result.historicalDate;
    final dateLabel =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

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
            const Icon(Icons.history_toggle_off, color: Color(0xFF26A69A), size: 40),
            const SizedBox(height: 16),
            const Text(
              'WHAT-IF TIME MACHINE',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              "If you'd put",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              '\$${result.hypotheticalAmount.toStringAsFixed(0)}',
              style: const TextStyle(
                  color: Colors.white, fontSize: 40, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'into ${result.symbol} on $dateLabel',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 18),
            ),
            const SizedBox(height: 32),
            Text(
              "it'd be worth today:",
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 14),
            ),
            const SizedBox(height: 8),
            Text(
              '\$${result.currentValue.toStringAsFixed(2)}',
              style: TextStyle(color: accentColor, fontSize: 48, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              '${profit ? '+' : ''}\$${result.profitLoss.toStringAsFixed(2)} '
              '(${result.growthMultiple.toStringAsFixed(2)}x)',
              style: TextStyle(color: accentColor, fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            Text(
              'Simulated with paper-trading data on Crypto Paper Trader.\n'
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
