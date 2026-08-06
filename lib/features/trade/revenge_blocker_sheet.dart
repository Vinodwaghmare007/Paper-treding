import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/user_account.dart';
import 'risk_management_tips.dart';
import 'trade_lock_provider.dart';

/// Opens the revenge-blocker hard lock. This is deliberately NOT a toast
/// and NOT casually dismissible: no tap-outside, no swipe-down, no back
/// button, and no "skip" affordance anywhere in it. The only way out is for
/// the lock to actually expire — a lock the user can bypass in two taps
/// isn't a safeguard, it's decoration.
Future<void> showRevengeBlockerSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1E222D),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => const _RevengeBlockerSheet(),
  );
}

class _RevengeBlockerSheet extends ConsumerWidget {
  const _RevengeBlockerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lockState = ref.watch(tradeLockProvider);

    // The lock expiring while this sheet is open is the ONLY way it closes.
    ref.listen<TradeLockState>(tradeLockProvider, (previous, next) {
      if (!next.isLocked && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });

    final lockedUntil = lockState.lockedUntil;
    // Rotates deterministically per lock event (not per rebuild), so the
    // tip stays stable for the duration of one lock but differs the next
    // time a lock is triggered.
    final tip = riskManagementTips[
        (lockedUntil?.millisecondsSinceEpoch ?? 0) % riskManagementTips.length];

    final minutes = (lockState.remainingSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (lockState.remainingSeconds % 60).toString().padLeft(2, '0');

    return PopScope(
      // Blocks the system back gesture/button too — tap-outside and
      // swipe-down are already disabled via showModalBottomSheet's options.
      canPop: !lockState.isLocked,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.pan_tool_alt, color: Color(0xFFEF5350), size: 40),
            const SizedBox(height: 16),
            const Text(
              'Buying is paused',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'You\'ve had ${UserAccount.lossStreakLimit} losing trades in a '
              'row. To keep a losing streak from turning into a bigger one, '
              'new buys are paused for a short cooldown.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF131722),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  const Text(
                    'TIME REMAINING',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$minutes:$seconds',
                    style: const TextStyle(
                      color: Color(0xFFFFC107),
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.lightbulb_outline, color: Color(0xFF26A69A), size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'A general risk-management principle — not personalized advice:',
                        style: TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tip,
                        style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Selling is still available. This pause only applies to new buys.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
