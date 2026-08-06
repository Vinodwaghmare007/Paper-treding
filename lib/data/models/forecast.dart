/// A short-horizon ARIMA price projection from the forecast backend.
///
/// This is a statistical projection, not a prediction with any guarantee of
/// accuracy — see [disclaimer], which the backend always fills in and the
/// UI must always surface alongside the chart overlay.
class PriceForecast {
  const PriceForecast({
    required this.predictedPath,
    required this.confidenceUpper,
    required this.confidenceLower,
    required this.modelOrder,
    required this.generatedAt,
    required this.disclaimer,
  });

  final List<double> predictedPath;
  final List<double> confidenceUpper;
  final List<double> confidenceLower;
  final List<int> modelOrder;
  final DateTime generatedAt;
  final String disclaimer;

  factory PriceForecast.fromJson(Map<String, dynamic> json) {
    List<double> toDoubleList(dynamic value) => (value as List<dynamic>)
        .map((e) => (e as num).toDouble())
        .toList(growable: false);

    return PriceForecast(
      predictedPath: toDoubleList(json['predicted_path']),
      confidenceUpper: toDoubleList(json['confidence_upper']),
      confidenceLower: toDoubleList(json['confidence_lower']),
      modelOrder: (json['model_order'] as List<dynamic>)
          .map((e) => (e as num).toInt())
          .toList(growable: false),
      generatedAt: DateTime.parse(json['generated_at'] as String),
      disclaimer: json['disclaimer'] as String,
    );
  }
}
