import 'package:crypto_paper_trader/domain/usecases/indicator_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

/// Independent, deliberately unoptimized reference implementation of
/// Wilder's RSI, written separately from `indicator_calculator.dart` (no
/// shared helpers) so it can catch a bug the production code might share
/// with itself. Mirrors the textbook formula line-by-line: first average
/// is a plain mean of the first `period` gains/losses, every average after
/// that is Wilder-smoothed, RSI = 100 - 100/(1 + avgGain/avgLoss).
List<double> _referenceRsi(List<double> prices, int period) {
  final result = List<double>.filled(prices.length, double.nan);
  if (prices.length <= period) return result;

  final changes = <double>[0];
  for (var i = 1; i < prices.length; i++) {
    changes.add(prices[i] - prices[i - 1]);
  }

  double avgGain = changes.sublist(1, period + 1).where((c) => c > 0).fold(0.0, (a, b) => a + b) / period;
  double avgLoss = changes.sublist(1, period + 1).where((c) => c < 0).fold(0.0, (a, b) => a - b) / period;

  double rsiOf(double gain, double loss) {
    if (gain == 0 && loss == 0) return 50;
    if (loss == 0) return 100;
    if (gain == 0) return 0;
    return 100 - 100 / (1 + gain / loss);
  }

  result[period] = rsiOf(avgGain, avgLoss);
  for (var i = period + 1; i < prices.length; i++) {
    final gain = changes[i] > 0 ? changes[i] : 0.0;
    final loss = changes[i] < 0 ? -changes[i] : 0.0;
    avgGain = (avgGain * (period - 1) + gain) / period;
    avgLoss = (avgLoss * (period - 1) + loss) / period;
    result[i] = rsiOf(avgGain, avgLoss);
  }
  return result;
}

