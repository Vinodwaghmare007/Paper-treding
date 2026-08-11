import { NewsProvider, NewsProviderItem } from "./newsProvider";

/**
 * The ACTIVE default provider — see aggregateNews.ts. CoinGecko's News
 * endpoint could not be verified from this sandbox (no outbound network
 * access at all — see coinGeckoNewsProvider.ts's doc comment for the full
 * account), which is exactly the condition under which the spec calls for
 * falling back to CryptoPanic's free tier.
 *
 * This is also not freshly guessed: this exact `/api/v1/posts/` shape
 * (`results[].title`, `.url`, `.published_at`, `.source.title`/
 * `.source.domain`) is the same schema this codebase's own prior
 * client-side CryptoPanic integration was built against earlier in this
 * project's history — still not exercised against a live response (same
 * network constraint), but at least a schema this project has reasoned
 * through once already rather than a fresh guess. Confirm it against a
 * real API call before the first production deploy, same as any other
 * unverified integration in this codebase (see docs/RELEASE.md).
 *
 * Moving this server-side (rather than the old client-side Dart
 * implementation) is also a small security improvement: the
 * `auth_token` now lives in a Secret Manager secret
 * (CRYPTOPANIC_API_TOKEN, see aggregateNews.ts) and is never shipped
 * inside the app binary.
 */
export class CryptoPanicNewsProvider implements NewsProvider {
  readonly name = "cryptopanic";

  constructor(
    private readonly options: {
      authToken: string;
      baseUrl?: string;
      timeoutMs?: number;
      currencies?: string;
    },
  ) {}

  async fetchLatestNews(): Promise<NewsProviderItem[]> {
    if (!this.options.authToken) {
      throw new Error("CryptoPanic auth token is not configured.");
    }

    const baseUrl = this.options.baseUrl ?? "https://cryptopanic.com/api/v1/posts/";
    const query = new URLSearchParams({
      auth_token: this.options.authToken,
      public: "true",
      kind: "news",
    });
    if (this.options.currencies) {
      query.set("currencies", this.options.currencies);
    }

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.options.timeoutMs ?? 10_000);

    let response: Response;
    try {
      response = await fetch(`${baseUrl}?${query.toString()}`, { signal: controller.signal });
    } finally {
      clearTimeout(timeout);
    }

    if (!response.ok) {
      throw new Error(`CryptoPanic request failed: HTTP ${response.status}`);
    }

    const body = (await response.json()) as unknown;
    return CryptoPanicNewsProvider.parseResponse(body);
  }

  static parseResponse(body: unknown): NewsProviderItem[] {
    if (typeof body !== "object" || body === null) return [];
    const results = (body as Record<string, unknown>).results;
    if (!Array.isArray(results)) return [];

    const items: NewsProviderItem[] = [];
    for (const raw of results) {
      if (typeof raw !== "object" || raw === null) continue;
      const entry = raw as Record<string, unknown>;

      const headline = entry.title;
      const url = entry.url;
      if (typeof headline !== "string" || typeof url !== "string") continue;

      const source = entry.source as Record<string, unknown> | undefined;
      const sourceName =
        typeof source?.title === "string"
          ? source.title
          : typeof source?.domain === "string"
            ? source.domain
            : "Unknown source";

      // CryptoPanic's public posts endpoint is a curated aggregator/
      // commentary feed rather than full-article syndication — it does
      // not return a separate summary/description field distinct from
      // the headline itself. Left empty rather than duplicating the
      // headline into the summary field too; news_feed_screen.dart
      // already hides the summary line entirely when it's empty rather
      // than showing a repeated headline.
      const summary = "";

      const publishedRaw = entry.published_at;
      const publishedAtMs = typeof publishedRaw === "string" ? Date.parse(publishedRaw) : NaN;

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
