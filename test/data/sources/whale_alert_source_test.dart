import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:crypto_paper_trader/data/sources/whale_alert_source.dart';

const _sampleBody = '''
[
  ["txid-1", 1500, 250, 2500000000],
  ["txid-2", 900, 180, 50000000]
]
''';

void main() {
  group('WhaleAlertSource.fetchRecentMempoolTransactions', () {
    test('parses txid and value (sats) from each [txid, fee, vsize, value] entry', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/api/mempool/recent');
        return http.Response(_sampleBody, 200);
      });

      final source = WhaleAlertSource(client: client);
      final txs = await source.fetchRecentMempoolTransactions();

      expect(txs, hasLength(2));
      expect(txs[0].txid, 'txid-1');
      expect(txs[0].valueSats, 2500000000);
      expect(txs[0].valueBtc, 25.0);
      expect(txs[1].txid, 'txid-2');
      expect(txs[1].valueSats, 50000000);
    });

    test('throws WhaleAlertException on a non-200 response', () async {
      final client = MockClient((request) async => http.Response('server error', 500));
      final source = WhaleAlertSource(client: client);

      expect(
        () => source.fetchRecentMempoolTransactions(),
        throwsA(isA<WhaleAlertException>()),
      );
    });

    test('throws WhaleAlertException on a malformed response body', () async {
      final client = MockClient((request) async => http.Response('not json', 200));
      final source = WhaleAlertSource(client: client);

      expect(
        () => source.fetchRecentMempoolTransactions(),
        throwsA(isA<WhaleAlertException>()),
      );
    });
  });
}
