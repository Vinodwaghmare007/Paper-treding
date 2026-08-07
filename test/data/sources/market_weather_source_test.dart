import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:crypto_paper_trader/data/sources/market_weather_source.dart';

const _sampleBody = '''
{
  "name": "projects/test-project/databases/(default)/documents/public_market_weather/current",
  "fields": {
    "tier": {"stringValue": "Active"},
    "icon_key": {"stringValue": "weather_active"},
    "std_dev_pct": {"doubleValue": 0.62},
    "symbol": {"stringValue": "BTCUSDT"},
    "updated_at": {"timestampValue": "2026-08-06T12:00:00.123456Z"}
  }
}
''';

void main() {
  group('MarketWeatherSource.fetchCurrent', () {
    test('parses tier, icon key, std dev, symbol, and updated time', () async {
      final client = MockClient((request) async {
        expect(
          request.url.toString(),
          'https://firestore.googleapis.com/v1/projects/test-project/databases/'
          '(default)/documents/public_market_weather/current',
        );
        return http.Response(_sampleBody, 200);
      });

      final source = MarketWeatherSource(client: client, projectId: 'test-project');
      final weather = await source.fetchCurrent();

      expect(weather.tier, 'Active');
      expect(weather.iconKey, 'weather_active');
      expect(weather.stdDevPct, 0.62);
      expect(weather.symbol, 'BTCUSDT');
      expect(weather.updatedAt, DateTime.utc(2026, 8, 6, 12, 0, 0, 123, 456));
    });

    test('handles an integerValue std_dev_pct (Firestore\'s REST API '
        'distinguishes int vs double)', () async {
      final client = MockClient((request) async {
        return http.Response(
          _sampleBody.replaceFirst(
            '{"doubleValue": 0.62}',
            '{"integerValue": "1"}',
          ),
          200,
        );
      });

      final source = MarketWeatherSource(client: client, projectId: 'test-project');
      final weather = await source.fetchCurrent();
      expect(weather.stdDevPct, 1.0);
    });

    test('throws MarketWeatherException on a non-200 response', () async {
      final client = MockClient((request) async => http.Response('nope', 404));
      final source = MarketWeatherSource(client: client, projectId: 'test-project');

      expect(
        () => source.fetchCurrent(),
        throwsA(isA<MarketWeatherException>()),
      );
    });

    test('throws MarketWeatherException when no project id is configured', () async {
      final client = MockClient((request) async => http.Response(_sampleBody, 200));
      final source = MarketWeatherSource(client: client, projectId: '');

      expect(
        () => source.fetchCurrent(),
        throwsA(isA<MarketWeatherException>()),
      );
    });
  });
}
