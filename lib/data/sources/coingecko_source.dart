import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Thrown when a fresh batch couldn't be fetched and there's no cached
/// fallback to serve instead.
class CoinGeckoException implements Exception {
  CoinGeckoException(this.message);
  final String message;

  @override
  String toString() => 'CoinGeckoException: $message';
}

/// One coin's price snapshot from `/coins/markets` — includes a 7-day
/// sparkline, which is the actual reason this screen uses CoinGecko rather
/// than reusing Binance's `/ticker/24hr` (see binance_rest_service.dart's
/// `fetch24hrTickers`): Binance doesn't offer sparkline data in that
/// endpoint at all.
class CoinMarketData {
  const CoinMarketData({
    required this.coingeckoId,
    required this.symbol,
    required this.currentPriceUsd,
    required this.priceChangePercent24h,
    required this.sparkline7d,
  });

  factory CoinMarketData.fromJson(Map<String, dynamic> json) {
    final sparklineRaw =
        (json['sparkline_in_7d'] as Map<String, dynamic>?)?['price'] as List<dynamic>?;
    return CoinMarketData(
      coingeckoId: json['id'] as String,
      symbol: (json['symbol'] as String).toUpperCase(),
      currentPriceUsd: (json['current_price'] as num?)?.toDouble() ?? 0,
      priceChangePercent24h: (json['price_change_percentage_24h'] as num?)?.toDouble() ?? 0,
      sparkline7d: sparklineRaw?.map((e) => (e as num).toDouble()).toList(growable: false) ??
          const [],
    );
  }

  final String coingeckoId;

  /// Ticker symbol as CoinGecko reports it, e.g. `'BTC'` — uppercased to
  /// match [SupportedCoin.baseAsset]'s convention.
  final String symbol;
  final double currentPriceUsd;
  final double priceChangePercent24h;
  final List<double> sparkline7d;
}

/// A batch fetch result, tagged with whether it's fresh or a stale cache
/// fallback served after a failed refresh (same pattern as
/// currency_converter.dart's ExchangeRate) — callers show a "stale"
/// indicator rather than silently presenting old prices as current.
class CoinMarketSnapshot {
  const CoinMarketSnapshot({required this.coins, required this.fetchedAt, required this.isStale});

  final List<CoinMarketData> coins;
  final DateTime fetchedAt;
  final bool isStale;
}

/// Fetches current price, 24h % change, and a 7-day sparkline for several
/// coins in ONE request via CoinGecko's `/coins/markets` — not one request
/// per coin, which would burn through CoinGecko's free-tier rate limit in
/// seconds for a 15-coin watchlist. Cached for 45s (comfortably above
/// CoinGecko's free-tier per-minute limit even if several screens poll it,
/// well under a minute so the Markets screen still feels live).
class CoinGeckoSource {
  CoinGeckoSource({
    http.Client? client,
    this.baseUrl = 'https://api.coingecko.com/api/v3',
    this.timeout = const Duration(seconds: 10),
    this.cacheTtl = const Duration(seconds: 45),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;
  final Duration timeout;
  final Duration cacheTtl;

  CoinMarketSnapshot? _cached;

  Future<CoinMarketSnapshot> fetchMarkets({required List<String> coingeckoIds}) async {
    final cached = _cached;
    if (cached != null && DateTime.now().difference(cached.fetchedAt) < cacheTtl) {
      return cached;
    }

    try {
      final uri = Uri.parse('$baseUrl/coins/markets').replace(queryParameters: {
        'vs_currency': 'usd',
        'ids': coingeckoIds.join(','),
        'sparkline': 'true',
        'price_change_percentage': '24h',
      });
      final response = await _client.get(uri).timeout(timeout);
      if (response.statusCode != 200) {
        throw CoinGeckoException(
          'GET ${uri.path} returned ${response.statusCode}: ${response.body}',
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        throw CoinGeckoException('Unexpected /coins/markets payload: $decoded');
      }

      final coins = decoded
          .map((e) => CoinMarketData.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
      final snapshot = CoinMarketSnapshot(coins: coins, fetchedAt: DateTime.now(), isStale: false);
      _cached = snapshot;
      return snapshot;
    } catch (e) {
      debugPrint('[CoinGeckoSource] fetchMarkets failed: $e');
      if (cached != null) {
        return CoinMarketSnapshot(coins: cached.coins, fetchedAt: cached.fetchedAt, isStale: true);
      }
      rethrow;
    }
  }

  void dispose() => _client.close();
}
