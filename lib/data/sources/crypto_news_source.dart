import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/entities/news_headline.dart';

class CryptoNewsException implements Exception {
  CryptoNewsException(this.message);
  final String message;

  @override
  String toString() => 'CryptoNewsException: $message';
}

/// Fetches crypto headlines from the CryptoPanic public API — title,
/// source name, published time, and the external link only, never the
/// article body. Tapping a headline opens that external [NewsHeadline.url]
/// (see news_feed_screen.dart) rather than this app rendering or copying
/// the article itself, which is what keeps this feature clear of
/// republishing/copyright concerns.
///
/// NOTE ON VERIFICATION: this sandbox has no outbound network access, so
/// this client is written against CryptoPanic's documented v1
/// `/api/v1/posts/` response shape but has not been exercised against a
/// live response. Confirm the field names below (particularly
/// `results[].source.title` and `results[].url`) against a real API call
/// before shipping, and adjust `_parseResults` if they've drifted.
///
/// NOTE ON THE API TOKEN: CryptoPanic requires a free `auth_token` for
/// every request. It is never hardcoded here — pass it at build time with
/// `--dart-define=CRYPTOPANIC_API_TOKEN=your_token` (e.g. in your CI/CD
/// build command), which is why the constructor default reads it from
/// `String.fromEnvironment`. A missing token throws [CryptoNewsException]
/// immediately rather than making a request guaranteed to fail.
class CryptoNewsSource {
  CryptoNewsSource({
    http.Client? client,
    String? apiToken,
    this.baseUrl = 'https://cryptopanic.com/api/v1/posts/',
    this.cacheTtl = const Duration(minutes: 15),
  })  : _client = client ?? http.Client(),
        _apiToken = apiToken ??
            const String.fromEnvironment('CRYPTOPANIC_API_TOKEN');

  final http.Client _client;
  final String _apiToken;
  final String baseUrl;
  final Duration cacheTtl;

  final Map<String, _CacheEntry> _cache = {};

  /// Headlines for [currency] (a CryptoPanic-recognized ticker, e.g.
  /// "BTC"), most recent first. Served from an in-memory cache for
  /// [cacheTtl] so repeated screen visits within that window don't refetch.
  Future<List<NewsHeadline>> fetchHeadlines({
    String currency = 'BTC',
    int limit = 30,
  }) async {
    final cached = _cache[currency];
    if (cached != null &&
        DateTime.now().difference(cached.fetchedAt) < cacheTtl) {
      return cached.headlines;
    }

    if (_apiToken.isEmpty) {
      throw CryptoNewsException(
        'No CryptoPanic API token configured. Build with '
        '--dart-define=CRYPTOPANIC_API_TOKEN=your_token.',
      );
    }

    final uri = Uri.parse(baseUrl).replace(queryParameters: {
      'auth_token': _apiToken,
      'public': 'true',
      'currencies': currency,
      'kind': 'news',
    });

    final http.Response response;
    try {
      response = await _client.get(uri).timeout(const Duration(seconds: 10));
    } catch (e) {
      throw CryptoNewsException('Failed to reach CryptoPanic: $e');
    }

    if (response.statusCode != 200) {
      throw CryptoNewsException(
        'CryptoPanic returned ${response.statusCode}: ${response.body}',
      );
    }

    final List<NewsHeadline> headlines;
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      headlines = _parseResults(body, limit: limit);
    } catch (e) {
      throw CryptoNewsException('Malformed CryptoPanic response: $e');
    }

    _cache[currency] = _CacheEntry(headlines, DateTime.now());
    return headlines;
  }

  List<NewsHeadline> _parseResults(Map<String, dynamic> body, {required int limit}) {
    final results = body['results'] as List<dynamic>? ?? const [];
    return results.take(limit).map((raw) {
      final entry = raw as Map<String, dynamic>;
      final source = entry['source'] as Map<String, dynamic>?;
      return NewsHeadline(
        id: '${entry['id']}',
        title: entry['title'] as String? ?? '(untitled)',
        sourceName: source?['title'] as String? ??
            source?['domain'] as String? ??
            'Unknown source',
        publishedAt: DateTime.parse(entry['published_at'] as String).toUtc(),
        url: Uri.parse(entry['url'] as String),
      );
    }).toList(growable: false);
  }

  void dispose() => _client.close();
}

class _CacheEntry {
  _CacheEntry(this.headlines, this.fetchedAt);
  final List<NewsHeadline> headlines;
  final DateTime fetchedAt;
}
