import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/entities/whale_transaction.dart';

class WhaleAlertException implements Exception {
  WhaleAlertException(this.message);
  final String message;

  @override
  String toString() => 'WhaleAlertException: $message';
}

/// Fetches recently-observed Bitcoin mempool transactions from
/// mempool.space's free public API.
///
/// NOTE ON PROVIDER CHOICE: Whale Alert (whale-alert.io) — the more
/// commonly-known "whale transaction" API — has no viable free tier as of
/// the research done for this feature: $29.95/month minimum, only a 7-day
/// trial. mempool.space's API is free and public, in exchange for two
/// narrower guarantees than a paid whale-tracking service: it only covers
/// Bitcoin (not other chains), and `/api/mempool/recent` is documented as
/// a rolling snapshot of the ~10 most-recently-added mempool
/// transactions, not a queryable historical feed — see
/// whale_activity_tracker.dart for how this app builds an "in the last
/// hour" count out of that rolling snapshot via repeated polling.
///
/// NOTE ON VERIFICATION: this sandbox has no outbound network access to
/// mempool.space (confirmed blocked), so this client is written against
/// mempool.space's documented Esplora-derived REST shape — GET
/// /api/mempool/recent returning a JSON array of
/// `[txid, fee, vsize, value]` entries (value in satoshis) — but has not
/// been exercised against a live response. Confirm the endpoint path and
/// array field order below against a real call before shipping, and
/// adjust [fetchRecentMempoolTransactions] if they've drifted.
class WhaleAlertSource {
  WhaleAlertSource({
    http.Client? client,
    this.baseUrl = 'https://mempool.space/api',
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  Future<List<WhaleTransaction>> fetchRecentMempoolTransactions() async {
    final uri = Uri.parse('$baseUrl/mempool/recent');

    final http.Response response;
    try {
      response = await _client.get(uri).timeout(const Duration(seconds: 10));
    } catch (e) {
      throw WhaleAlertException('Failed to reach mempool.space: $e');
    }

    if (response.statusCode != 200) {
      throw WhaleAlertException(
        'mempool.space returned ${response.statusCode}: ${response.body}',
      );
    }

    try {
      final decoded = jsonDecode(response.body) as List<dynamic>;
      final observedAt = DateTime.now().toUtc();
      return decoded.map((raw) {
        final entry = raw as List<dynamic>;
        return WhaleTransaction(
          txid: entry[0] as String,
          valueSats: (entry[3] as num).toInt(),
          observedAt: observedAt,
        );
      }).toList(growable: false);
    } catch (e) {
      throw WhaleAlertException('Malformed mempool.space response: $e');
    }
  }

  void dispose() => _client.close();
}
