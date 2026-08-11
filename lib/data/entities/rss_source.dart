/// One crypto RSS/Atom source the backend polls into `news_items` (see
/// functions/src/news/aggregateNews.ts) — the Flutter app never fetches
/// RSS directly, so this list isn't used to drive network calls here. It
/// exists for forward-looking UI (e.g. "filter by source" chips once the
/// source list grows past a handful — see news_feed_screen.dart's doc
/// comment) and to mirror the exact source names the backend writes into
/// each `news_items` doc's `source_name` field.
///
/// [defaultRssSources] is the bundled default, shipped in the app binary,
/// overlaid with a live Remote Config payload by [rssSourcesProvider] in
/// rss_source_providers.dart — same fetch/parse/fallback pattern as
/// [supportedCoins] (see coin_catalog_providers.dart), and reading the
/// exact same `rss_sources_json` Remote Config parameter the backend
/// itself reads server-side (see functions/src/news/rssSources.ts), so
/// one publish in the Firebase console updates both sides.
///
/// PRE-LAUNCH TODO: these 4 URLs/names were supplied as the target sources
/// and have not been verified live — this sandbox has no outbound network
/// access. See the identical caveat on functions/src/news/rssSources.ts.
class RssSourceConfig {
  const RssSourceConfig({
    required this.name,
    required this.url,
    required this.category,
    required this.cryptoExclusive,
  });

  final String name;
  final String url;
  final String category;
  final bool cryptoExclusive;
}

const defaultRssSources = <RssSourceConfig>[
  RssSourceConfig(
    name: 'CoinDesk',
    url: 'https://www.coindesk.com/arc/outboundfeeds/rss/',
    category: 'general',
    cryptoExclusive: true,
  ),
  RssSourceConfig(
    name: 'CoinTelegraph',
    url: 'https://cointelegraph.com/rss',
    category: 'general',
    cryptoExclusive: true,
  ),
  RssSourceConfig(
    name: 'Decrypt',
    url: 'https://decrypt.co/feed',
    category: 'general',
    cryptoExclusive: true,
  ),
  RssSourceConfig(
    name: 'The Block',
    url: 'https://www.theblock.co/rss.xml',
    category: 'general',
    cryptoExclusive: true,
  ),
];
