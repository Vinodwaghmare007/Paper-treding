// Pure-logic tests — no Firestore/emulator/live network involved. Provider
// response parsing runs against saved sample JSON (inline below), never a
// live API call. Run via: npm run test:news
import { strict as assert } from "node:assert";
import test from "node:test";

import { Timestamp } from "firebase-admin/firestore";

import { CoinGeckoNewsProvider } from "../src/news/coinGeckoNewsProvider";
import { CryptoPanicNewsProvider } from "../src/news/cryptoPanicNewsProvider";
import { buildNewsItem, computeNewsItemId, truncateSummary } from "../src/news/newsItems";
import { NewsProviderItem } from "../src/news/newsProvider";

function item(overrides: Partial<NewsProviderItem> = {}): NewsProviderItem {
  return {
    headline: "Bitcoin breaks past key resistance level",
    summary: "Bitcoin rallied past a closely-watched resistance level on Monday.",
    url: "https://example.com/articles/bitcoin-resistance",
    sourceName: "Example News",
    publishedAtMs: Date.parse("2026-08-10T09:30:00Z"),
    ...overrides,
  };
}

test("computeNewsItemId (dedupe)", async (t) => {
  await t.test("is deterministic for the same url, given twice", () => {
    const url = "https://example.com/articles/bitcoin-resistance";
    assert.equal(computeNewsItemId(url), computeNewsItemId(url));
  });

  await t.test("is stable across repeated calls the way concurrent scheduled runs rely on", () => {
    const url = "https://example.com/articles/stablecoin-rules";
    const ids = Array.from({ length: 5 }, () => computeNewsItemId(url));
    assert.ok(ids.every((id) => id === ids[0]));
  });

  await t.test("differs for different urls", () => {
    assert.notEqual(
      computeNewsItemId("https://example.com/a"),
      computeNewsItemId("https://example.com/b"),
    );
  });

  await t.test("a repeated url across two buildNewsItem calls yields the same doc id", () => {
    const now = Timestamp.now();
    const first = buildNewsItem(item(), now);
    const second = buildNewsItem(item(), now); // same url, simulating the next poll
    assert.ok(first && second);
    assert.equal(
      computeNewsItemId(first!.source_url),
      computeNewsItemId(second!.source_url),
    );
  });
});

test("truncateSummary", async (t) => {
  await t.test("leaves a string under the limit untouched", () => {
    assert.equal(truncateSummary("Short summary."), "Short summary.");
  });

  await t.test("is a no-op right at the 150-char boundary", () => {
    const exactly150 = "a".repeat(150);
    assert.equal(truncateSummary(exactly150), exactly150);
  });

  await t.test("truncates one character past the boundary, at a word break", () => {
    const oneOver = `${"a".repeat(149)} bb`; // 152 chars, space at index 149
    const result = truncateSummary(oneOver);
    assert.equal(result, `${"a".repeat(149)}…`);
  });

  await t.test("strips HTML tags", () => {
    assert.equal(truncateSummary("<p>Hello <b>world</b></p>"), "Hello world");
  });

  await t.test("decodes common HTML entities", () => {
    assert.equal(truncateSummary("Fish &amp; chips"), "Fish & chips");
  });

  await t.test("truncates long text to ~150 chars at a word boundary, with an ellipsis", () => {
    const long = "word ".repeat(60).trim(); // 299 chars
    const result = truncateSummary(long);
    assert.ok(result.length <= 151, `expected <= 151 chars, got ${result.length}`);
    assert.ok(result.endsWith("…"));
    assert.ok(!result.slice(0, -1).endsWith(" "));
  });

  await t.test("honors a caller-specified maxLength smaller than 150", () => {
    const result = truncateSummary("This sentence is deliberately a bit long for the test.", 20);
    assert.ok(result.length <= 21, `expected <= 21 chars, got ${result.length}`);
  });
});

