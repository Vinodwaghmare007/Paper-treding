import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Thrown when a fresh rate couldn't be fetched and there's no cached
/// fallback to serve instead.
class CurrencyConverterException implements Exception {
  CurrencyConverterException(this.message);
  final String message;

  @override
  String toString() => 'CurrencyConverterException: $message';
}

/// A USD→INR rate, tagged with whether it's fresh or a stale cache fallback
/// served after a failed refresh — callers (currency_preference_provider
/// .dart) use [isStale] to show a "stale" indicator rather than silently
/// presenting an old rate as current.
class ExchangeRate {
  const ExchangeRate({required this.usdToInr, required this.fetchedAt, required this.isStale});

  final double usdToInr;
  final DateTime fetchedAt;
  final bool isStale;
}

/// Fetches the USD→INR exchange rate from CoinGecko's `/exchange_rates`
/// endpoint rather than a separate forex API — one less external
/// dependency, and no API key required. That endpoint reports every
/// supported currency's value against 1 BTC; dividing the INR rate by the
/// USD rate cancels out BTC's own price and leaves a plain USD→INR forex
/// rate. Cached for 1 hour (matches the spec: forex doesn't need
/// minute-level freshness), and on a failed refresh this keeps serving the
/// last-known rate (marked [ExchangeRate.isStale]) rather than blocking or
/// crashing a screen that just wants to show a price in INR.
class CurrencyConverter {
  CurrencyConverter({
    http.Client? client,
    this.baseUrl = 'https://api.coingecko.com/api/v3',
    this.timeout = const Duration(seconds: 10),
    this.cacheTtl = const Duration(hours: 1),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;
  final Duration timeout;
  final Duration cacheTtl;

  ExchangeRate? _cached;

  Future<ExchangeRate> fetchUsdToInr() async {
    final cached = _cached;
    if (cached != null && DateTime.now().difference(cached.fetchedAt) < cacheTtl) {
      return cached;
    }

    try {
      final uri = Uri.parse('$baseUrl/exchange_rates');
      final response = await _client.get(uri).timeout(timeout);
      if (response.statusCode != 200) {
        throw CurrencyConverterException(
          'GET $uri returned ${response.statusCode}: ${response.body}',
        );
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final rates = decoded['rates'] as Map<String, dynamic>;
      final usdPerBtc = (rates['usd'] as Map<String, dynamic>)['value'] as num;
      final inrPerBtc = (rates['inr'] as Map<String, dynamic>)['value'] as num;
      if (usdPerBtc == 0) {
        throw CurrencyConverterException('CoinGecko reported a zero USD/BTC rate');
      }

      final rate = ExchangeRate(
        usdToInr: inrPerBtc / usdPerBtc,
        fetchedAt: DateTime.now(),
        isStale: false,
      );
      _cached = rate;
      return rate;
    } catch (e) {
      debugPrint('[CurrencyConverter] fetch failed: $e');
      if (cached != null) {
        return ExchangeRate(usdToInr: cached.usdToInr, fetchedAt: cached.fetchedAt, isStale: true);
      }
      rethrow;
    }
  }

  void dispose() => _client.close();
}
