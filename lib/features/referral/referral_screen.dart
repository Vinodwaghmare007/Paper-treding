import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/usecases/generate_referral_code.dart';
import '../portfolio/portfolio_providers.dart';
import 'referral_providers.dart';
import 'referral_share_card.dart';

/// Refer-a-friend screen. Every account gets a code (generated lazily
/// here, on first visit, via the idempotent `generateReferralCode`
/// callable) and earns `pro_days_earned` for each successful signup that
/// redeems it — see functions/src/growth/referrals.ts.
///
/// IMPORTANT — read before changing any copy on this screen: this app has
/// no subscription/paywall feature (see analytics_service.dart's doc
/// comment). `pro_access_until`/`pro_days_earned` are real, honestly
/// tracked fields, but today they don't unlock anything — there is no
/// paid tier for them to gate. This was an explicit product decision
/// (confirmed with the app owner) rather than an oversight: the UI must
/// say plainly that this is currently just a counter/badge, never imply a
/// working Pro tier exists. If a real paid tier ships later, this screen
/// (and this comment) should be revisited together.
class ReferralScreen extends ConsumerStatefulWidget {
  const ReferralScreen({super.key});

  @override
  ConsumerState<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends ConsumerState<ReferralScreen> {
  final _screenshotController = ScreenshotController();
  bool _generating = false;
  bool _requestedGeneration = false;
  String? _generationError;
  bool _sharing = false;

  Future<void> _ensureCode(String? existingCode) async {
    if (existingCode != null || _requestedGeneration) return;
    _requestedGeneration = true;
    setState(() => _generating = true);
    try {
      await ref.read(generateReferralCodeUseCaseProvider).call();
      // No local state write needed — the Cloud Function's write to
      // users/{uid}.referral_code arrives back through the existing
      // accountStreamProvider Firestore listener.
    } on ReferralCodeException catch (e) {
      if (mounted) setState(() => _generationError = e.message);
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _share(String code) async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final bytes = await _screenshotController.capture(pixelRatio: 2);
      if (bytes == null) return;
      await Share.shareXFiles(
        [XFile.fromData(bytes, mimeType: 'image/png', name: 'referral.png')],
        text: 'Join me on Crypto Paper Trader (simulated crypto trading, no '
            'real money) — use my invite code $code when you sign up and '
            "we'll both earn bonus days.",
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(accountStreamProvider).valueOrNull;
    final code = account?.referralCode;
    final proDaysEarned = account?.proDaysEarned ?? 0;
    final proAccessUntil = account?.proAccessUntil;
    final referralCountAsync = ref.watch(referralCountProvider);

    if (code == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _ensureCode(code));
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E222D),
        title: const Text('Refer a Friend'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (code == null) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Center(
                  child: _generationError != null
                      ? Text(
                          'Could not create your referral code: $_generationError',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFFEF5350)),
                        )
                      : const CircularProgressIndicator(),
                ),
              ),
            ] else ...[
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 340),
                  child: Screenshot(
                    controller: _screenshotController,
                    child: ReferralShareCard(code: code),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _sharing ? null : () => _share(code),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF26A69A)),
                icon: _sharing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.share),
                label: const Text('Share my code'),
              ),
            ],
            const SizedBox(height: 24),
            Card(
              color: const Color(0xFF1E222D),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Your referrals', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    referralCountAsync.when(
                      data: (count) => Text(
                        count == 1 ? '1 successful referral' : '$count successful referrals',
                        style: const TextStyle(color: Colors.white70),
                      ),
                      loading: () => const LinearProgressIndicator(),
                      error: (e, _) =>
                          Text('$e', style: const TextStyle(color: Color(0xFFEF5350))),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$proDaysEarned bonus day${proDaysEarned == 1 ? '' : 's'} earned in total',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    if (proAccessUntil != null && proAccessUntil.isAfter(DateTime.now())) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Active window until ${proAccessUntil.toLocal()}'.split('.').first,
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              "These bonus days are tracked for you, but there's no paid "
              "Pro tier in the app yet for them to unlock — nothing is "
              "gated behind this today. If a Pro tier launches in the "
              "future, days you've already earned will count toward it.",
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
