import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto_paper_trader/domain/usecases/add_trade_rationale.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

class MockHttpsCallable extends Mock implements HttpsCallable {}

class MockHttpsCallableResult extends Mock implements HttpsCallableResult<Map<String, dynamic>> {}

void main() {
  group('AddTradeRationaleUseCase client-side guards', () {
    // These two cases throw before ever touching FirebaseFunctions, so an
    // unstubbed mock (which would throw if actually invoked) proves the
    // guard clause runs first.
    test('rejects empty text without calling the backend', () {
      final useCase = AddTradeRationaleUseCase(functions: MockFirebaseFunctions());
      expect(
        () => useCase(orderId: 'order-1', text: '   '),
        throwsA(isA<TradeRationaleException>()),
      );
    });

    test('rejects text over 280 characters without calling the backend', () {
      final useCase = AddTradeRationaleUseCase(functions: MockFirebaseFunctions());
      expect(
        () => useCase(orderId: 'order-1', text: 'x' * 281),
        throwsA(isA<TradeRationaleException>()),
      );
    });
  });

  group('AddTradeRationaleUseCase call', () {
    late MockFirebaseFunctions functions;
    late MockHttpsCallable callable;

    setUp(() {
      functions = MockFirebaseFunctions();
      callable = MockHttpsCallable();
      when(() => functions.httpsCallable('addTradeRationale')).thenReturn(callable);
    });

    test('trims text, invokes the callable, and returns the flagged result', () async {
      final result = MockHttpsCallableResult();
      when(() => result.data).thenReturn({'flagged': true});
      when(() => callable.call<Map<String, dynamic>>(any())).thenAnswer((_) async => result);

      final useCase = AddTradeRationaleUseCase(functions: functions);
      final flagged = await useCase(orderId: 'order-1', text: '  Took profit early.  ');

      expect(flagged, isTrue);
      final captured = verify(() => callable.call<Map<String, dynamic>>(captureAny())).captured;
      expect(captured.single, {'orderId': 'order-1', 'text': 'Took profit early.'});
    });

    test('maps FirebaseFunctionsException to TradeRationaleException', () async {
      when(() => callable.call<Map<String, dynamic>>(any())).thenThrow(
        FirebaseFunctionsException(message: 'not found', code: 'not-found'),
      );

      final useCase = AddTradeRationaleUseCase(functions: functions);
      expect(
        () => useCase(orderId: 'order-1', text: 'Note'),
        throwsA(isA<TradeRationaleException>()),
      );
    });
  });
}
