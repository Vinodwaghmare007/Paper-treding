/// One row of `news_items/{itemId}`, written server-side by
/// functions/src/news/aggregateNews.ts from a polled crypto news provider
/// (see functions/src/news/newsProvider.ts).
///
/// Deliberately holds only a headline, a short (server-truncated)
/// [summary], and enough to attribute + link out to the original article
/// — never the full article body. [id] is the deterministic SHA-256 hash
/// of [sourceUrl] the backend uses as the doc ID (see
/// computeNewsItemId in newsItems.ts) — not meaningful client-side
/// beyond being a stable Flutter list key.
class NewsHeadline {
  const NewsHeadline({
    required this.id,
    required this.headline,
    required this.summary,
    required this.sourceName,
    required this.sourceUrl,
    required this.publishedAt,
    required this.fetchedAt,
  });

  final String id;
  final String headline;
  final String summary;
  final String sourceName;
  final Uri sourceUrl;
  final DateTime publishedAt;
  final DateTime fetchedAt;

  factory NewsHeadline.fromMap(String id, Map<String, dynamic> map) {
    return NewsHeadline(
      id: id,
      headline: map['headline'] as String? ?? '(untitled)',
      summary: map['summary'] as String? ?? '',
      sourceName: map['source_name'] as String? ?? 'Unknown source',
      sourceUrl: Uri.parse(map['source_url'] as String),
      publishedAt: (map['published_at'] as dynamic).toDate() as DateTime,
      fetchedAt: (map['fetched_at'] as dynamic).toDate() as DateTime,
    );
  }
}
