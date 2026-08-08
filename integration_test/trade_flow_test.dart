// Exercises ExecuteTradeUseCase against a REAL Firestore (+ Auth) emulator
// instance — the mocktail-based test/domain/usecases/execute_trade_test.dart
// verifies the *logic* against a scripted fake, but can't verify actual
// Firestore transaction semantics (optimistic-concurrency retries, security
// rule enforcement) the way a real backend can. This is exactly the kind of
// test the mock can't replace.
//
// HOW TO RUN (this sandbox has no Android/iOS device or browser driver
// wired up, so this file is written and reviewed but not executed here):
//
//   1. From the repo root, start the Firestore + Auth emulators:
//        cd functions && npx firebase emulators:start --only firestore,auth --project demo-test
//   2. With a device/emulator connected (or `flutter test -d chrome` once
//      web support + chromedriver are set up):
//        flutter test integration_test/trade_flow_test.dart -d <device-id>
//
// Uses a `demo-` prefixed project id and fake FirebaseOptions on purpose —
// the Firebase emulator suite treats any `demo-*` project as a sandboxed,
// no-real-credentials-needed project, so this test never touches a real
// Firebase project and needs no google-services.json to run in CI.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:crypto_paper_trader/data/firestore/trading_mappers.dart';
import 'package:crypto_paper_trader/domain/usecases/execute_trade.dart';

const _emulatorHost = String.fromEnvironment('FIREBASE_EMULATOR_HOST', defaultValue: 'localhost');

Future<String> _signInFreshTestUser(FirebaseFirestore firestore) async {
  // A fresh anonymous user per test keeps tests independent — no shared
  // mutable state to reset between runs, and no risk of one test's
  // leftover data changing another's outcome.
  final credential = await FirebaseAuth.instance.signInAnonymously();
  final uid = credential.user!.uid;
  await firestore.collection('users').doc(uid).set(UserAccountFirestoreMapping.initialDoc());
  return uid;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: 'demo-api-key',
        appId: '1:000000000000:web:0000000000000000000000',
        messagingSenderId: '000000000000',
        projectId: 'demo-test',
      ),
    );
    FirebaseFirestore.instance.useFirestoreEmulator(_emulatorHost, 8080);
    await FirebaseAuth.instance.useAuthEmulator(_emulatorHost, 9099);
  });

  testWidgets('buy then sell updates the real balance and books P&L', (tester) async {
    final firestore = FirebaseFirestore.instance;
    final uid = await _signInFreshTestUser(firestore);
    final engine = ExecuteTradeUseCase(firestore, uid: uid);

    await engine.buy(coinSymbol: 'BTCUSDT', price: 60000, quantity: 0.1);
    final afterBuy = await firestore.collection('users').doc(uid).get();
    expect((afterBuy.data()!['virtual_balance'] as num).toDouble(), 100000 - 6000);

    final positionAfterBuy =
        await firestore.collection('users').doc(uid).collection('portfolio').doc('BTCUSDT').get();
    expect((positionAfterBuy.data()!['total_quantity'] as num).toDouble(), 0.1);

    final sellOrder = await engine.sell(coinSymbol: 'BTCUSDT', price: 70000, quantity: 0.1);
    expect(sellOrder.realizedPnl, closeTo(1000, 1e-9)); // (70000-60000)*0.1

    final afterSell = await firestore.collection('users').doc(uid).get();
    expect(
      (afterSell.data()!['virtual_balance'] as num).toDouble(),
      closeTo(100000 - 6000 + 7000, 1e-9),
    );

    // Fully closed by the sell -> the position doc should be gone, not a
    // zero-quantity row left behind.
    final positionAfterSell =
        await firestore.collection('users').doc(uid).collection('portfolio').doc('BTCUSDT').get();
    expect(positionAfterSell.exists, isFalse);
  });

  testWidgets(
      'two concurrent buys that together exceed the balance: exactly one '
      'succeeds, the balance never goes negative', (tester) async {
    final firestore = FirebaseFirestore.instance;
    final uid = await _signInFreshTestUser(firestore);
    // Exactly enough for one 0.1 BTC @ 60000 buy, not two.
    await firestore.collection('users').doc(uid).update({'virtual_balance': 6000});
    final engine = ExecuteTradeUseCase(firestore, uid: uid);

    final results = await Future.wait([
      engine
          .buy(coinSymbol: 'BTCUSDT', price: 60000, quantity: 0.1)
          .then((_) => true)
          .catchError((Object e) => false),
      engine
          .buy(coinSymbol: 'BTCUSDT', price: 60000, quantity: 0.1)
          .then((_) => true)
          .catchError((Object e) => false),
    ]);

    // This is the actual bug this test guards against: without Firestore's
    // transaction retry-on-conflict semantics, two racing reads of the same
    // starting balance could both "succeed", overdrawing the account.
    expect(results.where((ok) => ok).length, 1,
        reason: 'exactly one of the two concurrent buys should succeed');

    final finalAccount = await firestore.collection('users').doc(uid).get();
    final finalBalance = (finalAccount.data()!['virtual_balance'] as num).toDouble();
    expect(finalBalance, greaterThanOrEqualTo(0));
    expect(finalBalance, 0); // the one successful buy spent exactly 6000

    final orders = await firestore.collection('users').doc(uid).collection('orders').get();
    expect(orders.docs.length, 1, reason: 'only one order should have been recorded');
  });

  testWidgets('a rejected buy (insufficient balance) throws and leaves state untouched',
      (tester) async {
    final firestore = FirebaseFirestore.instance;
    final uid = await _signInFreshTestUser(firestore);
    final engine = ExecuteTradeUseCase(firestore, uid: uid);

    await expectLater(
      engine.buy(coinSymbol: 'BTCUSDT', price: 1000000, quantity: 1),
      throwsA(isA<InsufficientBalanceException>()),
    );

    final account = await firestore.collection('users').doc(uid).get();
    expect((account.data()!['virtual_balance'] as num).toDouble(), 100000);
    final orders = await firestore.collection('users').doc(uid).collection('orders').get();
    expect(orders.docs, isEmpty);
  });
}
