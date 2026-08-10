import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:crypto_paper_trader/data/sources/currency_converter.dart';

const _sampleBody = '''
{
  "rates": {
    "usd": {"value": 65000.0, "unit": "US Dollar"},
    "inr": {"value": 5460000.0, "unit": "Indian Rupee"}
  }
}
''';

void main() {
  group('CurrencyConverter.fetchUsdToInr', () {
    test('derives USD->INR by dividing the two BTC-denominated rates', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/v3/exchange_rates');
        return http.Response(_sampleBody, 200);
      });

      final converter = CurrencyConverter(client: client);
      final rate = await converter.fetchUsdToInr();

      expect(rate.usdToInr, 84.0);
      expect(rate.isStale, isFalse);
    });

    test('serves cached results within the TTL without a second request', () async {
      var requestCount = 0;
      final client = MockClient((request) async {
        requestCount++;
        return http.Response(_sampleBody, 200);
      });

      final converter = CurrencyConverter(client: client);
      await converter.fetchUsdToInr();
      await converter.fetchUsdToInr();

      expect(requestCount, 1);
    });

    test('falls back to the stale cache on a failed refresh instead of throwing', () async {
      var requestCount = 0;
      final client = MockClient((request) async {
        requestCount++;
        if (requestCount == 1) return http.Response(_sampleBody, 200);
        return http.Response('server error', 500);
      });

      final converter = CurrencyConverter(client: client, cacheTtl: Duration.zero);
      final first = await converter.fetchUsdToInr();
      final second = await converter.fetchUsdToInr();

      expect(first.isStale, isFalse);
      expect(second.isStale, isTrue);
      expect(second.usdToInr, first.usdToInr);
    });

    test('throws when there is no cache and the request fails', () async {
      final client = MockClient((request) async => http.Response('server error', 500));
      final converter = CurrencyConverter(client: client);

      expect(
        () => converter.fetchUsdToInr(),
        throwsA(isA<CurrencyConverterException>()),
      );
    });
  });
}
