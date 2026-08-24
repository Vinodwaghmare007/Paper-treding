import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/conditional_order.dart';
import '../../l10n/generated/app_localizations.dart';
import '../connectivity/connectivity_providers.dart';
import '../connectivity/offline_banner.dart';
import '../home/more_menu_button.dart';
import '../settings/currency_providers.dart';
import '../settings/price_text.dart';
import '../trade/conditional_order_providers.dart';
import '../trade/set_stop_loss_take_profit_sheet.dart';
import '../trade/trade_sheet.dart';
import 'portfolio_providers.dart';
import 'portfolio_twin_card.dart';

class PortfolioScreen extends ConsumerWidget {
  const PortfolioScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final accountAsync = ref.watch(accountStreamProvider);
    final valuations = ref.watch(positionValuationsProvider);
    final totalValue = ref.watch(totalAccountValueProvider);
    final isOnline = ref.watch(isOnlineProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E222D),
        title: Text(l10n.portfolioTitle),
        actions: const [MoreMenuButton()],
      ),
      body: accountAsync.when(
        data: (account) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Firestore's own offline persistence is already what's
            // serving `account` here when offline (see app_database.dart's
            // doc comment) — this is purely the "tell the user" banner.
            if (!isOnline) const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: OfflineBanner(),
            ),
            _SummaryCard(
              totalValue: totalValue,
              virtualBalance: account.virtualBalance,
              consecutiveLosses: account.consecutiveLosses,
            ),
            const SizedBox(height: 12),
            const PortfolioTwinCard(),
            const SizedBox(height: 20),
            Text(
              l10n.portfolioHoldingsSectionTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (valuations.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    l10n.portfolioNoOpenPositions,
                    style: const TextStyle(color: Colors.white54),
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
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E222D),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.portfolioTotalAccountValue,
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 4),
          PriceText(
            totalValue,
            style: const TextStyle(
                color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _StatColumn(
                label: l10n.portfolioCashBalance,
                valueWidget: PriceText(
                  virtualBalance,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
              ),
              _StatColumn(
                label: l10n.portfolioLossStreak,
                valueWidget: Text(
                  '$consecutiveLosses',
                  style: TextStyle(
                    color: consecutiveLosses > 0 ? const Color(0xFFEF5350) : Colors.white,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  const _StatColumn({required this.label, required this.valueWidget});

  final String label;
  final Widget valueWidget;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
        valueWidget,
      ],
    );
  }
}

class _HoldingTile extends ConsumerWidget {
  const _HoldingTile({required this.valuation, required this.onTap});

  final PositionValuation valuation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final position = valuation.position;
    final pnl = valuation.unrealizedPnl;
    final pnlColor = pnl >= 0 ? const Color(0xFF26A69A) : const Color(0xFFEF5350);
    // Shown as a positive number either way — the short/long distinction
    // is conveyed by the SHORT badge, not a minus sign in the quantity.
    final displayQuantity =
        position.isShort ? -position.totalQuantity : position.totalQuantity;
    // Stop-loss/take-profit is v1-scoped to LONG positions only — see
    // TradeMath's short-selling doc comment and checkConditionalOrders.ts,
    // which only ever ports the long-closing branch server-side.
    final activeOrders = position.isLong
        ? ref.watch(activeConditionalOrdersForSymbolProvider(position.coinSymbol))
        : const <ConditionalOrder>[];
    final currency = ref.watch(currencyPreferenceProvider);
    final rate = ref.watch(usdToInrRateProvider).valueOrNull;

    return Card(
      color: const Color(0xFF1E222D),
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        children: [
          ListTile(
            onTap: onTap,
            title: Row(
              children: [
                Text(
                  position.coinSymbol,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
                if (position.isShort) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF5350).withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFFEF5350)),
                    ),
                    child: Text(
                      l10n.portfolioShortBadge,
                      style: const TextStyle(
                        color: Color(0xFFEF5350),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            subtitle: Row(
              children: [
                Text('Qty $displayQuantity  ·  Avg ',
                    style: const TextStyle(color: Colors.white54, fontSize: 12)),
                PriceText(position.avgBuyPrice,
                    style: const TextStyle(color: Colors.white54, fontSize: 12)),
                const Text('  ·  Now ', style: TextStyle(color: Colors.white54, fontSize: 12)),
                PriceText(valuation.currentPrice,
                    style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                PriceText(
                  pnl,
                  prefix: pnl >= 0 ? '+' : '',
                  style: TextStyle(color: pnlColor, fontWeight: FontWeight.w600),
                ),
                Text(
                  '${valuation.unrealizedPnlPercent >= 0 ? '+' : ''}${valuation.unrealizedPnlPercent.toStringAsFixed(2)}%',
                  style: TextStyle(color: pnlColor, fontSize: 11),
                ),
              ],
            ),
          ),
          if (position.isLong)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final order in activeOrders)
                          _ConditionalOrderBadge(order: order, currency: currency, rate: rate),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => showStopLossTakeProfitSheet(
                      context,
                      holding: position,
                      currentPrice: valuation.currentPrice,
                    ),
                    child: Text(
                      l10n.portfolioSetStopLossTakeProfit,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ConditionalOrderBadge extends StatelessWidget {
  const _ConditionalOrderBadge({required this.order, required this.currency, required this.rate});

  final ConditionalOrder order;
  final String currency;
  final double? rate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final color = order.isStopLoss ? const Color(0xFFEF5350) : const Color(0xFF26A69A);
    final priceStr = formatCurrency(order.triggerPrice, currency, rate);
    final label =
        order.isStopLoss ? l10n.portfolioActiveStopLoss(priceStr) : l10n.portfolioActiveTakeProfit(priceStr);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }
}
