import Parser from "rss-parser";

import { NewsProvider, NewsProviderItem } from "./newsProvider";

/**
 * ACTIVE PROVIDER — genuinely zero-cost: no account, no API key, no
 * payment. CryptoPanic's API (cryptoPanicNewsProvider.ts) turned out to
 * require a paid plan (confirmed live: their v2 docs show every plan
 * tier — Developer/Growth/Enterprise — gated behind "Get PLUS", with no
 * free API-key path found under Profile/Account/Settings). CoinGecko's
 * News endpoint was never even confirmed to exist (see
 * coinGeckoNewsProvider.ts). RSS is the one option that's actually
 * confirmed free, since publishers themselves publish these feeds
 * openly, with no auth of any kind.
 *
 * PRE-LAUNCH TODO: the 4 feed URLs below have not been verified live —
 * this sandbox has no outbound network access at all (confirmed via
 * curl and WebFetch against multiple hosts this session). Feed URLs
 * change without notice; confirm each one still resolves and returns
 * valid RSS/Atom XML before relying on this in production. A dead URL
 * degrades gracefully (see fetchLatestNews below — one source failing
 * never blocks the others), so this is a "silently produces fewer
 * items" risk, not a crash risk — but still worth an actual check.
 */
interface RssSource {
  name: string;
  url: string;
}

const RSS_SOURCES: RssSource[] = [
  { name: "CoinDesk", url: "https://www.coindesk.com/arc/outboundfeeds/rss/" },
  { name: "CoinTelegraph", url: "https://cointelegraph.com/rss" },
  { name: "Decrypt", url: "https://decrypt.co/feed" },
  { name: "The Block", url: "https://www.theblock.co/rss.xml" },
];

export class RssNewsProvider implements NewsProvider {
  readonly name = "rss";

  constructor(
    private readonly options: {
      sources?: RssSource[];
      timeoutMs?: number;
    } = {},
  ) {}

  async fetchLatestNews(): Promise<NewsProviderItem[]> {
    const sources = this.options.sources ?? RSS_SOURCES;
    const items: NewsProviderItem[] = [];
    const failedSources: string[] = [];

    for (const source of sources) {
      try {
        const xml = await this.fetchFeedXml(source.url);
        const rawItems = await RssNewsProvider.parseFeedXml(xml);
        for (const rawItem of rawItems) {
          const item = RssNewsProvider.toProviderItem(rawItem, source.name);
          if (item) items.push(item);
        }
      } catch (e) {
        // One dead/malformed feed must never block the others — log and
        // move on to the next source.
        const message = e instanceof Error ? e.message : String(e);
        console.error(`[RssNewsProvider] source "${source.name}" failed, skipping:`, message);
        failedSources.push(source.name);
      }
    }

    // A partial outage (some sources down, others fine) is expected and
    // not itself a "run failure" — this run still writes whatever came
    // back. But if literally EVERY source failed, that's exactly the
    // kind of problem aggregateNews.ts's consecutive-failure alert exists
    // to catch, and it can only catch it if this throws rather than
    // quietly returning an empty array that looks like "zero news today."
    if (items.length === 0 && sources.length > 0 && failedSources.length === sources.length) {
      throw new Error(`All ${sources.length} RSS source(s) failed: ${failedSources.join(", ")}`);
    }

    return items;
  }

  private async fetchFeedXml(url: string): Promise<string> {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.options.timeoutMs ?? 10_000);
    try {
      const response = await fetch(url, {
        signal: controller.signal,
        headers: {
          "User-Agent":
            "CryptoPaperTraderNewsBot/1.0 (+https://vinodwaghmare007.github.io/Paper-treding/)",
        },
      });
      if (!response.ok) {
        throw new Error(`HTTP ${response.status} fetching ${url}`);
      }
      return await response.text();
    } finally {
      clearTimeout(timeout);
    }
  }

  static async parseFeedXml(xml: string): Promise<Parser.Item[]> {
    const parser = new Parser();
    const feed = await parser.parseString(xml);
    return feed.items;
  }

  /**
   * SUMMARY FIELD — READ BEFORE CHANGING: `item.summary` and
   * `item.contentSnippet`/`item.content` are safe short-summary fields.
   * `item['content:encoded']` and `item['content:encodedSnippet']` are
   * NOT safe — verified directly against the installed rss-parser
   * source (lib/parser.js + lib/fields.js): an RSS `<content:encoded>`
   * tag (full article body, when a feed includes one) is copied to the
   * separate key `content:encoded`/`content:encodedSnippet`, never to
   * `.content`/`.contentSnippet` — those two are populated ONLY from the
   * short `<description>` tag for RSS feeds (Atom feeds populate
   * `.content` from `<content>`, which is why `.summary`, sourced from
   * Atom's `<summary>`, is tried first below). This function must never
   * read `item['content:encoded']` or `item['content:encodedSnippet']`.
   */
  static toProviderItem(item: Parser.Item, sourceName: string): NewsProviderItem | null {
    const headline = item.title?.trim();
    const url = item.link?.trim();
    if (!headline || !url) return null;

    const summary = item.summary || item.contentSnippet || item.content || "";
    const publishedAtMs = item.pubDate ? Date.parse(item.pubDate) : NaN;

    return {
      headline,
      summary,
      url,
      sourceName,
      publishedAtMs: Number.isFinite(publishedAtMs) ? publishedAtMs : undefined,
    };
  }
}
