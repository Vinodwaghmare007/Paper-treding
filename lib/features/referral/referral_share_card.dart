import 'package:flutter/material.dart';

/// The visual card captured for sharing — same 9:16 Story-sized layout as
/// WhatIfShareCard, deliberately kept modest about what the referral code
/// actually does today: it earns tracked bonus days (pro_days_earned),
/// not access to any feature that exists yet (see referral_screen.dart's
/// doc comment). The copy here must never claim more than that.
class ReferralShareCard extends StatelessWidget {
  const ReferralShareCard({super.key, required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
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
            const Icon(Icons.card_giftcard, color: Color(0xFF26A69A), size: 40),
            const SizedBox(height: 16),
            const Text(
              'CRYPTO PAPER TRADER',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Practice crypto trading risk-free\n(simulated — no real money).',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 18),
            ),
            const SizedBox(height: 32),
            Text(
              'Use my invite code',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 14),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF26A69A), width: 2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                code,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 4,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              "We'll both earn bonus days when you sign up with it.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 14),
            ),
            const Spacer(),
            Text(
              'Educational simulator only — not financial advice.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
