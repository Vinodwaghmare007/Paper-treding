/// A single crypto news headline. Deliberately holds only what's needed to
/// list and open the source article — never the article body, to stay
/// clear of republishing/copyright issues (see crypto_news_source.dart).
class NewsHeadline {
  const NewsHeadline({
    required this.id,
    required this.title,
    required this.sourceName,
    required this.publishedAt,
    required this.url,
  });

  final String id;
  final String title;
  final String sourceName;
  final DateTime publishedAt;
  final Uri url;
}
