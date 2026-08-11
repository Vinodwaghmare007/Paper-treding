import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/news_headline.dart';
import '../firestore/firestore_paths.dart';

/// One page of the news feed query, plus the pagination cursor
/// ([lastDocument]) the next call passes back in as `startAfter`.
class NewsFeedPage {
  const NewsFeedPage({
    required this.headlines,
    required this.lastDocument,
    required this.hasMore,
  });

  final List<NewsHeadline> headlines;
  final DocumentSnapshot<Map<String, dynamic>>? lastDocument;

  /// True if this page was full — a strong (not perfect) signal there's
  /// more to load. A page shorter than [NewsFeedSource.pageSize] means
  /// this was the last page.
  final bool hasMore;
}

/// Reads the server-aggregated news feed from `news_items`, most recent
/// first, paginated. This is the ONLY thing the app does for news — it
/// never calls a news provider directly, so fetch/dedup/copyright-safety
/// logic lives in exactly one place (functions/src/news/aggregateNews.ts),
/// not duplicated client-side.
class NewsFeedSource {
  NewsFeedSource(FirebaseFirestore firestore) : _paths = FirestorePaths(firestore);

  final FirestorePaths _paths;

  static const pageSize = 20;

  Future<NewsFeedPage> fetchPage({
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
  }) async {
    Query<Map<String, dynamic>> query =
        _paths.newsItems().orderBy('published_at', descending: true).limit(pageSize);
    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }

    final snap = await query.get();
    final headlines = snap.docs
        .map((doc) => NewsHeadline.fromMap(doc.id, doc.data()))
        .toList(growable: false);

    return NewsFeedPage(
      headlines: headlines,
      lastDocument: snap.docs.isEmpty ? startAfter : snap.docs.last,
      hasMore: snap.docs.length == pageSize,
    );
  }
}
