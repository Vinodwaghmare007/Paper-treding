import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/order.dart';
import '../auth/sign_out_button.dart';
import '../portfolio/portfolio_providers.dart';
import '../regret_free/regret_free_card.dart';

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

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final isBuy = order.orderType == OrderType.buy;
    final sideColor = isBuy ? const Color(0xFF26A69A) : const Color(0xFFEF5350);
    final pnl = order.realizedPnl;
    final ts = order.timestamp.toLocal();
    final timeLabel =
        '${ts.year}-${ts.month.toString().padLeft(2, '0')}-${ts.day.toString().padLeft(2, '0')} '
        '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}';

    return Card(
      color: const Color(0xFF1E222D),
      child: ListTile(
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
    );
  }
}
