/**
 * One headline as a provider reports it — deliberately just enough to
 * build a `news_items` doc from (see newsItems.ts's buildNewsItem).
 * Never a full article body field: whichever provider implements this
 * must not even fetch/return one.
 */
export interface NewsProviderItem {
  headline: string;
  /** The provider's own short summary/description, PRE-truncation — see
   * newsItems.ts's truncateSummary for the server-side safety margin
   * applied on top of whatever length the provider already gives us. */
  summary: string;
  url: string;
  sourceName: string;
  /** Epoch milliseconds, or undefined if the provider didn't report one
   * (buildNewsItem falls back to "now" in that case). */
  publishedAtMs: number | undefined;
}

/**
 * The swappable seam between "how we get crypto headlines" and
 * everything else (truncation, dedupe, Firestore writes, pruning,
 * failure-alerting in aggregateNews.ts) — none of that code needs to
 * change if the active provider changes, per the explicit architecture
 * requirement. See coinGeckoNewsProvider.ts and cryptoPanicNewsProvider.ts
 * for the two implementations, and aggregateNews.ts's `activeProvider`
 * for which one is actually wired in today (and why).
 */
export interface NewsProvider {
  readonly name: string;
  fetchLatestNews(): Promise<NewsProviderItem[]>;
}
