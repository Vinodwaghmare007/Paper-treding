import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/kline_tick.dart';

/// Thrown when historical klines could not be fetched after all retries.
class BinanceRestException implements Exception {
  BinanceRestException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'BinanceRestException($statusCode): $message';
}

/// Fetches historical candles from the Binance spot REST API.
class BinanceRestService {
  BinanceRestService({
    http.Client? client,
    this.baseUrl = 'https://api.binance.com',
    this.timeout = const Duration(seconds: 10),
    this.maxAttempts = 3,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;
  final Duration timeout;
  final int maxAttempts;

  /// GET /api/v3/klines — returns candles oldest-first. The final candle is
  /// the currently forming (unclosed) one.
  Future<List<Candle>> fetchKlines({
    String symbol = 'BTCUSDT',
    String interval = '1m',
    int limit = 500,
  }) async {
    final uri = Uri.parse('$baseUrl/api/v3/klines').replace(
      queryParameters: {
        'symbol': symbol,
        'interval': interval,
        'limit': '$limit',
      },
    );

    Object? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final response = await _client.get(uri).timeout(timeout);
        if (response.statusCode != 200) {
          throw BinanceRestException(
            'GET $uri returned ${response.statusCode}: ${response.body}',
            statusCode: response.statusCode,
          );
        }
        final decoded = jsonDecode(response.body);
        if (decoded is! List) {
          throw BinanceRestException('Unexpected klines payload: $decoded');
        }
        return decoded
            .map((entry) => Candle.fromRestEntry(entry as List<dynamic>))
            .toList(growable: false);
      } on BinanceRestException catch (e) {
        // 4xx means the request itself is wrong — retrying won't help.
        final code = e.statusCode;
        if (code != null && code >= 400 && code < 500 && code != 429) rethrow;
        lastError = e;
      } catch (e) {
        lastError = e;
      }
      if (attempt < maxAttempts) {
        final delay = Duration(milliseconds: 500 * (1 << (attempt - 1)));
        debugPrint(
          '[BinanceREST] attempt $attempt failed ($lastError), '
          'retrying in ${delay.inMilliseconds}ms',
        );
        await Future<void>.delayed(delay);
      }
    }
    throw BinanceRestException(
      'Failed to fetch klines after $maxAttempts attempts: $lastError',
    );
  }

  void dispose() => _client.close();
}
