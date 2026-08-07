import 'dart:convert';

import 'package:crypto_paper_trader/data/models/kline_tick.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('KlineTick.fromRawMessage', () {
    const rawOpen = '{"e":"kline","E":1723000000123,"s":"BTCUSDT",'
        '"k":{"t":1723000000000,"T":1723000059999,"s":"BTCUSDT","i":"1m",'
        '"f":100,"L":200,"o":"60000.10","c":"60050.55","h":"60100.00",'
        '"l":"59990.00","v":"12.345","n":100,"x":false,"q":"740000.00",'
        '"V":"6.0","Q":"360000.00","B":"0"}}';

    test('parses an in-progress candle', () {
      final tick = KlineTick.fromRawMessage(rawOpen);
      expect(tick.symbol, 'BTCUSDT');
      expect(tick.interval, '1m');
      expect(tick.isCandleClosed, isFalse);
      expect(tick.eventTimeMs, 1723000000123);
      expect(tick.candle.openTimeMs, 1723000000000);
      expect(tick.candle.closeTimeMs, 1723000059999);
      expect(tick.candle.open, 60000.10);
      expect(tick.candle.high, 60100.00);
      expect(tick.candle.low, 59990.00);
      expect(tick.candle.close, 60050.55);
      expect(tick.candle.volume, 12.345);
    });

    test('parses a closed candle (k.x == true)', () {
      final raw = rawOpen.replaceFirst('"x":false', '"x":true');
      expect(KlineTick.fromRawMessage(raw).isCandleClosed, isTrue);
    });

    test('rejects non-kline events', () {
      expect(
        () => KlineTick.fromRawMessage('{"e":"aggTrade","E":1,"s":"BTCUSDT"}'),
        throwsFormatException,
      );
    });

    test('rejects payloads with missing fields', () {
      expect(
        () => KlineTick.fromRawMessage(
            '{"e":"kline","E":1,"s":"BTCUSDT","k":{"i":"1m"}}'),
        throwsFormatException,
      );
    });

    test('rejects non-object payloads', () {
      expect(() => KlineTick.fromRawMessage('[1,2,3]'), throwsFormatException);
    });
  });

  group('Candle.fromRestEntry', () {
    test('parses a REST klines entry', () {
      final entry = jsonDecode(
        '[1723000000000,"60000.10","60100.00","59990.00","60050.55",'
        '"12.345",1723000059999,"740000.00",100,"6.0","360000.00","0"]',
      ) as List<dynamic>;
      final candle = Candle.fromRestEntry(entry);
      expect(candle.openTimeMs, 1723000000000);
      expect(candle.closeTimeMs, 1723000059999);
      expect(candle.open, 60000.10);
      expect(candle.high, 60100.00);
      expect(candle.low, 59990.00);
      expect(candle.close, 60050.55);
      expect(candle.volume, 12.345);
    });

    test('rejects short entries', () {
      expect(
        () => Candle.fromRestEntry([1723000000000, '1', '2']),
        throwsFormatException,
      );
    });
  });

  group('Candle.fromMap', () {
    test('parses the shape written by generateDailyPuzzle.ts', () {
      final candle = Candle.fromMap({
        'openTimeMs': 1723000000000,
        'closeTimeMs': 1723000059999,
        'open': 60000.10,
        'high': 60100.00,
        'low': 59990.00,
        'close': 60050.55,
        'volume': 12.345,
      });
      expect(candle.openTimeMs, 1723000000000);
      expect(candle.closeTimeMs, 1723000059999);
      expect(candle.open, 60000.10);
      expect(candle.high, 60100.00);
      expect(candle.low, 59990.00);
      expect(candle.close, 60050.55);
      expect(candle.volume, 12.345);
    });

    test('throws on a missing field', () {
      expect(
        () => Candle.fromMap({'openTimeMs': 1}),
        throwsFormatException,
      );
    });
  });

  group('Candle.toChartPoint', () {
    test('converts ms to whole seconds for Lightweight Charts', () {
      const candle = Candle(
        openTimeMs: 1723000000000,
        closeTimeMs: 1723000059999,
        open: 1.0,
        high: 2.0,
        low: 0.5,
        close: 1.5,
        volume: 10.0,
      );
      expect(candle.toChartPoint(), {
        'time': 1723000000,
        'open': 1.0,
        'high': 2.0,
        'low': 0.5,
        'close': 1.5,
      });
      expect(jsonDecode(candle.toChartJson()), isA<Map<String, dynamic>>());
    });
  });
}
