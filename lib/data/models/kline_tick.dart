import 'dart:convert';

/// A single OHLCV candle.
///
/// Used both for candles parsed from the Binance kline WebSocket stream and
/// for historical candles fetched from the REST `/api/v3/klines` endpoint.
class Candle {
  const Candle({
    required this.openTimeMs,
    required this.closeTimeMs,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
  });

  /// Candle open time in milliseconds since epoch (UTC).
  final int openTimeMs;

  /// Candle close time in milliseconds since epoch (UTC).
  final int closeTimeMs;

  final double open;
  final double high;
  final double low;
  final double close;

  /// Base-asset volume traded during this candle.
  final double volume;

  /// Parses one entry of the REST klines response, which is a positional
  /// array: `[openTime, open, high, low, close, volume, closeTime, ...]`.
  ///
  /// Throws [FormatException] if the entry does not match that shape.
  factory Candle.fromRestEntry(List<dynamic> entry) {
    if (entry.length < 7) {
      throw FormatException(
        'REST kline entry has ${entry.length} fields, expected >= 7: $entry',
      );
    }
    return Candle(
      openTimeMs: _asInt(entry[0], 'openTime'),
      open: _asDouble(entry[1], 'open'),
      high: _asDouble(entry[2], 'high'),
      low: _asDouble(entry[3], 'low'),
      close: _asDouble(entry[4], 'close'),
      volume: _asDouble(entry[5], 'volume'),
      closeTimeMs: _asInt(entry[6], 'closeTime'),
    );
  }

  /// Parses one candle as written by generateDailyPuzzle.ts's
  /// `shown_candles`/`reveal_candles` arrays — the Cloud Function writes
  /// the same field names as this class (`openTimeMs`, `closeTimeMs`,
  /// `open`, `high`, `low`, `close`, `volume`), so this is a direct
  /// field-for-field read rather than a REST-shaped positional parse.
  factory Candle.fromMap(Map<String, dynamic> map) {
    return Candle(
      openTimeMs: _asInt(map['openTimeMs'], 'openTimeMs'),
      closeTimeMs: _asInt(map['closeTimeMs'], 'closeTimeMs'),
      open: _asDouble(map['open'], 'open'),
      high: _asDouble(map['high'], 'high'),
      low: _asDouble(map['low'], 'low'),
      close: _asDouble(map['close'], 'close'),
      volume: _asDouble(map['volume'], 'volume'),
    );
  }

  /// Shape expected by the Lightweight Charts bridge in
  /// `assets/charts/tradingview.html`. Lightweight Charts wants UTC time in
  /// whole seconds.
  Map<String, Object> toChartPoint() => {
        'time': openTimeMs ~/ 1000,
        'open': open,
        'high': high,
        'low': low,
        'close': close,
      };

  String toChartJson() => jsonEncode(toChartPoint());

  @override
  String toString() =>
      'Candle(t=$openTimeMs o=$open h=$high l=$low c=$close v=$volume)';
}

/// One event from the Binance `<symbol>@kline_<interval>` WebSocket stream.
class KlineTick {
  const KlineTick({
    required this.eventTimeMs,
    required this.symbol,
    required this.interval,
    required this.candle,
    required this.isCandleClosed,
  });

  final int eventTimeMs;
  final String symbol;
  final String interval;
  final Candle candle;

  /// True when this event carries the final state of the candle (`k.x`).
  final bool isCandleClosed;

  /// Parses a raw kline stream payload:
  ///
  /// ```json
  /// {"e":"kline","E":1690000000000,"s":"BTCUSDT",
  ///  "k":{"t":...,"T":...,"i":"1m","o":"...","h":"...","l":"...","c":"...",
  ///       "v":"...","x":false, ...}}
  /// ```
  ///
  /// Throws [FormatException] for payloads that are not kline events or are
  /// missing required fields.
  factory KlineTick.fromJson(Map<String, dynamic> json) {
    if (json['e'] != 'kline') {
      throw FormatException('Not a kline event: ${json['e']}');
    }
    final k = json['k'];
    if (k is! Map<String, dynamic>) {
      throw FormatException('Missing "k" payload in kline event: $json');
    }
    return KlineTick(
      eventTimeMs: _asInt(json['E'], 'E'),
      symbol: _asString(json['s'], 's'),
      interval: _asString(k['i'], 'k.i'),
      isCandleClosed: _asBool(k['x'], 'k.x'),
      candle: Candle(
        openTimeMs: _asInt(k['t'], 'k.t'),
        closeTimeMs: _asInt(k['T'], 'k.T'),
        open: _asDouble(k['o'], 'k.o'),
        high: _asDouble(k['h'], 'k.h'),
        low: _asDouble(k['l'], 'k.l'),
        close: _asDouble(k['c'], 'k.c'),
        volume: _asDouble(k['v'], 'k.v'),
      ),
    );
  }

  /// Convenience wrapper around [KlineTick.fromJson] for a raw frame string.
  factory KlineTick.fromRawMessage(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('Expected a JSON object, got: $raw');
    }
    return KlineTick.fromJson(decoded);
  }

  @override
  String toString() =>
      'KlineTick($symbol $interval closed=$isCandleClosed $candle)';
}

int _asInt(dynamic value, String field) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  throw FormatException('Field "$field" is not an int: $value');
}

double _asDouble(dynamic value, String field) {
  // Binance sends prices/volumes as strings to preserve precision.
  if (value is String) {
    final parsed = double.tryParse(value);
    if (parsed != null) return parsed;
  }
  if (value is num) return value.toDouble();
  throw FormatException('Field "$field" is not a number: $value');
}

String _asString(dynamic value, String field) {
  if (value is String && value.isNotEmpty) return value;
  throw FormatException('Field "$field" is not a non-empty string: $value');
}

bool _asBool(dynamic value, String field) {
  if (value is bool) return value;
  throw FormatException('Field "$field" is not a bool: $value');
}