void main() {
  group('calculateSMA', () {
    test('matches a hand-verified example', () {
      // prices form an arithmetic sequence; SMA(3) of any 3 consecutive
      // values in a +1 ramp is just the middle value.
      final sma = calculateSMA([10, 11, 12, 13, 14], 3);
      expect(sma[0].isNaN, isTrue);
      expect(sma[1].isNaN, isTrue);
      expect(sma[2], 11); // (10+11+12)/3
      expect(sma[3], 12); // (11+12+13)/3
      expect(sma[4], 13); // (12+13+14)/3
    });

    test('throws for a non-positive period', () {
      expect(() => calculateSMA([1, 2, 3], 0), throwsArgumentError);
    });
  });

  group('calculateEMA', () {
    test('matches a hand-verified example', () {
      // multiplier = 2/(3+1) = 0.5
      // seed EMA[2] = mean(10,11,12) = 11
      // EMA[3] = (13-11)*0.5 + 11 = 12
      // EMA[4] = (14-12)*0.5 + 12 = 13
      final ema = calculateEMA([10, 11, 12, 13, 14], 3);
      expect(ema[0].isNaN, isTrue);
      expect(ema[1].isNaN, isTrue);
      expect(ema[2], 11);
      expect(ema[3], 12);
      expect(ema[4], 13);
    });

    test('seeds correctly past a leading NaN run (as MACD\'s signal line needs)', () {
      final input = [double.nan, double.nan, 10.0, 11.0, 12.0, 13.0, 14.0];
      final ema = calculateEMA(input, 3);
      expect(ema[3].isNaN, isTrue); // only 2 valid values so far
      expect(ema[4], 11); // mean(10,11,12), first valid 3-run
      expect(ema[5], 12);
      expect(ema[6], 13);
    });
  });

  group('calculateRSI', () {
    test('a monotonically rising series saturates at RSI 100 (no losses at all)', () {
      final prices = List<double>.generate(10, (i) => 100.0 + i * 2);
      final rsi = calculateRSI(prices, 5);
      expect(rsi[5], 100);
      expect(rsi[9], 100);
    });

    test('a monotonically falling series saturates at RSI 0 (no gains at all)', () {
      final prices = List<double>.generate(10, (i) => 100.0 - i * 2);
      final rsi = calculateRSI(prices, 5);
      expect(rsi[5], 0);
      expect(rsi[9], 0);
    });

    test('a perfectly flat series is RSI 50 (no gains, no losses)', () {
      final prices = List<double>.filled(10, 100.0);
      final rsi = calculateRSI(prices, 5);
      expect(rsi[5], 50);
      expect(rsi[9], 50);
    });

    test('matches a hand-derived worked example (period 5)', () {
      // prices:  100, 102, 101, 103, 106, 105, 107, 106, 108, 110
      // changes:      +2   -1   +2   +3   -1   +2   -1   +2   +2
      // gains:         2    0    2    3    0    2    0    2    2
      // losses:        0    1    0    0    1    0    1    0    0
      //
      // avgGain[5] = (2+0+2+3+0)/5 = 7/5, avgLoss[5] = (0+1+0+0+1)/5 = 2/5
      // RS[5] = 7/2 -> RSI[5] = 100 - 100/(1+7/2) = 700/9
      //
      // avgGain[6] = (7/5*4+2)/5 = 38/25, avgLoss[6] = (2/5*4+0)/5 = 8/25
      // RS[6] = 19/4 -> RSI[6] = 100 - 100/(1+19/4) = 1900/23
      //
      // avgGain[7] = (38/25*4+0)/5 = 152/125, avgLoss[7] = (8/25*4+1)/5 = 57/125
      // RS[7] = 8/3 -> RSI[7] = 100 - 100/(1+8/3) = 800/11
      //
      // avgGain[8] = (152/125*4+2)/5 = 858/625, avgLoss[8] = (57/125*4+0)/5 = 228/625
      // RS[8] = 143/38 -> RSI[8] = 100 - 100/(1+143/38) = 14300/181
      //
      // avgGain[9] = (858/625*4+2)/5 = 4682/3125, avgLoss[9] = (228/625*4+0)/5 = 912/3125
      // RS[9] = 2341/456 -> RSI[9] = 100 - 100/(1+2341/456) = 234100/2797
      final prices = <double>[100, 102, 101, 103, 106, 105, 107, 106, 108, 110];
      final rsi = calculateRSI(prices, 5);

      expect(rsi[5], closeTo(700 / 9, 1e-9));
      expect(rsi[6], closeTo(1900 / 23, 1e-9));
      expect(rsi[7], closeTo(800 / 11, 1e-9));
      expect(rsi[8], closeTo(14300 / 181, 1e-9));
      expect(rsi[9], closeTo(234100 / 2797, 1e-9));
    });

    test('matches an independently-coded reference implementation on a longer series', () {
      // A separately-written implementation of the same published formula,
      // run over a longer, less hand-tractable series, catching anything
      // the short worked example above wouldn't exercise (e.g. period
      // boundary handling, sign edge cases).
      final prices = [
        44.34, 44.09, 44.15, 43.61, 44.33, 44.83, 45.10, 45.42, 45.84, 46.08,
        45.89, 46.03, 45.61, 46.28, 46.28, 46.00, 46.03, 46.41, 46.22, 45.64,
      ];
      for (final period in [5, 14]) {
        final production = calculateRSI(prices, period);
        final reference = _referenceRsi(prices, period);
        for (var i = 0; i < prices.length; i++) {
          if (reference[i].isNaN) {
            expect(production[i].isNaN, isTrue, reason: 'index $i, period $period');
          } else {
            expect(production[i], closeTo(reference[i], 1e-9), reason: 'index $i, period $period');
          }
        }
      }
    });

    test('throws for a non-positive period', () {
      expect(() => calculateRSI([1, 2, 3], 0), throwsArgumentError);
    });

    test('returns all-NaN when there is not enough data for even one value', () {
      final rsi = calculateRSI([1, 2, 3], 5);
      expect(rsi.every((v) => v.isNaN), isTrue);
    });
  });

  group('calculateMACD', () {
    test('macdLine equals EMA(fast) - EMA(slow) at every defined index', () {
      final prices = List<double>.generate(60, (i) => 100 + i * 0.5 + (i.isEven ? 1 : -1));
      final result = calculateMACD(prices, fastPeriod: 3, slowPeriod: 6, signalPeriod: 4);
      final fastEma = calculateEMA(prices, 3);
      final slowEma = calculateEMA(prices, 6);

      for (var i = 0; i < prices.length; i++) {
        if (fastEma[i].isNaN || slowEma[i].isNaN) {
          expect(result.macdLine[i].isNaN, isTrue, reason: 'index $i');
        } else {
          expect(result.macdLine[i], closeTo(fastEma[i] - slowEma[i], 1e-9), reason: 'index $i');
        }
      }
    });

    test('signal line is defined signalPeriod bars after the MACD line starts', () {
      final prices = List<double>.generate(60, (i) => 100 + i * 0.3);
      final result = calculateMACD(prices, fastPeriod: 3, slowPeriod: 6, signalPeriod: 4);

      // MACD line first defined at index 5 (slowPeriod-1); signal line
      // needs 4 more consecutive MACD values, so first defined at index 8.
      expect(result.macdLine[4].isNaN, isTrue);
      expect(result.macdLine[5].isNaN, isFalse);
      expect(result.signalLine[7].isNaN, isTrue);
      expect(result.signalLine[8].isNaN, isFalse);
    });

    test('rejects fastPeriod >= slowPeriod', () {
      expect(
        () => calculateMACD([1, 2, 3], fastPeriod: 10, slowPeriod: 5),
        throwsArgumentError,
      );
    });
  });
}
