import { NewsProvider, NewsProviderItem } from "./newsProvider";

/**
 * NOT the active provider (see aggregateNews.ts — RssNewsProvider is).
 * CryptoPanic was tried first as the fallback when CoinGecko's News
 * endpoint couldn't be verified, but turned out itself to require a paid
 * plan: live screenshots of their v2 API docs and account UI (checked
 * during this project's own setup, not just read from documentation)
 * show every plan tier — Developer/Growth/Enterprise — gated behind "Get
 * PLUS", with no free API-key generation found under Profile, Account,
 * or Settings. This isn't the "unverified, might be free" state the
 * other providers are in — it's confirmed not free.
 *
 * Kept in the codebase (rather than deleted) in case a paid CryptoPanic
 * plan is ever worth it later: this exact `/api/API_PLAN/v2/posts/`
 * shape needs updating first (see the URL below), since it was written
 * against CryptoPanic's older v1 endpoint before their v2 restructuring
 * was discovered — the v2 response schema has NOT been confirmed either,
 * so treat this implementation as unverified on top of being non-free
 * today.
 *
 * The `auth_token`-via-Secret-Manager pattern here (rather than a
 * client-side `--dart-define` the way the app's very first CryptoPanic
 * integration worked) is still the right approach if this is ever
 * revived: the token never ships inside the app binary either way.
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
