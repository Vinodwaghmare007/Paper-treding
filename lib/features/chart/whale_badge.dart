import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'whale_providers.dart';

/// "🐋 N large transactions in the last hour" — purely informational, on
/// the chart screen. Silent (renders nothing) while loading or on error,
/// same treatment as ticker_screen.dart's community sentiment badge: a
/// non-critical badge failing shouldn't ever look like a broken screen.
/// Tapping shows a plain-language explanation, never the underlying
/// transaction list — this stays an educational "context" signal, not a
/// pro on-chain analytics tool.
class WhaleBadge extends ConsumerWidget {
  const WhaleBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(whaleActivityProvider).valueOrNull;
    if (count == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _showExplanation(context, count),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🐋', style: TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
            Text(
              '$count large transaction${count == 1 ? '' : 's'} in the last hour',
              style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.info_outline, size: 13, color: Colors.white38),
          ],
        ),
      ),
    );
  }

  void _showExplanation(BuildContext context, int count) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E222D),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Text('🐋', style: TextStyle(fontSize: 22)),
                SizedBox(width: 8),
                Text('Large Bitcoin transactions',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              "In the last hour, this app observed $count Bitcoin transaction"
              "${count == 1 ? '' : 's'} moving 10 BTC or more on-chain — "
              "sometimes called a \"whale\" transaction because of the size "
              "of the wallet involved.",
              style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            const Text(
              'A large transaction usually just means coins are moving '
              'between wallets or exchanges — it could be an exchange, a '
              'fund, or one person consolidating their own wallets. It is '
              'informational only and is not a trading signal or a '
              'prediction of what price will do next.',
              style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 12),
            const Text(
              'Source: public Bitcoin mempool data. Counted only while this '
              'screen has been open and polling — not a complete record of '
              'every large transaction in the last hour.',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Got it'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
