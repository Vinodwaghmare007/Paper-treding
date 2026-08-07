import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'portfolio_providers.dart';

/// "You: $102,400 · Similar traders: $99,800" — the user's own portfolio
/// value next to their cohort's published median, never any other
/// individual's data (see CohortRepository / firestore.rules). Renders
/// nothing until there's a cohort median to actually compare against —
/// either the account is too new to have a `createdAt`, or its cohort
/// hasn't reached MIN_COHORT_SIZE in computeCohortMedians.ts yet.
class PortfolioTwinCard extends ConsumerWidget {
  const PortfolioTwinCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final median = ref.watch(cohortMedianProvider).valueOrNull;
    if (median == null) return const SizedBox.shrink();

    final myValue = ref.watch(totalAccountValueProvider);
    final delta = myValue - median.medianPortfolioValue;
    final aheadOfMedian = delta >= 0;
    final deltaColor = aheadOfMedian ? const Color(0xFF26A69A) : const Color(0xFFEF5350);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E222D),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Portfolio Twin',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _ValueColumn(label: 'You', value: myValue, valueColor: Colors.white),
              _ValueColumn(
                label: 'Similar traders',
                value: median.medianPortfolioValue,
                valueColor: Colors.white70,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            aheadOfMedian
                ? "You're \$${delta.abs().toStringAsFixed(0)} ahead of ${median.memberCount} similar traders."
                : "You're \$${delta.abs().toStringAsFixed(0)} behind ${median.memberCount} similar traders.",
            style: TextStyle(color: deltaColor, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _ValueColumn extends StatelessWidget {
  const _ValueColumn({required this.label, required this.value, required this.valueColor});

  final String label;
  final double value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
        Text(
          '\$${value.toStringAsFixed(2)}',
          style: TextStyle(color: valueColor, fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
