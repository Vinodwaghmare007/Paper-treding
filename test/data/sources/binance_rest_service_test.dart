import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:crypto_paper_trader/data/sources/binance_rest_service.dart';

void main() {
  group('BinanceRestService.fetchPrices', () {
    test('parses a batch of symbol/price pairs', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/v3/ticker/price');
        expect(request.url.queryParameters['symbols'], '["BTCUSDT","ETHUSDT"]');
        return http.Response(
          '[{"symbol":"BTCUSDT","price":"65000.12"},{"symbol":"ETHUSDT","price":"3400.50"}]',
          200,
        );
      });

      final service = BinanceRestService(client: client);
      final prices = await service.fetchPrices(symbols: ['BTCUSDT', 'ETHUSDT']);

      expect(prices, {'BTCUSDT': 65000.12, 'ETHUSDT': 3400.50});
    });

    test('returns an empty map without a request for an empty symbol list', () async {
      var requestCount = 0;
      final client = MockClient((request) async {
        requestCount++;
        return http.Response('[]', 200);
      });

      final service = BinanceRestService(client: client);
      final prices = await service.fetchPrices(symbols: const []);

      expect(prices, isEmpty);
      expect(requestCount, 0);
    });

    test('returns an empty map (not a throw) on a non-200 response', () async {
      final client = MockClient((request) async => http.Response('bad request', 400));
      final service = BinanceRestService(client: client);

      final prices = await service.fetchPrices(symbols: ['BTCUSDT']);

      expect(prices, isEmpty);
    });
  });

  group('BinanceRestService.fetch24hrTickers', () {
    test('parses last price and open price into TickerSnapshots', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/v3/ticker/24hr');
        expect(request.url.queryParameters['type'], 'MINI');
        return http.Response(
          '[{"symbol":"BTCUSDT","lastPrice":"65000.00","openPrice":"64000.00"}]',
          200,
        );
      });

      final service = BinanceRestService(client: client);
      final snapshots = await service.fetch24hrTickers(symbols: ['BTCUSDT']);

      expect(snapshots, hasLength(1));
      expect(snapshots.single.symbol, 'BTCUSDT');
      expect(snapshots.single.lastPrice, 65000.00);
      expect(snapshots.single.openPrice, 64000.00);
    });

    test('returns an empty list (not a throw) on a network error', () async {
      final client = MockClient((request) async => throw Exception('boom'));
      final service = BinanceRestService(client: client);

      final snapshots = await service.fetch24hrTickers(symbols: ['BTCUSDT']);

      expect(snapshots, isEmpty);
    });
  });

  group('TickerSnapshot.changePercent24h', () {
    test('computes percent change from open vs last price', () {
      const snapshot = TickerSnapshot(symbol: 'BTCUSDT', lastPrice: 65000, openPrice: 64000);
      expect(snapshot.changePercent24h, closeTo(1.5625, 0.0001));
    });

    test('is zero (not NaN/infinite) when openPrice is zero', () {
      const snapshot = TickerSnapshot(symbol: 'BTCUSDT', lastPrice: 65000, openPrice: 0);
      expect(snapshot.changePercent24h, 0);
    });
  });
}
