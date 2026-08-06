// cloud_firestore's Query/DocumentReference/DocumentSnapshot are `sealed`,
// which is an API-evolution guard for the SDK's own subclasses — it doesn't
// prevent mocktail's `implements` pattern from working, only trips the
// analyzer's sealed-class lint.
// ignore_for_file: subtype_of_sealed_class
import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:crypto_paper_trader/domain/entities/order.dart';
import 'package:crypto_paper_trader/domain/entities/user_account.dart';
import 'package:crypto_paper_trader/domain/usecases/execute_trade.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockFirebaseFirestore extends Mock implements FirebaseFirestore {}

class MockCollectionReference extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

class MockDocumentReference extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

class MockDocumentSnapshot extends Mock
    implements DocumentSnapshot<Map<String, dynamic>> {}

class MockTransaction extends Mock implements Transaction {}

class _FakeDocumentReference extends Fake
    implements DocumentReference<Map<String, dynamic>> {}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeDocumentReference());
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(const Duration());
  });

  const uid = 'user-1';
  const symbol = 'BTCUSDT';

  late MockFirebaseFirestore firestore;
  late MockCollectionReference usersCollection;
  late MockDocumentReference userDoc;
  late MockCollectionReference portfolioCollection;
  late MockDocumentReference portfolioDoc;
  late MockCollectionReference ordersCollection;
  late MockDocumentReference newOrderDoc;
  late MockTransaction transaction;
  late MockDocumentSnapshot userSnapshot;
  late MockDocumentSnapshot portfolioSnapshot;

  late ExecuteTradeUseCase engine;
  final fixedNow = DateTime.utc(2026, 1, 1, 12);

  Map<String, dynamic> accountDoc({
    double virtualBalance = 100000,
    int consecutiveLosses = 0,
    DateTime? buyLockedUntil,
  }) =>
      {
        'virtual_balance': virtualBalance,
        'consecutive_losses': consecutiveLosses,
        'buy_locked_until':
            buyLockedUntil == null ? null : Timestamp.fromDate(buyLockedUntil),
      };

  Map<String, dynamic> positionDoc({
    required double totalQuantity,
    required double avgBuyPrice,
  }) =>
      {'total_quantity': totalQuantity, 'avg_buy_price': avgBuyPrice};

  setUp(() {
    firestore = MockFirebaseFirestore();
    usersCollection = MockCollectionReference();
    userDoc = MockDocumentReference();
    portfolioCollection = MockCollectionReference();
    portfolioDoc = MockDocumentReference();
    ordersCollection = MockCollectionReference();
    newOrderDoc = MockDocumentReference();
    transaction = MockTransaction();
    userSnapshot = MockDocumentSnapshot();
    portfolioSnapshot = MockDocumentSnapshot();

    when(() => firestore.collection('users')).thenReturn(usersCollection);
    when(() => usersCollection.doc(uid)).thenReturn(userDoc);
    when(() => userDoc.id).thenReturn(uid);
    when(() => userDoc.collection('portfolio')).thenReturn(portfolioCollection);
    when(() => portfolioCollection.doc(any())).thenReturn(portfolioDoc);
    when(() => portfolioDoc.id).thenReturn(symbol);
    when(() => userDoc.collection('orders')).thenReturn(ordersCollection);
    when(() => ordersCollection.doc()).thenReturn(newOrderDoc);
    when(() => newOrderDoc.id).thenReturn('order-1');

    when(() => firestore.runTransaction<Order>(
          any(),
          timeout: any(named: 'timeout'),
          maxAttempts: any(named: 'maxAttempts'),
        )).thenAnswer((invocation) async {
      final handler = invocation.positionalArguments[0]
          as Future<Order> Function(Transaction);
      return handler(transaction);
    });

    when(() => userSnapshot.id).thenReturn(uid);
    when(() => portfolioSnapshot.id).thenReturn(symbol);
    when(() => transaction.get(userDoc))
        .thenAnswer((_) async => userSnapshot);
    when(() => transaction.get(portfolioDoc))
        .thenAnswer((_) async => portfolioSnapshot);
    when(() => transaction.set<Map<String, dynamic>>(any(), any()))
        .thenReturn(transaction);
    when(() => transaction.update(any(), any())).thenReturn(transaction);
    when(() => transaction.delete(any())).thenReturn(transaction);

    engine = ExecuteTradeUseCase(firestore, uid: uid, clock: () => fixedNow);
  });

  group('buy', () {
    test('successful buy deducts balance and opens a new position', () async {
      when(() => userSnapshot.data()).thenReturn(accountDoc());
      when(() => portfolioSnapshot.exists).thenReturn(false);
      when(() => portfolioSnapshot.data()).thenReturn(null);

      final order = await engine.buy(
        coinSymbol: symbol,
        price: 60000,
        quantity: 0.1,
      );

      expect(order.orderType, OrderType.buy);
      expect(order.coinSymbol, symbol);
      expect(order.price, 60000);
      expect(order.quantity, 0.1);
      expect(order.realizedPnl, isNull);
      expect(order.timestamp, fixedNow);

      final positionWrite = verify(
        () => transaction.set<Map<String, dynamic>>(portfolioDoc, captureAny()),
      ).captured.single as Map<String, dynamic>;
      expect(positionWrite['total_quantity'], 0.1);
      expect(positionWrite['avg_buy_price'], 60000);

      final accountUpdate = verify(
        () => transaction.update(userDoc, captureAny()),
      ).captured.single as Map<String, dynamic>;
      expect(accountUpdate['virtual_balance'], 100000 - 6000);

      verify(() => transaction.set<Map<String, dynamic>>(newOrderDoc, any())).called(1);
    });

    test('folds a second buy into a weighted-average price', () async {
      when(() => userSnapshot.data()).thenReturn(accountDoc());
      when(() => portfolioSnapshot.exists).thenReturn(true);
      when(() => portfolioSnapshot.data()).thenReturn(
        positionDoc(totalQuantity: 1, avgBuyPrice: 50000),
      );

      await engine.buy(coinSymbol: symbol, price: 60000, quantity: 1);

      final positionWrite = verify(
        () => transaction.set<Map<String, dynamic>>(portfolioDoc, captureAny()),
      ).captured.single as Map<String, dynamic>;
      // (1*50000 + 1*60000) / 2 == 55000
      expect(positionWrite['total_quantity'], 2);
      expect(positionWrite['avg_buy_price'], 55000);
    });

    test('rejects a buy that costs more than the available balance',
        () async {
      when(() => userSnapshot.data()).thenReturn(accountDoc(virtualBalance: 100));
      when(() => portfolioSnapshot.exists).thenReturn(false);

      await expectLater(
        engine.buy(coinSymbol: symbol, price: 60000, quantity: 1),
        throwsA(isA<InsufficientBalanceException>()),
      );
    });

    test('rejects a buy while the revenge-trade lock is active', () async {
      when(() => userSnapshot.data()).thenReturn(
        accountDoc(buyLockedUntil: fixedNow.add(const Duration(minutes: 10))),
      );

      await expectLater(
        engine.buy(coinSymbol: symbol, price: 60000, quantity: 0.1),
        throwsA(isA<TradingLockedException>()),
      );
      verifyNever(() => transaction.update(any(), any()));
    });

    test('allows a buy once the lock has expired', () async {
      when(() => userSnapshot.data()).thenReturn(
        accountDoc(
          buyLockedUntil: fixedNow.subtract(const Duration(minutes: 1)),
        ),
      );
      when(() => portfolioSnapshot.exists).thenReturn(false);

      final order = await engine.buy(
        coinSymbol: symbol,
        price: 60000,
        quantity: 0.1,
      );
      expect(order.orderType, OrderType.buy);
    });
  });

  group('sell', () {
    test('successful sell books realized P&L and credits proceeds',
        () async {
      when(() => userSnapshot.data()).thenReturn(accountDoc());
      when(() => portfolioSnapshot.exists).thenReturn(true);
      when(() => portfolioSnapshot.data()).thenReturn(
        positionDoc(totalQuantity: 1, avgBuyPrice: 50000),
      );

      final order = await engine.sell(
        coinSymbol: symbol,
        price: 60000,
        quantity: 0.5,
      );

      expect(order.orderType, OrderType.sell);
      expect(order.realizedPnl, 5000); // (60000-50000)*0.5

      final accountUpdate = verify(
        () => transaction.update(userDoc, captureAny()),
      ).captured.single as Map<String, dynamic>;
      expect(accountUpdate['virtual_balance'], 100000 + 30000);
      expect(accountUpdate['consecutive_losses'], 0);

      final positionWrite = verify(
        () => transaction.set<Map<String, dynamic>>(portfolioDoc, captureAny()),
      ).captured.single as Map<String, dynamic>;
      expect(positionWrite['total_quantity'], 0.5);
      expect(positionWrite['avg_buy_price'], 50000); // unchanged on sell
    });

    test('fully closing a position deletes the portfolio doc', () async {
      when(() => userSnapshot.data()).thenReturn(accountDoc());
      when(() => portfolioSnapshot.exists).thenReturn(true);
      when(() => portfolioSnapshot.data()).thenReturn(
        positionDoc(totalQuantity: 1, avgBuyPrice: 50000),
      );

      await engine.sell(coinSymbol: symbol, price: 60000, quantity: 1);

      verify(() => transaction.delete(portfolioDoc)).called(1);
      verifyNever(() => transaction.set<Map<String, dynamic>>(portfolioDoc, any()));
    });

    test('rejects selling more than is held', () async {
      when(() => userSnapshot.data()).thenReturn(accountDoc());
      when(() => portfolioSnapshot.exists).thenReturn(true);
      when(() => portfolioSnapshot.data()).thenReturn(
        positionDoc(totalQuantity: 0.2, avgBuyPrice: 50000),
      );

      await expectLater(
        engine.sell(coinSymbol: symbol, price: 60000, quantity: 1),
        throwsA(isA<InsufficientHoldingsException>()),
      );
    });

    test('rejects selling a coin with no position at all', () async {
      when(() => userSnapshot.data()).thenReturn(accountDoc());
      when(() => portfolioSnapshot.exists).thenReturn(false);
      when(() => portfolioSnapshot.data()).thenReturn(null);

      await expectLater(
        engine.sell(coinSymbol: symbol, price: 60000, quantity: 0.1),
        throwsA(isA<InsufficientHoldingsException>()),
      );
    });

    test('a losing sell increments the consecutive-loss streak', () async {
      when(() => userSnapshot.data())
          .thenReturn(accountDoc(consecutiveLosses: 1));
      when(() => portfolioSnapshot.exists).thenReturn(true);
      when(() => portfolioSnapshot.data()).thenReturn(
        positionDoc(totalQuantity: 1, avgBuyPrice: 50000),
      );

      final order = await engine.sell(
        coinSymbol: symbol,
        price: 40000, // below avg buy price -> loss
        quantity: 1,
      );

      expect(order.realizedPnl, lessThan(0));
      final accountUpdate = verify(
        () => transaction.update(userDoc, captureAny()),
      ).captured.single as Map<String, dynamic>;
      expect(accountUpdate['consecutive_losses'], 2);
      expect(accountUpdate['buy_locked_until'], isNull);
    });

    test(
        'the 3rd consecutive losing sell arms a 30-minute buy lock',
        () async {
      when(() => userSnapshot.data())
          .thenReturn(accountDoc(consecutiveLosses: 2));
      when(() => portfolioSnapshot.exists).thenReturn(true);
      when(() => portfolioSnapshot.data()).thenReturn(
        positionDoc(totalQuantity: 1, avgBuyPrice: 50000),
      );

      await engine.sell(coinSymbol: symbol, price: 40000, quantity: 1);

      final accountUpdate = verify(
        () => transaction.update(userDoc, captureAny()),
      ).captured.single as Map<String, dynamic>;
      expect(accountUpdate['consecutive_losses'], 3);
      final lockedUntil = accountUpdate['buy_locked_until'] as Timestamp;
      expect(
        lockedUntil.toDate().toUtc(),
        fixedNow.add(UserAccount.lockDuration),
      );
    });

    test('a profitable sell resets the consecutive-loss streak to zero',
        () async {
      when(() => userSnapshot.data())
          .thenReturn(accountDoc(consecutiveLosses: 2));
      when(() => portfolioSnapshot.exists).thenReturn(true);
      when(() => portfolioSnapshot.data()).thenReturn(
        positionDoc(totalQuantity: 1, avgBuyPrice: 50000),
      );

      await engine.sell(coinSymbol: symbol, price: 60000, quantity: 1);

      final accountUpdate = verify(
        () => transaction.update(userDoc, captureAny()),
      ).captured.single as Map<String, dynamic>;
      expect(accountUpdate['consecutive_losses'], 0);
    });
  });

  group('validation', () {
    test('rejects a zero or negative price', () {
      expect(
        () => engine.buy(coinSymbol: symbol, price: 0, quantity: 1),
        throwsA(isA<InvalidTradeException>()),
      );
    });

    test('rejects a zero or negative quantity', () {
      expect(
        () => engine.sell(coinSymbol: symbol, price: 100, quantity: -1),
        throwsA(isA<InvalidTradeException>()),
      );
    });
  });
}
