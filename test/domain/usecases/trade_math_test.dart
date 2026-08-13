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

      expect(outcome.updatedPosition!.coinSymbol, 'BTCUSDT');
      expect(outcome.updatedPosition!.totalQuantity, 0.1);
      expect(outcome.updatedPosition!.avgBuyPrice, 60000);
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

      expect(outcome.updatedPosition!.totalQuantity, 2);
      expect(outcome.updatedPosition!.avgBuyPrice, 55000);
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

    test('throws InvalidTradeException for a zero price', () {
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

    test('throws InvalidTradeException for a negative price', () {
      expect(
        () => TradeMath.applyBuy(
          account: freshAccount,
          existingPosition: null,
          coinSymbol: 'BTCUSDT',
          price: -60000,
          quantity: 1,
          now: now,
          orderId: 'order-5b',
        ),
        throwsA(isA<InvalidTradeException>()),
      );
    });

    test('throws InvalidTradeException for a zero quantity', () {
      // Regression coverage for the second branch of validatePositive —
      // the existing "non-positive inputs" cases above only ever exercised
      // the price check, since it runs first and short-circuits.
      expect(
        () => TradeMath.applyBuy(
          account: freshAccount,
          existingPosition: null,
          coinSymbol: 'BTCUSDT',
          price: 60000,
          quantity: 0,
          now: now,
          orderId: 'order-5c',
        ),
        throwsA(isA<InvalidTradeException>()),
      );
    });

    test('throws InvalidTradeException for a negative quantity', () {
      expect(
        () => TradeMath.applyBuy(
          account: freshAccount,
          existingPosition: null,
          coinSymbol: 'BTCUSDT',
          price: 60000,
          quantity: -0.1,
          now: now,
          orderId: 'order-5d',
        ),
        throwsA(isA<InvalidTradeException>()),
      );
    });

    test('a cost exactly equal to the available balance succeeds and '
        'zeroes the balance', () {
      final outcome = TradeMath.applyBuy(
        account: const UserAccount(uid: uid, virtualBalance: 6000, consecutiveLosses: 0),
        existingPosition: null,
        coinSymbol: 'BTCUSDT',
        price: 60000,
        quantity: 0.1,
        now: now,
        orderId: 'order-5e',
      );
      expect(outcome.updatedAccount.virtualBalance, 0);
    });

    test('InsufficientBalanceException reports the exact required and '
        'available amounts', () {
      try {
        TradeMath.applyBuy(
          account: const UserAccount(uid: uid, virtualBalance: 100, consecutiveLosses: 0),
          existingPosition: null,
          coinSymbol: 'BTCUSDT',
          price: 60000,
          quantity: 1,
          now: now,
          orderId: 'order-5f',
        );
        fail('expected InsufficientBalanceException');
      } on InsufficientBalanceException catch (e) {
        expect(e.required, 60000);
        expect(e.available, 100);
      }
    });

    test('weighted-average price stays exact under repeating-decimal inputs', () {
      // 1 @ 10 then 2 @ 20 -> (10 + 40) / 3 = 16.666... — a real float-
      // precision hazard if the accumulation were done any other way than
      // total-cost-over-total-quantity in one division.
      final outcome = TradeMath.applyBuy(
        account: const UserAccount(uid: uid, virtualBalance: 100000, consecutiveLosses: 0),
        existingPosition: const PortfolioPosition(
            coinSymbol: 'BTCUSDT', totalQuantity: 1, avgBuyPrice: 10),
        coinSymbol: 'BTCUSDT',
        price: 20,
        quantity: 2,
        now: now,
        orderId: 'order-5g',
      );
      expect(outcome.updatedPosition!.avgBuyPrice, closeTo(50 / 3, 1e-9));
    });
  });

  group('TradeMath.applyBuy — covering a short', () {
    const shortHolding = PortfolioPosition(
        coinSymbol: 'BTCUSDT', totalQuantity: -1, avgBuyPrice: 60000);

    test('covers part of a short and books realized P&L', () {
      final outcome = TradeMath.applyBuy(
        account: freshAccount,
        existingPosition: shortHolding,
        coinSymbol: 'BTCUSDT',
        price: 50000, // bought back cheaper than the short's entry -> profit
        quantity: 0.5,
        now: now,
        orderId: 'order-short-1',
      );

      expect(outcome.order.orderType, OrderType.buy);
      expect(outcome.order.realizedPnl, 5000); // (60000-50000)*0.5
      expect(outcome.updatedAccount.virtualBalance, 100000 - 25000);
      expect(outcome.updatedPosition!.totalQuantity, -0.5);
      expect(outcome.updatedPosition!.avgBuyPrice, 60000);
    });

    test('fully covering a short returns a null updatedPosition', () {
      final outcome = TradeMath.applyBuy(
        account: freshAccount,
        existingPosition: shortHolding,
        coinSymbol: 'BTCUSDT',
        price: 50000,
        quantity: 1,
        now: now,
        orderId: 'order-short-2',
      );
      expect(outcome.updatedPosition, isNull);
    });

    test('a losing short cover (bought back higher than entry) increments consecutive_losses', () {
      final outcome = TradeMath.applyBuy(
        account: const UserAccount(uid: uid, virtualBalance: 100000, consecutiveLosses: 1),
        existingPosition: shortHolding,
        coinSymbol: 'BTCUSDT',
        price: 70000, // above the short's entry -> loss
        quantity: 1,
        now: now,
        orderId: 'order-short-3',
      );
      expect(outcome.order.realizedPnl, lessThan(0));
      expect(outcome.updatedAccount.consecutiveLosses, 2);
    });

    test('throws InvalidTradeException when the buy would flip a short past zero into a long', () {
      // Design choice: a single order never crosses a position through
      // zero — cover fully first, then buy separately.
      expect(
        () => TradeMath.applyBuy(
          account: freshAccount,
          existingPosition: shortHolding,
          coinSymbol: 'BTCUSDT',
          price: 50000,
          quantity: 1.5,
          now: now,
          orderId: 'order-short-4',
        ),
        throwsA(isA<InvalidTradeException>()),
      );
    });

    test('covering a short is never blocked by the buy-lock', () {
      final lockedAccount = UserAccount(
        uid: uid,
        virtualBalance: 100000,
        consecutiveLosses: 3,
        buyLockedUntil: now.add(const Duration(minutes: 5)),
      );
      final outcome = TradeMath.applyBuy(
        account: lockedAccount,
        existingPosition: shortHolding,
        coinSymbol: 'BTCUSDT',
        price: 50000,
        quantity: 1,
        now: now,
        orderId: 'order-short-5',
      );
      expect(outcome.updatedPosition, isNull);
    });

    test('opening/adding to a long is still blocked by the buy-lock (unaffected by the short carve-out)', () {
      final lockedAccount = UserAccount(
        uid: uid,
        virtualBalance: 100000,
        consecutiveLosses: 3,
        buyLockedUntil: now.add(const Duration(minutes: 5)),
      );
      expect(
        () => TradeMath.applyBuy(
          account: lockedAccount,
          existingPosition: null,
          coinSymbol: 'BTCUSDT',
          price: 50000,
          quantity: 1,
          now: now,
          orderId: 'order-short-6',
        ),
        throwsA(isA<TradingLockedException>()),
      );
    });

    test('covering a short still throws InsufficientBalanceException if the buy-back cost exceeds balance', () {
      expect(
        () => TradeMath.applyBuy(
          account: const UserAccount(uid: uid, virtualBalance: 100, consecutiveLosses: 0),
          existingPosition: shortHolding,
          coinSymbol: 'BTCUSDT',
          price: 50000,
          quantity: 1,
          now: now,
          orderId: 'order-short-7',
        ),
        throwsA(isA<InsufficientBalanceException>()),
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

    test('InsufficientHoldingsException reports the exact requested and '
        'held amounts', () {
      try {
        TradeMath.applySell(
          account: freshAccount,
          existingPosition: holding,
          coinSymbol: 'BTCUSDT',
          price: 60000,
          quantity: 2,
          now: now,
          orderId: 'order-8b',
        );
        fail('expected InsufficientHoldingsException');
      } on InsufficientHoldingsException catch (e) {
        expect(e.requested, 2);
        expect(e.held, 1);
      }
    });

    test('throws InvalidTradeException for a negative price', () {
      expect(
        () => TradeMath.applySell(
          account: freshAccount,
          existingPosition: holding,
          coinSymbol: 'BTCUSDT',
          price: -60000,
          quantity: 0.5,
          now: now,
          orderId: 'order-8c',
        ),
        throwsA(isA<InvalidTradeException>()),
      );
    });

    test('throws InvalidTradeException for a zero quantity', () {
      expect(
        () => TradeMath.applySell(
          account: freshAccount,
          existingPosition: holding,
          coinSymbol: 'BTCUSDT',
          price: 60000,
          quantity: 0,
          now: now,
          orderId: 'order-8d',
        ),
        throwsA(isA<InvalidTradeException>()),
      );
    });

    test('normalizes a lowercase coin symbol', () {
      final outcome = TradeMath.applySell(
        account: freshAccount,
        existingPosition: holding,
        coinSymbol: 'btcusdt',
        price: 60000,
        quantity: 0.5,
        now: now,
        orderId: 'order-8e',
      );
      expect(outcome.order.coinSymbol, 'BTCUSDT');
      expect(outcome.updatedPosition?.coinSymbol, 'BTCUSDT');
    });

    test('a breakeven sell (zero realized P&L) is not counted as a loss', () {
      // Financial-correctness edge case: `realizedPnl < 0` must exclude
      // exactly-zero, or a breakeven trade would incorrectly march the
      // revenge-blocker streak forward.
      final outcome = TradeMath.applySell(
        account: const UserAccount(uid: uid, virtualBalance: 100000, consecutiveLosses: 2),
        existingPosition: holding,
        coinSymbol: 'BTCUSDT',
        price: 50000, // == avgBuyPrice -> exactly zero P&L
        quantity: 1,
        now: now,
        orderId: 'order-8f',
      );
      expect(outcome.order.realizedPnl, 0);
      expect(outcome.updatedAccount.consecutiveLosses, 0);
      expect(outcome.updatedAccount.buyLockedUntil, isNull);
    });

    test('selling down to a float-dust remainder is treated as fully closed', () {
      // 0.1 + 0.1 + 0.1 != 0.3 exactly in binary floating point; a naive
      // `remainingQuantity == 0` check would leave a phantom position open.
      const dustyHolding = PortfolioPosition(
          coinSymbol: 'BTCUSDT', totalQuantity: 0.1 + 0.1 + 0.1, avgBuyPrice: 50000);
      final outcome = TradeMath.applySell(
        account: freshAccount,
        existingPosition: dustyHolding,
        coinSymbol: 'BTCUSDT',
        price: 60000,
        quantity: 0.3,
        now: now,
        orderId: 'order-8g',
      );
      expect(outcome.updatedPosition, isNull);
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

  group('TradeMath.applySell — opening/adding to a short', () {
    test('opens a fresh short with no realized P&L, credits proceeds', () {
      final outcome = TradeMath.applySell(
        account: freshAccount,
        existingPosition: null,
        coinSymbol: 'BTCUSDT',
        price: 60000,
        quantity: 0.5,
        now: now,
        orderId: 'order-short-open-1',
      );

      expect(outcome.order.realizedPnl, isNull);
      expect(outcome.updatedAccount.virtualBalance, 100000 + 30000);
      expect(outcome.updatedPosition!.totalQuantity, -0.5);
      expect(outcome.updatedPosition!.avgBuyPrice, 60000);
    });

    test('adds to an existing short with a weighted-average entry price', () {
      const existingShort = PortfolioPosition(
          coinSymbol: 'BTCUSDT', totalQuantity: -1, avgBuyPrice: 50000);
      final outcome = TradeMath.applySell(
        account: freshAccount,
        existingPosition: existingShort,
        coinSymbol: 'BTCUSDT',
        price: 60000,
        quantity: 1,
        now: now,
        orderId: 'order-short-open-2',
      );

      expect(outcome.updatedPosition!.totalQuantity, -2);
      expect(outcome.updatedPosition!.avgBuyPrice, 55000); // (50000+60000)/2
      expect(outcome.order.realizedPnl, isNull);
    });

    test('opening a short is never blocked by the buy-lock (the lock only ever gates BUYs)', () {
      final lockedAccount = UserAccount(
        uid: uid,
        virtualBalance: 100000,
        consecutiveLosses: 3,
        buyLockedUntil: now.add(const Duration(minutes: 5)),
      );
      final outcome = TradeMath.applySell(
        account: lockedAccount,
        existingPosition: null,
        coinSymbol: 'BTCUSDT',
        price: 60000,
        quantity: 0.5,
        now: now,
        orderId: 'order-short-open-3',
      );
      expect(outcome.updatedPosition!.totalQuantity, -0.5);
    });

    test('throws InsufficientBalanceException when opening a short would exceed the collateral check', () {
      expect(
        () => TradeMath.applySell(
          account: const UserAccount(uid: uid, virtualBalance: 100, consecutiveLosses: 0),
          existingPosition: null,
          coinSymbol: 'BTCUSDT',
          price: 60000,
          quantity: 1,
          now: now,
          orderId: 'order-short-open-4',
        ),
        throwsA(isA<InsufficientBalanceException>()),
      );
    });
  });
}
