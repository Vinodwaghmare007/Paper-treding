import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/entities/market_weather.dart';

class MarketWeatherException implements Exception {
  MarketWeatherException(this.message);
  final String message;

  @override
  String toString() => 'MarketWeatherException: $message';
}

/// Fetches `public_market_weather/current` via a plain, unauthenticated
/// Firestore REST call rather than the `cloud_firestore` SDK.
///
/// This is deliberate, not a style choice: this source is called from
/// market_weather_sync_task.dart's WorkManager background isolate, and
/// Flutter plugins that rely on FlutterEngine/platform-channel
/// registration (like cloud_firestore, and by extension firebase_core) are
/// unreliable in that headless context — the isolate WorkManager spawns
/// doesn't go through the same plugin registration the main app's engine
/// does. A bare `package:http` GET against Firestore's public REST API has
/// no such dependency, and works here precisely because
/// `public_market_weather/current` is marked `allow read: if true` in
/// firestore.rules — no auth token needed.
class MarketWeatherSource {
  MarketWeatherSource({http.Client? client, String? projectId})
      : _client = client ?? http.Client(),
        _projectId = projectId ?? const String.fromEnvironment('FIREBASE_PROJECT_ID');

  final http.Client _client;
  final String _projectId;

  Future<MarketWeather> fetchCurrent() async {
    if (_projectId.isEmpty) {
      throw MarketWeatherException(
        'No Firebase project id configured. Build with '
        '--dart-define=FIREBASE_PROJECT_ID=your_project_id.',
      );
    }

    final uri = Uri.parse(
      'https://firestore.googleapis.com/v1/projects/$_projectId/databases/(default)/documents/public_market_weather/current',
    );

    final http.Response response;
    try {
      response = await _client.get(uri).timeout(const Duration(seconds: 10));
    } catch (e) {
      throw MarketWeatherException('Failed to reach Firestore: $e');
    }

    if (response.statusCode != 200) {
      throw MarketWeatherException(
        'Firestore returned ${response.statusCode}: ${response.body}',
      );
    }

    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final fields = body['fields'] as Map<String, dynamic>;
      return MarketWeather(
        tier: _string(fields, 'tier'),
        iconKey: _string(fields, 'icon_key'),
        stdDevPct: _double(fields, 'std_dev_pct'),
        symbol: _string(fields, 'symbol'),
        updatedAt: _timestamp(fields, 'updated_at'),
      );
    } catch (e) {
      throw MarketWeatherException('Malformed Firestore response: $e');
    }
  }

  String _string(Map<String, dynamic> fields, String key) =>
      fields[key]['stringValue'] as String;

  double _double(Map<String, dynamic> fields, String key) {
    final value = fields[key]['doubleValue'] ?? fields[key]['integerValue'];
    return double.parse(value.toString());
  }

  DateTime _timestamp(Map<String, dynamic> fields, String key) =>
      DateTime.parse(fields[key]['timestampValue'] as String).toUtc();

  void dispose() => _client.close();
}
