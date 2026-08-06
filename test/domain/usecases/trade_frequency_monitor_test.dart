import 'package:crypto_paper_trader/domain/entities/order.dart';
import 'package:crypto_paper_trader/domain/usecases/trade_frequency_monitor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 1, 1, 12, 0);

  Order orderAt(DateTime timestamp) => Order(
        id: timestamp.toIso8601String(),
        coinSymbol: 'BTCUSDT',
        orderType: OrderType.buy,
        price: 100,
        quantity: 1,
        timestamp: timestamp,
      );

  test('counts only orders within the trailing window', () {
    final orders = [
      orderAt(now.subtract(const Duration(minutes: 5))), // in window
      orderAt(now.subtract(const Duration(minutes: 59))), // in window
      orderAt(now.subtract(const Duration(minutes: 61))), // out of window
      orderAt(now.subtract(const Duration(hours: 5))), // out of window
    ];

    expect(countTradesInTrailingWindow(orders, now: now), 2);
  });

  test('returns 0 for an empty order list', () {
    expect(countTradesInTrailingWindow(const [], now: now), 0);
  });

  test('respects a custom window duration', () {
    final orders = [
      orderAt(now.subtract(const Duration(minutes: 10))),
      orderAt(now.subtract(const Duration(minutes: 20))),
    ];

    expect(
      countTradesInTrailingWindow(orders, now: now, window: const Duration(minutes: 15)),
      1,
    );
  });

  test('an order exactly at the cutoff boundary is excluded', () {
    final orders = [orderAt(now.subtract(highFrequencyWindow))];
    expect(countTradesInTrailingWindow(orders, now: now), 0);
  });
}
