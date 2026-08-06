import 'package:crypto_paper_trader/domain/entities/order.dart';
import 'package:crypto_paper_trader/domain/entities/portfolio_position.dart';
import 'package:crypto_paper_trader/domain/entities/user_account.dart';
import 'package:crypto_paper_trader/domain/usecases/trade_exceptions.dart';
import 'package:crypto_paper_trader/domain/usecases/trade_math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const uid = 'user-1';
  final now = DateTime.utc(2026, 1, 1, 12);
  const freshAccount =
      UserAccount(uid: uid, virtualBalance: 100000, consecutiveLosses: 0);

  group('TradeMath.applyBuy', () {
    test('opens a new position and deducts the cost', () {
      final outcome = TradeMath.applyBuy(
        account: freshAccount,
        existingPosition: null,
        coinSymbol: 'btcusdt',
        price: 60000,
        quantity: 0.1,
        now: now,
        orderId: 'order-1',
      );

      expect(outcome.updatedPosition.coinSymbol, 'BTCUSDT');
      expect(outcome.updatedPosition.totalQuantity, 0.1);
      expect(outcome.updatedPosition.avgBuyPrice, 60000);
      expect(outcome.updatedAccount.virtualBalance, 100000 - 6000);
      expect(outcome.order.orderType, OrderType.buy);
    });

    test('folds into a weighted-average price', () {
      final outcome = TradeMath.applyBuy(
        account: freshAccount,
        existingPosition: const PortfolioPosition(
            coinSymbol: 'BTCUSDT', totalQuantity: 1, avgBuyPrice: 50000),
        coinSymbol: 'BTCUSDT',
        price: 60000,
        quantity: 1,
        now: now,
        orderId: 'order-2',
      );

      expect(outcome.updatedPosition.totalQuantity, 2);
      expect(outcome.updatedPosition.avgBuyPrice, 55000);
    });

    test('throws InsufficientBalanceException over budget', () {
      expect(
        () => TradeMath.applyBuy(
          account: const UserAccount(
              uid: uid, virtualBalance: 100, consecutiveLosses: 0),
          existingPosition: null,
          coinSymbol: 'BTCUSDT',
          price: 60000,
          quantity: 1,
          now: now,
          orderId: 'order-3',
        ),
        throwsA(isA<InsufficientBalanceException>()),
      );
    });

    test('throws TradingLockedException while locked', () {
      expect(
        () => TradeMath.applyBuy(
          account: UserAccount(
            uid: uid,
            virtualBalance: 100000,
            consecutiveLosses: 3,
            buyLockedUntil: now.add(const Duration(minutes: 5)),
          ),
          existingPosition: null,
          coinSymbol: 'BTCUSDT',
          price: 60000,
          quantity: 0.1,
          now: now,
          orderId: 'order-4',
        ),
        throwsA(isA<TradingLockedException>()),
      );
    });

    test('throws InvalidTradeException for non-positive inputs', () {
      expect(
        () => TradeMath.applyBuy(
          account: freshAccount,
          existingPosition: null,
          coinSymbol: 'BTCUSDT',
          price: 0,
          quantity: 1,
          now: now,
          orderId: 'order-5',
        ),
        throwsA(isA<InvalidTradeException>()),
      );
    });
  });

  group('TradeMath.applySell', () {
    const holding = PortfolioPosition(
        coinSymbol: 'BTCUSDT', totalQuantity: 1, avgBuyPrice: 50000);

    test('books realized P&L and credits proceeds', () {
      final outcome = TradeMath.applySell(
        account: freshAccount,
        existingPosition: holding,
        coinSymbol: 'BTCUSDT',
        price: 60000,
        quantity: 0.5,
        now: now,
        orderId: 'order-6',
      );

      expect(outcome.order.realizedPnl, 5000); // (60000-50000)*0.5
      expect(outcome.updatedAccount.virtualBalance, 100000 + 30000);
      expect(outcome.updatedPosition?.totalQuantity, 0.5);
      expect(outcome.updatedPosition?.avgBuyPrice, 50000);
    });

    test('fully closing a position returns a null updatedPosition', () {
      final outcome = TradeMath.applySell(
        account: freshAccount,
        existingPosition: holding,
        coinSymbol: 'BTCUSDT',
        price: 60000,
        quantity: 1,
        now: now,
        orderId: 'order-7',
      );

      expect(outcome.updatedPosition, isNull);
    });

    test('throws InsufficientHoldingsException over the held amount', () {
      expect(
        () => TradeMath.applySell(
          account: freshAccount,
          existingPosition: holding,
          coinSymbol: 'BTCUSDT',
          price: 60000,
          quantity: 2,
          now: now,
          orderId: 'order-8',
        ),
        throwsA(isA<InsufficientHoldingsException>()),
      );
    });

    test('a losing sell increments consecutive_losses', () {
      final outcome = TradeMath.applySell(
        account: const UserAccount(
            uid: uid, virtualBalance: 100000, consecutiveLosses: 1),
        existingPosition: holding,
        coinSymbol: 'BTCUSDT',
        price: 40000, // below avg buy price -> loss
        quantity: 1,
        now: now,
        orderId: 'order-9',
      );

      expect(outcome.order.realizedPnl, lessThan(0));
      expect(outcome.updatedAccount.consecutiveLosses, 2);
      expect(outcome.updatedAccount.buyLockedUntil, isNull);
    });

    test('the 3rd consecutive loss arms a 30-minute buy lock', () {
      final outcome = TradeMath.applySell(
        account: const UserAccount(
            uid: uid, virtualBalance: 100000, consecutiveLosses: 2),
        existingPosition: holding,
        coinSymbol: 'BTCUSDT',
        price: 40000,
        quantity: 1,
        now: now,
        orderId: 'order-10',
      );

      expect(outcome.updatedAccount.consecutiveLosses, 3);
      expect(outcome.updatedAccount.buyLockedUntil, now.add(UserAccount.lockDuration));
    });

    test('a profitable sell resets consecutive_losses to zero', () {
      final outcome = TradeMath.applySell(
        account: const UserAccount(
            uid: uid, virtualBalance: 100000, consecutiveLosses: 2),
        existingPosition: holding,
        coinSymbol: 'BTCUSDT',
        price: 60000,
        quantity: 1,
        now: now,
        orderId: 'order-11',
      );

      expect(outcome.updatedAccount.consecutiveLosses, 0);
    });
  });
}
