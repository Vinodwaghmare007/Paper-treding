import 'package:crypto_paper_trader/data/models/forecast.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PriceForecast.fromJson', () {
    test('parses a well-formed forecast response', () {
      final forecast = PriceForecast.fromJson({
        'predicted_path': [60010.5, 60020.1, 60035.0],
        'confidence_upper': [60110.5, 60150.1, 60200.0],
        'confidence_lower': [59910.5, 59900.1, 59870.0],
        'model_order': [1, 1, 0],
        'generated_at': '2026-08-06T12:00:00+00:00',
        'disclaimer': 'This is a mathematical projection... not financial advice.',
      });

      expect(forecast.predictedPath, [60010.5, 60020.1, 60035.0]);
      expect(forecast.confidenceUpper, [60110.5, 60150.1, 60200.0]);
      expect(forecast.confidenceLower, [59910.5, 59900.1, 59870.0]);
      expect(forecast.modelOrder, [1, 1, 0]);
      expect(forecast.generatedAt, DateTime.parse('2026-08-06T12:00:00+00:00'));
      expect(forecast.disclaimer, contains('not financial advice'));
    });

    test('coerces integer-valued JSON numbers to double', () {
      final forecast = PriceForecast.fromJson({
        'predicted_path': [60000, 60001],
        'confidence_upper': [60100, 60101],
        'confidence_lower': [59900, 59901],
        'model_order': [0, 0, 0],
        'generated_at': '2026-08-06T12:00:00+00:00',
        'disclaimer': 'x',
      });

      expect(forecast.predictedPath, isA<List<double>>());
      expect(forecast.predictedPath, [60000.0, 60001.0]);
    });

    test('throws on a malformed generated_at timestamp', () {
      expect(
        () => PriceForecast.fromJson({
          'predicted_path': [1.0],
          'confidence_upper': [1.0],
          'confidence_lower': [1.0],
          'model_order': [0, 0, 0],
          'generated_at': 'not-a-timestamp',
          'disclaimer': 'x',
        }),
        throwsFormatException,
      );
    });
  });
}
