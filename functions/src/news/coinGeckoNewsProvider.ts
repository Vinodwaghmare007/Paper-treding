import { NewsProvider, NewsProviderItem } from "./newsProvider";

/**
 * ============================================================================
 * UNVERIFIED — DO NOT WIRE THIS IN AS THE ACTIVE PROVIDER WITHOUT CHECKING
 * COINGECKO'S LIVE DOCS FIRST. See aggregateNews.ts's `activeProvider` for
 * why CryptoPanicNewsProvider is what's actually running today instead.
 * ============================================================================
 *
 * This sandbox has no outbound network access at all — confirmed by both
 * a direct `curl` through the environment's egress proxy (`CONNECT tunnel
 * failed, response 403`) against `api.coingecko.com` and
 * `docs.coingecko.com`, and by the WebFetch tool (`EGRESS_BLOCKED`) against
 * the same hosts. That means NONE of the following could be confirmed
 * against a live response, despite the explicit instruction not to guess:
 *
 *   1. Whether `api.coingecko.com/api/v3/news` (the path below) exists at
 *      all on CoinGecko's public API. This app's *existing* CoinGecko
 *      usage (coingecko_source.dart, already in this codebase) only ever
 *      calls `/coins/markets` — there is no prior evidence in this
 *      codebase that a News endpoint was ever confirmed to exist here.
 *   2. Whether it requires the free "Demo" plan's `x-cg-demo-api-key`
 *      header (added below on the assumption it does, matching CoinGecko's
 *      2024 API tier restructuring) or a paid Pro plan, or no key at all.
 *   3. The response envelope and field names below (`data[]`, `title`,
 *      `description`, `url`, `news_site`, `updated_at`) — these are a
 *      best-effort guess, not a confirmed schema, and could be wrong in
 *      any combination.
 *   4. Actual rate limits for this endpoint specifically.
 *
 * "Reuses existing API key/infra, no new account or billing setup needed"
 * (as originally assumed) does NOT hold either: coingecko_source.dart
 * calls CoinGecko's public API with zero authentication today — there is
 * no existing CoinGecko API key configured anywhere in this project to
 * reuse. Getting this provider working for real requires: (a) confirming
 * the endpoint exists on your plan, (b) if it needs a key, registering
 * one and storing it the same way COINGECKO_API_KEY is read below (a
 * Secret Manager secret, see aggregateNews.ts's `secrets:` option — no
 * such secret is provisioned yet).
 *
 * Parsing below is written defensively (skips a malformed item rather
 * than throwing) specifically because the shape is unconfirmed — if the
 * real response looks nothing like this, fetchLatestNews() will most
 * likely return an empty array rather than crash, which is safer but
 * also easy to miss. If you enable this provider, watch the first few
 * scheduled runs' logs closely.
 */
export class CoinGeckoNewsProvider implements NewsProvider {
  readonly name = "coingecko";

  constructor(
    private readonly options: {
      apiKey?: string;
      baseUrl?: string;
      timeoutMs?: number;
    } = {},
  ) {}

  async fetchLatestNews(): Promise<NewsProviderItem[]> {
    const baseUrl = this.options.baseUrl ?? "https://api.coingecko.com/api/v3";
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.options.timeoutMs ?? 10_000);

    let response: Response;
    try {
      response = await fetch(`${baseUrl}/news`, {
        signal: controller.signal,
        headers: this.options.apiKey ? { "x-cg-demo-api-key": this.options.apiKey } : {},
      });
    } finally {
      clearTimeout(timeout);
    }

    if (!response.ok) {
      throw new Error(`CoinGecko news request failed: HTTP ${response.status}`);
    }

    const body = (await response.json()) as unknown;
    return CoinGeckoNewsProvider.parseResponse(body);
  }

  /** Exported as a static method (rather than inlined) so it can be unit
   * tested independently of the network call, same "separate IO from
   * parsing" split used throughout this app's other sources. */
  static parseResponse(body: unknown): NewsProviderItem[] {
    if (typeof body !== "object" || body === null) return [];
    const data = (body as Record<string, unknown>).data;
    if (!Array.isArray(data)) return [];

    const items: NewsProviderItem[] = [];
    for (const raw of data) {
      if (typeof raw !== "object" || raw === null) continue;
      const entry = raw as Record<string, unknown>;

      const headline = entry.title;
      const url = entry.url;
      if (typeof headline !== "string" || typeof url !== "string") continue;

      const summary = typeof entry.description === "string" ? entry.description : "";
      const sourceName =
        typeof entry.news_site === "string"
          ? entry.news_site
          : typeof entry.author === "string"
            ? entry.author
            : "CoinGecko";

      const publishedRaw = entry.updated_at ?? entry.published_at ?? entry.created_at;
      const publishedAtMs =
        typeof publishedRaw === "string" || typeof publishedRaw === "number"
          ? new Date(publishedRaw).getTime()
          : undefined;

      items.push({
        headline,
        summary,
        url,
        sourceName,
        publishedAtMs: Number.isFinite(publishedAtMs) ? publishedAtMs : undefined,
      });
    }
    return items;
  }
}
