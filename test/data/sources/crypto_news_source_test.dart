import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:crypto_paper_trader/data/sources/crypto_news_source.dart';

const _sampleBody = '''
{
  "results": [
    {
      "id": 111,
      "title": "Bitcoin breaks past resistance",
      "published_at": "2026-08-06T09:30:00Z",
      "url": "https://cryptopanic.com/news/111/bitcoin-breaks-past-resistance",
      "source": {"title": "CoinDesk", "domain": "coindesk.com"}
    },
    {
      "id": 112,
      "title": "Regulators eye stablecoins",
      "published_at": "2026-08-06T08:00:00Z",
      "url": "https://cryptopanic.com/news/112/regulators-eye-stablecoins",
      "source": {"domain": "reuters.com"}
    }
  ]
}
''';

void main() {
  group('CryptoNewsSource.fetchHeadlines', () {
    test('parses title, source name, published time, and url', () async {
      var requestCount = 0;
      final client = MockClient((request) async {
        requestCount++;
        expect(request.url.queryParameters['auth_token'], 'test-token');
        expect(request.url.queryParameters['currencies'], 'BTC');
        return http.Response(_sampleBody, 200);
      });

      final source = CryptoNewsSource(client: client, apiToken: 'test-token');
      final headlines = await source.fetchHeadlines(currency: 'BTC');

      expect(requestCount, 1);
      expect(headlines, hasLength(2));
      expect(headlines[0].id, '111');
      expect(headlines[0].title, 'Bitcoin breaks past resistance');
      expect(headlines[0].sourceName, 'CoinDesk');
      expect(headlines[0].publishedAt, DateTime.utc(2026, 8, 6, 9, 30));
      expect(headlines[0].url,
          Uri.parse('https://cryptopanic.com/news/111/bitcoin-breaks-past-resistance'));

      // Falls back to the domain when source.title is absent.
      expect(headlines[1].sourceName, 'reuters.com');
    });

    test('serves cached results within the TTL without a second request', () async {
      var requestCount = 0;
      final client = MockClient((request) async {
        requestCount++;
        return http.Response(_sampleBody, 200);
      });

      final source = CryptoNewsSource(client: client, apiToken: 'test-token');
      await source.fetchHeadlines(currency: 'BTC');
      await source.fetchHeadlines(currency: 'BTC');

      expect(requestCount, 1);
    });

    test('throws CryptoNewsException on a non-200 response', () async {
      final client = MockClient((request) async => http.Response('server error', 500));
      final source = CryptoNewsSource(client: client, apiToken: 'test-token');

      expect(
        () => source.fetchHeadlines(currency: 'BTC'),
        throwsA(isA<CryptoNewsException>()),
      );
    });

    test('throws CryptoNewsException when no API token is configured', () async {
      final client = MockClient((request) async => http.Response(_sampleBody, 200));
      final source = CryptoNewsSource(client: client, apiToken: '');

      expect(
        () => source.fetchHeadlines(currency: 'BTC'),
        throwsA(isA<CryptoNewsException>()),
      );
    });
  });
}
