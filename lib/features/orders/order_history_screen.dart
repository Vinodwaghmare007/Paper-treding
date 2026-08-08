import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/order.dart';
import '../../domain/usecases/add_trade_rationale.dart';
import '../auth/sign_out_button.dart';
import '../portfolio/portfolio_providers.dart';
import '../regret_free/regret_free_card.dart';
import '../social/trader_profile_providers.dart';

class OrderHistoryScreen extends ConsumerWidget {
  const OrderHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(orderHistoryStreamProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E222D),
        title: const Text('Order History'),
        actions: const [SignOutButton()],
      ),
      body: ordersAsync.when(
        data: (orders) {
          if (orders.isEmpty) {
            return const Center(
              child: Text(
                'No orders yet.',
                style: TextStyle(color: Colors.white54),
              ),
            );
          }
          return Column(
            children: [
              const RegretFreeCard(),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: orders.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) => _OrderTile(order: orders[index]),
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text('Failed to load orders: $e',
              style: const TextStyle(color: Color(0xFFEF5350))),
        ),
      ),
    );
  }
}

class _OrderTile extends ConsumerWidget {
  const _OrderTile({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isBuy = order.orderType == OrderType.buy;
    final sideColor = isBuy ? const Color(0xFF26A69A) : const Color(0xFFEF5350);
    final pnl = order.realizedPnl;
    final ts = order.timestamp.toLocal();
    final timeLabel =
        '${ts.year}-${ts.month.toString().padLeft(2, '0')}-${ts.day.toString().padLeft(2, '0')} '
        '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}';

    return Card(
      color: const Color(0xFF1E222D),
      child: Column(
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: sideColor.withValues(alpha: 0.15),
              child: Icon(
                isBuy ? Icons.arrow_downward : Icons.arrow_upward,
                color: sideColor,
                size: 18,
              ),
            ),
            title: Text(
              '${order.orderType.code} ${order.coinSymbol}',
              style: TextStyle(color: sideColor, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              'Qty ${order.quantity} @ ${order.price.toStringAsFixed(2)}  ·  $timeLabel',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            trailing: pnl == null
                ? Text(
                    order.total.toStringAsFixed(2),
                    style: const TextStyle(color: Colors.white70),
                  )
                : Text(
                    '${pnl >= 0 ? '+' : ''}${pnl.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: pnl >= 0 ? const Color(0xFF26A69A) : const Color(0xFFEF5350),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
          // Trade Rationale is retrospective-only, so it's only ever
          // offered on a closed (SELL) order — see add_trade_rationale
          // .dart / addTradeRationale.ts for the server-enforced version
          // of this same rule.
          if (!isBuy) _RationaleRow(orderId: order.id),
        ],
      ),
    );
  }
}

class _RationaleRow extends ConsumerWidget {
  const _RationaleRow({required this.orderId});
  final String orderId;

  Future<void> _openEditor(BuildContext context, WidgetRef ref, String? existingText) async {
    final controller = TextEditingController(text: existingText ?? '');
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E222D),
        title: Text(
          existingText == null ? 'Add a Trade Rationale' : 'Edit your Trade Rationale',
          style: const TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: AddTradeRationaleUseCase.maxLength,
          maxLines: 4,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Why did you make this trade? (retrospective only)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (text == null || !context.mounted) return;

    try {
      await ref.read(addTradeRationaleUseCaseProvider).call(orderId: orderId, text: text);
    } on TradeRationaleException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rationale = ref.watch(ownRationaleProvider(orderId)).valueOrNull;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 12, 10),
      child: rationale == null
          ? Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _openEditor(context, ref, null),
                icon: const Icon(Icons.notes, size: 16),
                label: const Text('Add rationale'),
              ),
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.notes, size: 14, color: Colors.white38),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(rationale.text, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ),
                TextButton(
                  onPressed: () => _openEditor(context, ref, rationale.text),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(40, 24)),
                  child: const Text('Edit', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
    );
  }
}
