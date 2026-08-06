import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/community_sentiment.dart';
import '../firestore/firestore_paths.dart';
import '../firestore/sentiment_mappers.dart';

/// Read side of the anonymized community sentiment feature — always
/// public, read-only from the client (see the `public_sentiment` match
/// block in firestore.rules).
class SentimentRepository {
  SentimentRepository(FirebaseFirestore firestore)
      : _paths = FirestorePaths(firestore);

  final FirestorePaths _paths;

  /// Null if functions/src/sentiment/aggregateSentiment.ts hasn't produced
  /// a doc for [symbol] yet (e.g. right after deploy, before the first
  /// hourly run).
  Stream<CommunitySentiment?> watchSentiment(String symbol) {
    return _paths.publicSentiment(symbol).snapshots().map(
          (doc) => doc.exists
              ? CommunitySentimentFirestoreMapping.fromDoc(doc)
              : null,
        );
  }
}
