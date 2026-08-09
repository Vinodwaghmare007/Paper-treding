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

  /// GET /api/v3/klines — returns candles oldest-first. With no
  /// [startTimeMs]/[endTimeMs], the final candle is the currently forming
  /// (unclosed) one; a bounded historical window is fully closed candles.
  Future<List<Candle>> fetchKlines({
    String symbol = 'BTCUSDT',
    String interval = '1m',
    int limit = 500,
    int? startTimeMs,
    int? endTimeMs,
  }) async {
    final uri = Uri.parse('$baseUrl/api/v3/klines').replace(
      queryParameters: {
        'symbol': symbol,
        'interval': interval,
        'limit': '$limit',
        if (startTimeMs != null) 'startTime': '$startTimeMs',
        if (endTimeMs != null) 'endTime': '$endTimeMs',
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

  /// Fetches every candle from [start] up to [end], paginating in
  /// Binance's max-1000-per-request chunks. Backtesting "months of 1m
  /// data" can mean hundreds of thousands of candles and dozens of
  /// requests, so this waits [requestGap] between pages to stay well clear
  /// of Binance's REST rate limits rather than firing them back-to-back.
  Future<List<Candle>> fetchKlinesRange({
    required String symbol,
    required String interval,
    required DateTime start,
    required DateTime end,
    Duration requestGap = const Duration(milliseconds: 250),
    void Function(int fetchedCandles)? onProgress,
  }) async {
    final intervalMs = intervalToMilliseconds(interval);
    final endMs = end.toUtc().millisecondsSinceEpoch;
    var cursorMs = start.toUtc().millisecondsSinceEpoch;
    final candles = <Candle>[];

    while (cursorMs < endMs) {
      final batch = await fetchKlines(
        symbol: symbol,
        interval: interval,
        limit: 1000,
        startTimeMs: cursorMs,
        endTimeMs: endMs,
      );
      if (batch.isEmpty) break;

      candles.addAll(batch);
      onProgress?.call(candles.length);

      final lastOpenTimeMs = batch.last.openTimeMs;
      final nextCursorMs = lastOpenTimeMs + intervalMs;
      // Binance echoing the same last candle back would otherwise spin
      // forever; a cursor that fails to advance means there's nothing more.
      if (nextCursorMs <= cursorMs) break;
      cursorMs = nextCursorMs;

      if (batch.length < 1000) break; // short page == reached the end
      await Future<void>.delayed(requestGap);
    }
    return candles;
  }

  /// GET /api/v3/ticker/price for several symbols at once — last traded
  /// price only, no 24h stats. Used to keep portfolio holdings priced live
  /// even for coins that aren't the one currently open on the chart (which
  /// already gets its price for free from the WebSocket tick stream).
  ///
  /// Binance rejects the whole batch if any [symbols] entry is invalid, so
  /// a bad/delisted symbol here fails every symbol's price, not just its
  /// own — this returns an empty map on any error rather than throwing, so
  /// callers can keep showing their last-known price instead of the whole
  /// portfolio screen erroring out.
  Future<Map<String, double>> fetchPrices({required List<String> symbols}) async {
    if (symbols.isEmpty) return const {};
    final uri = Uri.parse('$baseUrl/api/v3/ticker/price').replace(
      queryParameters: {'symbols': jsonEncode(symbols)},
    );
    try {
      final response = await _client.get(uri).timeout(timeout);
      if (response.statusCode != 200) {
        debugPrint('[BinanceREST] fetchPrices ${response.statusCode}: ${response.body}');
        return const {};
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! List) return const {};
      return {
        for (final entry in decoded)
          (entry as Map<String, dynamic>)['symbol'] as String:
              double.parse(entry['price'] as String),
      };
    } catch (e) {
      debugPrint('[BinanceREST] fetchPrices failed: $e');
      return const {};
    }
  }

  /// GET /api/v3/ticker/24hr for several symbols at once — last price plus
  /// the rolling 24h open, for a Markets/watchlist-style list. Same
  /// whole-batch-fails-together caveat as [fetchPrices]; returns an empty
  /// list on any error.
  Future<List<TickerSnapshot>> fetch24hrTickers({required List<String> symbols}) async {
    if (symbols.isEmpty) return const [];
    final uri = Uri.parse('$baseUrl/api/v3/ticker/24hr').replace(
      queryParameters: {'symbols': jsonEncode(symbols), 'type': 'MINI'},
    );
    try {
      final response = await _client.get(uri).timeout(timeout);
      if (response.statusCode != 200) {
        debugPrint('[BinanceREST] fetch24hrTickers ${response.statusCode}: ${response.body}');
        return const [];
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! List) return const [];
      return decoded
          .map((entry) => TickerSnapshot.fromJson(entry as Map<String, dynamic>))
          .toList(growable: false);
    } catch (e) {
      debugPrint('[BinanceREST] fetch24hrTickers failed: $e');
      return const [];
    }
  }

  void dispose() => _client.close();
}

/// One symbol's last price and rolling-24h open, from `/api/v3/ticker/24hr`
/// (`type=MINI`) — the percent change is computed locally from these two
/// rather than trusting Binance's own `priceChangePercent` field, which
/// `type=MINI` doesn't even return.
class TickerSnapshot {
  const TickerSnapshot({
    required this.symbol,
    required this.lastPrice,
    required this.openPrice,
  });

  factory TickerSnapshot.fromJson(Map<String, dynamic> json) => TickerSnapshot(
        symbol: json['symbol'] as String,
        lastPrice: double.parse(json['lastPrice'] as String),
        openPrice: double.parse(json['openPrice'] as String),
      );

  final String symbol;
  final double lastPrice;
  final double openPrice;

  double get changePercent24h =>
      openPrice == 0 ? 0 : (lastPrice - openPrice) / openPrice * 100;
}

const _intervalMillis = {
  '1m': 60000, '3m': 180000, '5m': 300000, '15m': 900000, '30m': 1800000,
  '1h': 3600000, '2h': 7200000, '4h': 14400000, '6h': 21600000,
  '8h': 28800000, '12h': 43200000,
  '1d': 86400000, '3d': 259200000, '1w': 604800000,
};

int intervalToMilliseconds(String interval) {
  final ms = _intervalMillis[interval];
  if (ms == null) throw ArgumentError.value(interval, 'interval', 'Unknown interval');
  return ms;
}