test("buildNewsItem", async (t) => {
  await t.test("maps headline/summary/source/url/published_at correctly", () => {
    const now = Timestamp.now();
    const built = buildNewsItem(item(), now);

    assert.ok(built);
    assert.equal(built!.headline, "Bitcoin breaks past key resistance level");
    assert.equal(built!.source_name, "Example News");
    assert.equal(built!.source_url, "https://example.com/articles/bitcoin-resistance");
    assert.equal(built!.published_at.toDate().toISOString(), "2026-08-10T09:30:00.000Z");
    assert.equal(built!.fetched_at, now);
  });

  await t.test("truncates a long summary to the 150-char safety margin", () => {
    const now = Timestamp.now();
    const built = buildNewsItem(item({ summary: "word ".repeat(60).trim() }), now);
    assert.ok(built);
    assert.ok(built!.summary.length <= 151);
  });

  await t.test("falls back to 'now' when the provider gave no published time", () => {
    const now = Timestamp.now();
    const built = buildNewsItem(item({ publishedAtMs: undefined }), now);
    assert.ok(built);
    assert.equal(built!.published_at, now);
  });

  await t.test("skips an item missing a headline or url rather than throwing", () => {
    const now = Timestamp.now();
    assert.equal(buildNewsItem(item({ headline: "" }), now), null);
    assert.equal(buildNewsItem(item({ url: "" }), now), null);
  });
});

const SAMPLE_CRYPTOPANIC_RESPONSE = {
  results: [
    {
      id: 111,
      title: "Bitcoin breaks past resistance",
      published_at: "2026-08-06T09:30:00Z",
      url: "https://cryptopanic.com/news/111/bitcoin-breaks-past-resistance",
      source: { title: "CoinDesk", domain: "coindesk.com" },
    },
    {
      id: 112,
      title: "Regulators eye stablecoins",
      published_at: "2026-08-06T08:00:00Z",
      url: "https://cryptopanic.com/news/112/regulators-eye-stablecoins",
      source: { domain: "reuters.com" },
    },
    { id: 113, title: "Missing a url, should be skipped" },
  ],
};

test("CryptoPanicNewsProvider.parseResponse", async (t) => {
  await t.test("extracts title, url, published time, and source name", () => {
    const items = CryptoPanicNewsProvider.parseResponse(SAMPLE_CRYPTOPANIC_RESPONSE);
    assert.equal(items.length, 2); // the malformed 3rd entry is dropped

    assert.equal(items[0].headline, "Bitcoin breaks past resistance");
    assert.equal(
      items[0].url,
      "https://cryptopanic.com/news/111/bitcoin-breaks-past-resistance",
    );
    assert.equal(items[0].sourceName, "CoinDesk");
    assert.equal(items[0].publishedAtMs, Date.parse("2026-08-06T09:30:00Z"));
  });

  await t.test("falls back to the domain when source.title is absent", () => {
    const items = CryptoPanicNewsProvider.parseResponse(SAMPLE_CRYPTOPANIC_RESPONSE);
    assert.equal(items[1].sourceName, "reuters.com");
  });

  await t.test("returns an empty array for a malformed/unexpected body", () => {
    assert.deepEqual(CryptoPanicNewsProvider.parseResponse(null), []);
    assert.deepEqual(CryptoPanicNewsProvider.parseResponse({}), []);
    assert.deepEqual(CryptoPanicNewsProvider.parseResponse({ results: "not an array" }), []);
  });
});

// Best-effort sample matching coinGeckoNewsProvider.ts's UNVERIFIED guessed
// schema — this test only proves the defensive parser behaves sanely
// against that guess, not that the guess is correct (see that file's doc
// comment for the full caveat).
const SAMPLE_COINGECKO_RESPONSE = {
  data: [
    {
      title: "Ethereum upgrade ships",
      description: "A short description of the upgrade.",
      url: "https://example.com/eth-upgrade",
      news_site: "Example Crypto News",
      updated_at: "2026-08-06T09:30:00Z",
    },
    { title: "Missing a url, should be skipped" },
  ],
};

test("CoinGeckoNewsProvider.parseResponse (best-effort, unverified schema)", async (t) => {
  await t.test("extracts title/url/source/time under the assumed schema", () => {
    const items = CoinGeckoNewsProvider.parseResponse(SAMPLE_COINGECKO_RESPONSE);
    assert.equal(items.length, 1);
    assert.equal(items[0].headline, "Ethereum upgrade ships");
    assert.equal(items[0].sourceName, "Example Crypto News");
    assert.equal(items[0].url, "https://example.com/eth-upgrade");
  });

  await t.test("returns an empty array for a malformed/unexpected body", () => {
    assert.deepEqual(CoinGeckoNewsProvider.parseResponse(null), []);
    assert.deepEqual(CoinGeckoNewsProvider.parseResponse({}), []);
    assert.deepEqual(CoinGeckoNewsProvider.parseResponse({ data: "not an array" }), []);
  });
});
