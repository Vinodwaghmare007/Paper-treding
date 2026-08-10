import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:crypto_paper_trader/data/sources/coingecko_source.dart';

const _sampleBody = '''
[
  {
    "id": "bitcoin",
    "symbol": "btc",
    "current_price": 65000.12,
    "price_change_percentage_24h": 2.5,
    "sparkline_in_7d": {"price": [64000.0, 64500.0, 65000.12]}
  },
  {
    "id": "ethereum",
    "symbol": "eth",
    "current_price": 3400.5,
    "price_change_percentage_24h": -1.2,
    "sparkline_in_7d": {"price": [3450.0, 3420.0, 3400.5]}
  }
]
''';

void main() {
  group('CoinGeckoSource.fetchMarkets', () {
    test('batches every id into a single request and parses the response', () async {
      var requestCount = 0;
      final client = MockClient((request) async {
        requestCount++;
        expect(request.url.path, '/api/v3/coins/markets');
        expect(request.url.queryParameters['ids'], 'bitcoin,ethereum');
        expect(request.url.queryParameters['sparkline'], 'true');
        return http.Response(_sampleBody, 200);
      });

      final source = CoinGeckoSource(client: client);
      final snapshot = await source.fetchMarkets(coingeckoIds: ['bitcoin', 'ethereum']);

      expect(requestCount, 1);
      expect(snapshot.isStale, isFalse);
      expect(snapshot.coins, hasLength(2));
      expect(snapshot.coins[0].symbol, 'BTC');
      expect(snapshot.coins[0].currentPriceUsd, 65000.12);
      expect(snapshot.coins[0].priceChangePercent24h, 2.5);
      expect(snapshot.coins[0].sparkline7d, [64000.0, 64500.0, 65000.12]);
    });

    test('serves cached results within the TTL without a second request', () async {
      var requestCount = 0;
      final client = MockClient((request) async {
        requestCount++;
        return http.Response(_sampleBody, 200);
      });

      final source = CoinGeckoSource(client: client);
      await source.fetchMarkets(coingeckoIds: ['bitcoin']);
      await source.fetchMarkets(coingeckoIds: ['bitcoin']);

      expect(requestCount, 1);
    });

    test('falls back to the stale cache on a failed refresh instead of throwing', () async {
      var requestCount = 0;
      final client = MockClient((request) async {
        requestCount++;
        if (requestCount == 1) return http.Response(_sampleBody, 200);
        return http.Response('server error', 500);
      });

      final source = CoinGeckoSource(client: client, cacheTtl: Duration.zero);
      final first = await source.fetchMarkets(coingeckoIds: ['bitcoin']);
      final second = await source.fetchMarkets(coingeckoIds: ['bitcoin']);

      expect(first.isStale, isFalse);
      expect(second.isStale, isTrue);
      expect(second.coins, first.coins);
    });

    test('throws when there is no cache and the request fails', () async {
      final client = MockClient((request) async => http.Response('server error', 500));
      final source = CoinGeckoSource(client: client);

      expect(
        () => source.fetchMarkets(coingeckoIds: ['bitcoin']),
        throwsA(isA<CoinGeckoException>()),
      );
    });
  });
}
