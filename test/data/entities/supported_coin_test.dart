import 'package:flutter_test/flutter_test.dart';

import 'package:crypto_paper_trader/data/entities/supported_coin.dart';

void main() {
  group('supportedCoins', () {
    test('has no duplicate symbols', () {
      final symbols = supportedCoins.map((c) => c.symbol).toSet();
      expect(symbols.length, supportedCoins.length);
    });

    test('includes BTCUSDT as the original single-coin default', () {
      expect(supportedCoins.any((c) => c.symbol == 'BTCUSDT'), isTrue);
    });

    test('has a non-empty, unique CoinGecko id for every coin', () {
      final ids = supportedCoins.map((c) => c.coingeckoId).toList();
      expect(ids, everyElement(isNotEmpty));
      expect(ids.toSet().length, ids.length);
    });
  });

  group('coinForSymbol', () {
    test('returns the curated entry for a known symbol', () {
      final coin = coinForSymbol('ETHUSDT');
      expect(coin.baseAsset, 'ETH');
      expect(coin.displayName, 'Ethereum');
    });

    test('falls back to a synthetic entry for an unknown symbol', () {
      final coin = coinForSymbol('SHIBUSDT');
      expect(coin.symbol, 'SHIBUSDT');
      expect(coin.baseAsset, 'SHIBUSDT');
      expect(coin.displayName, 'SHIBUSDT');
    });
  });
}
