import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'trade_frequency_provider.dart';

/// Non-blocking anti-gamification nudge — unlike the revenge-blocker, this
/// never prevents a trade. It's dismissible per-session and reappears if
/// the count crosses the threshold again later.
class HighFrequencyBanner extends ConsumerStatefulWidget {
  const HighFrequencyBanner({super.key});

  @override
  ConsumerState<HighFrequencyBanner> createState() => _HighFrequencyBannerState();
}

class _HighFrequencyBannerState extends ConsumerState<HighFrequencyBanner> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    final isHighFrequency = ref.watch(isHighFrequencyTradingProvider);

    // Re-arms the banner once frequency drops back under the threshold, so
    // it can show again if it climbs back up later in the session.
    ref.listen<bool>(isHighFrequencyTradingProvider, (previous, next) {
      if (!next && _dismissed) setState(() => _dismissed = false);
    });

    if (!isHighFrequency || _dismissed) return const SizedBox.shrink();

    final count = ref.watch(tradeFrequencyProvider);

    return Container(
      width: double.infinity,
      color: const Color(0xFFFFC107).withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.speed, color: Color(0xFFFFC107), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$count trades in the last hour. Historically, high-frequency '
              'trading correlates with lower average returns than a '
              'slower, plan-based approach.',
              style: const TextStyle(color: Color(0xFFFFC107), fontSize: 12),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Color(0xFFFFC107), size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => setState(() => _dismissed = true),
          ),
        ],
      ),
    );
  }
}
