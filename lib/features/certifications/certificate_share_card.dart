import 'package:flutter/material.dart';

import '../../domain/entities/certification.dart';

/// Overridable at build time the same way _privacyPolicyUrl is in
/// sign_in_screen.dart, in case the GitHub Pages source/branch changes:
/// flutter build ... --dart-define=VERIFY_BASE_URL=https://...
const _verifyBaseUrl = String.fromEnvironment(
  'VERIFY_BASE_URL',
  defaultValue: 'https://vinodwaghmare007.github.io/Paper-treding/verify.html',
);

String verificationUrlFor(String code) => '$_verifyBaseUrl?code=$code';

/// The visual certificate captured for sharing — see certificate_screen
/// .dart's [ScreenshotController] usage, same pattern as Phase 5's
/// WhatIfShareCard. Landscape rather than 9:16, since a "certificate"
/// reads as a document, not a story-format share image.
class CertificateShareCard extends StatelessWidget {
  const CertificateShareCard({super.key, required this.certification});

  final Certification certification;

  @override
  Widget build(BuildContext context) {
    final earned = certification.earnedAt.toLocal();
    final dateLabel =
        '${earned.year}-${earned.month.toString().padLeft(2, '0')}-${earned.day.toString().padLeft(2, '0')}';

    return AspectRatio(
      aspectRatio: 16 / 10,
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF131722), Color(0xFF1E222D)],
          ),
          border: Border.all(color: const Color(0xFF6FD3C7), width: 2),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(Icons.workspace_premium, color: Color(0xFF6FD3C7), size: 36),
            const SizedBox(height: 12),
            const Text(
              'CRYPTO PAPER TRADER — CERTIFICATE OF ACHIEVEMENT',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              certification.milestoneType.milestoneTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              certification.milestoneType.milestoneDescription,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13),
            ),
            const SizedBox(height: 16),
            Text('Earned $dateLabel', style: const TextStyle(color: Colors.white54, fontSize: 12)),
            const Spacer(),
            Text(
              'Verify at ${verificationUrlFor(certification.verificationCode)}\n'
              'Code: ${certification.verificationCode}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
            const SizedBox(height: 6),
            Text(
              'Earned in an educational paper-trading simulator — no real '
              'money or real trading account is involved.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}
