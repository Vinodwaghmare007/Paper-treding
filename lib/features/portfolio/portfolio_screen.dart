import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/sign_out_button.dart';
import '../trade/trade_sheet.dart';
import 'portfolio_providers.dart';

class PortfolioScreen extends ConsumerWidget {
  const PortfolioScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountAsync = ref.watch(accountStreamProvider);
    final valuations = ref.watch(positionValuationsProvider);
    final totalValue = ref.watch(totalAccountValueProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E222D),
        title: const Text('Portfolio'),
        actions: const [SignOutButton()],
      ),
      body: accountAsync.when(
        data: (account) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _SummaryCard(
              totalValue: totalValue,
              virtualBalance: account.virtualBalance,
              consecutiveLosses: account.consecutiveLosses,
            ),
            const SizedBox(height: 20),
            Text(
              'Holdings',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (valuations.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'No open positions yet. Trade from the chart screen.',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
              )
            else
              ...valuations.map(
                (v) => _HoldingTile(
                  valuation: v,
                  onTap: () => showTradeSheet(
                    context,
                    coinSymbol: v.position.coinSymbol,
                    currentPrice: v.currentPrice,
                  ),
                ),
              ),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text('Failed to load account: $e',
              style: const TextStyle(color: Color(0xFFEF5350))),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.totalValue,
    required this.virtualBalance,
    required this.consecutiveLosses,
  });

  final double totalValue;
  final double virtualBalance;
  final int consecutiveLosses;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E222D),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Total account value',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 4),
          Text(
            '\$${totalValue.toStringAsFixed(2)}',
            style: const TextStyle(
                color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _StatColumn(
                label: 'Cash balance',
                value: '\$${virtualBalance.toStringAsFixed(2)}',
              ),
              _StatColumn(
                label: 'Loss streak',
                value: '$consecutiveLosses',
                valueColor: consecutiveLosses > 0
                    ? const Color(0xFFEF5350)
                    : Colors.white,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  const _StatColumn({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
        Text(value, style: TextStyle(color: valueColor ?? Colors.white, fontSize: 15)),
      ],
    );
  }
}

class _HoldingTile extends StatelessWidget {
  const _HoldingTile({required this.valuation, required this.onTap});

  final PositionValuation valuation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pnl = valuation.unrealizedPnl;
    final pnlColor = pnl >= 0 ? const Color(0xFF26A69A) : const Color(0xFFEF5350);
    return Card(
      color: const Color(0xFF1E222D),
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: onTap,
        title: Text(
          valuation.position.coinSymbol,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          'Qty ${valuation.position.totalQuantity}  ·  Avg ${valuation.position.avgBuyPrice.toStringAsFixed(2)}  ·  Now ${valuation.currentPrice.toStringAsFixed(2)}',
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${pnl >= 0 ? '+' : ''}${pnl.toStringAsFixed(2)}',
              style: TextStyle(color: pnlColor, fontWeight: FontWeight.w600),
            ),
            Text(
              '${valuation.unrealizedPnlPercent >= 0 ? '+' : ''}${valuation.unrealizedPnlPercent.toStringAsFixed(2)}%',
              style: TextStyle(color: pnlColor, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
