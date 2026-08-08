// cloud_firestore's FirebaseFirestore is `sealed` at the SDK level, purely
// as an API-evolution guard — doesn't stop mocktail's `implements` pattern,
// only trips the analyzer's sealed-class lint (same situation as
// execute_trade_test.dart).
// ignore_for_file: subtype_of_sealed_class
import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:crypto_paper_trader/data/models/kline_tick.dart';
import 'package:crypto_paper_trader/domain/entities/order.dart';
import 'package:crypto_paper_trader/domain/entities/portfolio_position.dart';
import 'package:crypto_paper_trader/domain/entities/user_account.dart';
import 'package:crypto_paper_trader/domain/usecases/execute_trade.dart';
import 'package:crypto_paper_trader/features/chart/price_source.dart';
import 'package:crypto_paper_trader/features/portfolio/portfolio_providers.dart';
import 'package:crypto_paper_trader/features/trade/trade_sheet.dart';

class _MockFirebaseFirestore extends Mock implements FirebaseFirestore {}

/// Never actually talks to Firestore — `buy`/`sell` are overridden to throw
/// directly, standing in for what a real `runTransaction()` does when the
/// device can't reach the server: transactions need a live round-trip (see
/// the comment on trade_sheet.dart's FirebaseException handler), so offline
/// surfaces as a thrown FirebaseException, never a queued/deferred write.
class _OfflineExecuteTradeUseCase extends ExecuteTradeUseCase {
  _OfflineExecuteTradeUseCase() : super(_MockFirebaseFirestore(), uid: 'user-1');

  @override
  Future<Order> buy({
    required String coinSymbol,
    required double price,
    required double quantity,
  }) =>
      throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');

  @override
  Future<Order> sell({
    required String coinSymbol,
    required double price,
    required double quantity,
  }) =>
      buy(coinSymbol: coinSymbol, price: price, quantity: quantity);
}

void main() {
  testWidgets(
      'a Firestore FirebaseException (e.g. offline) surfaces a retryable '
      'message instead of an unhandled exception', (tester) async {
    const account =
        UserAccount(uid: 'user-1', virtualBalance: 100000, consecutiveLosses: 0);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountStreamProvider.overrideWith((ref) => Stream.value(account)),
          portfolioStreamProvider
              .overrideWith((ref) => Stream.value(const <PortfolioPosition>[])),
          activeTickProvider.overrideWith((ref) => const Stream<KlineTick>.empty()),
          executeTradeUseCaseProvider.overrideWith((ref) => _OfflineExecuteTradeUseCase()),
        ],
        child: MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () =>
                      showTradeSheet(context, coinSymbol: 'BTCUSDT', currentPrice: 60000),
                  child: const Text('open trade sheet'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open trade sheet'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '0.1');
    await tester.pump();

    // No FlutterError should be recorded — the exception must be caught,
    // not left to propagate as an unhandled Future rejection.
    await tester.tap(find.text('Confirm Buy'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.text("Couldn't reach the server — check your connection and try again."),
      findsOneWidget,
    );
    // The sheet stays open with the trade never recorded as sent — not a
    // silent success.
    expect(find.text('Confirm Buy'), findsOneWidget);
  });
}
