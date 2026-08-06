import 'package:dio/dio.dart';

import '../models/forecast.dart';

/// A clean, typed failure from the forecast backend — never a raw
/// [DioException] leaking into the UI layer.
class ForecastApiException implements Exception {
  const ForecastApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  /// True for the backend's per-symbol 30s rate limit (HTTP 429) — worth
  /// distinguishing so the UI can show a countdown instead of a generic
  /// error.
  bool get isRateLimited => statusCode == 429;

  @override
  String toString() => message;
}

/// Client for the Crypto Paper Trader forecast backend (FastAPI + ARIMA).
///
/// The backend's base URL isn't a fixed, known value at build time — it's
/// wherever the solo-dev deploy (Railway/Render, see backend/Dockerfile)
/// ends up living, which is a per-deployment detail, not something this
/// client can hard-code correctly for everyone. Override it at build time:
///   flutter run --dart-define=FORECAST_API_BASE_URL=https://your-app.up.railway.app
/// The default targets the Android emulator's alias for the host machine's
/// localhost, so `flutter run` "just works" against a locally-run
/// `uvicorn app.main:app` during development.
const _defaultBaseUrl = String.fromEnvironment(
  'FORECAST_API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8000',
);

class ForecastApiSource {
  ForecastApiSource({Dio? dio, String? baseUrl})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: baseUrl ?? _defaultBaseUrl,
                connectTimeout: const Duration(seconds: 10),
                // ARIMA fitting on the backend can take a few seconds for a
                // 500-candle history; give it real headroom rather than
                // timing out mid-fit.
                receiveTimeout: const Duration(seconds: 30),
              ),
            );

  final Dio _dio;

  Future<PriceForecast> fetchForecast({
    required String symbol,
    String interval = '1m',
    int steps = 15,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/forecast',
        data: {
          'symbol': symbol,
          'interval': interval,
          'steps': steps,
        },
      );
      return PriceForecast.fromJson(response.data!);
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  ForecastApiException _mapError(DioException e) {
    final statusCode = e.response?.statusCode;
    final detail = e.response?.data is Map
        ? (e.response?.data as Map)['detail']?.toString()
        : null;

    if (statusCode != null) {
      return ForecastApiException(
        detail ?? 'Forecast request failed (HTTP $statusCode).',
        statusCode: statusCode,
      );
    }
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const ForecastApiException(
          'Forecast service timed out. It may be cold-starting — try again shortly.',
        );
      case DioExceptionType.connectionError:
        return const ForecastApiException(
          'Could not reach the forecast service. Check your connection.',
        );
      default:
        return ForecastApiException('Forecast request failed: ${e.message}');
    }
  }
}
