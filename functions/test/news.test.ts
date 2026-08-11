// Pure-logic tests — no Firestore/emulator/live network involved. Feed
// parsing runs against a saved sample RSS XML string (inline below), never
// a live feed. Run via: npm run test:news
import { strict as assert } from "node:assert";
import test from "node:test";

import { Timestamp } from "firebase-admin/firestore";

import {
  buildNewsItem,
  computeNewsItemId,
  containsCryptoKeyword,
  parseFeedXml,
  truncateSummary,
} from "../src/news/newsParsing";
import { RssSourceConfig } from "../src/news/rssSources";

const SAMPLE_RSS = `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>Sample Crypto Feed</title>
    <link>https://example.com</link>
    <description>A saved sample feed used only for tests.</description>
    <item>
      <title>Bitcoin breaks past key resistance level</title>
      <link>https://example.com/articles/bitcoin-resistance</link>
      <guid>https://example.com/articles/bitcoin-resistance</guid>
      <pubDate>Mon, 10 Aug 2026 09:30:00 GMT</pubDate>
      <description>Bitcoin rallied past a closely-watched resistance level on Monday, extending its weekly gain.</description>
      <content:encoded><![CDATA[<p>Bitcoin rallied past a closely-watched resistance level on Monday, extending its weekly gain. This is the full, much longer article body that must NEVER be shown in the app -- it goes on for several more paragraphs describing market conditions, analyst commentary, historical context, and other copyrighted reporting that only the description field should ever surface to end users.</p>]]></content:encoded>
    </item>
    <item>
      <title>Regulators eye new stablecoin rules</title>
      <link>https://example.com/articles/stablecoin-rules</link>
      <guid>https://example.com/articles/stablecoin-rules</guid>
      <pubDate>Mon, 10 Aug 2026 08:00:00 GMT</pubDate>
      <description>Lawmakers proposed &amp; discussed a new framework for stablecoin issuers on Monday.</description>
    </item>
    <item>
      <title>Local bakery wins regional award</title>
      <link>https://example.com/articles/bakery-award</link>
      <guid>https://example.com/articles/bakery-award</guid>
      <pubDate>Mon, 10 Aug 2026 07:00:00 GMT</pubDate>
      <description>A neighborhood bakery took home a regional pastry award this weekend.</description>
    </item>
  </channel>
</rss>`;

const source: RssSourceConfig = {
  name: "Sample Source",
  url: "https://example.com/rss",
  category: "general",
  cryptoExclusive: true,
};

const mixedSource: RssSourceConfig = { ...source, cryptoExclusive: false };

test("computeNewsItemId", async (t) => {
  await t.test("is deterministic for the same link", () => {
    const link = "https://example.com/articles/bitcoin-resistance";
    assert.equal(computeNewsItemId(link), computeNewsItemId(link));
  });

  await t.test("differs for different links", () => {
    assert.notEqual(
      computeNewsItemId("https://example.com/a"),
      computeNewsItemId("https://example.com/b"),
    );
  });

  await t.test("is stable across repeated calls the way concurrent scheduled runs would rely on", () => {
    const link = "https://example.com/articles/stablecoin-rules";
    const ids = Array.from({ length: 5 }, () => computeNewsItemId(link));
    assert.ok(ids.every((id) => id === ids[0]));
  });
});

test("truncateSummary", async (t) => {
  await t.test("leaves a short string untouched", () => {
    assert.equal(truncateSummary("Short summary."), "Short summary.");
  });

  await t.test("strips HTML tags", () => {
    assert.equal(truncateSummary("<p>Hello <b>world</b></p>"), "Hello world");
  });

  await t.test("decodes common HTML entities", () => {
    assert.equal(truncateSummary("Fish &amp; chips &lt;now&gt;"), "Fish & chips <now>");
  });

  await t.test("truncates long text to ~150 chars at a word boundary, with an ellipsis", () => {
    const long = "word ".repeat(60).trim(); // 299 chars
    const result = truncateSummary(long);
    assert.ok(result.length <= 151, `expected <= 151 chars, got ${result.length}`);
    assert.ok(result.endsWith("…"));
    assert.ok(!result.slice(0, -1).endsWith(" ")); // no trailing space before the ellipsis
  });

  await t.test("applies the truncation margin even when the source's own text is already short-ish", () => {
    // 150 is the safety margin regardless of how "short" the source
    // considers its own summary — a caller-specified smaller maxLength
    // is still honored.
    const result = truncateSummary("This sentence is deliberately a bit long for the test.", 20);
    assert.ok(result.length <= 21, `expected <= 21 chars, got ${result.length}`);
  });
});

test("containsCryptoKeyword", async (t) => {
  await t.test("matches an obvious crypto headline", () => {
    assert.equal(containsCryptoKeyword("Bitcoin breaks past key resistance level"), true);
  });

  await t.test("is case-insensitive", () => {
    assert.equal(containsCryptoKeyword("ETHEREUM UPGRADE SHIPS"), true);
  });

  await t.test("rejects an unrelated headline", () => {
    assert.equal(containsCryptoKeyword("Local bakery wins regional award"), false);
  });
});

test("parseFeedXml + buildNewsItem against a saved sample feed", async (t) => {
  await t.test("extracts title, link, pubDate, and the short description only", async () => {
    const items = await parseFeedXml(SAMPLE_RSS);
    assert.equal(items.length, 3);

    const first = items[0];
    assert.equal(first.title, "Bitcoin breaks past key resistance level");
    assert.equal(first.link, "https://example.com/articles/bitcoin-resistance");
    assert.ok(first.pubDate);
  });

  await t.test(
    "NEVER surfaces content:encoded's full article body, even when a feed includes it",
    async () => {
      const items = await parseFeedXml(SAMPLE_RSS);
      const now = Timestamp.now();
      const built = buildNewsItem(items[0], source, now);

      assert.ok(built);
      assert.ok(!built!.summary.includes("goes on for several more paragraphs"));
      assert.ok(!built!.summary.includes("full, much longer article body"));
      assert.ok(built!.summary.startsWith("Bitcoin rallied past"));
    },
  );

  await t.test("truncates and HTML-decodes the description field", async () => {
    const items = await parseFeedXml(SAMPLE_RSS);
    const now = Timestamp.now();
    const built = buildNewsItem(items[1], source, now);

    assert.ok(built);
    assert.ok(built!.summary.includes("& discussed"));
    assert.ok(built!.summary.includes("new framework"));
    assert.ok(built!.summary.length <= 151);
  });

  await t.test("populates source_name/source_url/published_at/fetched_at correctly", async () => {
    const items = await parseFeedXml(SAMPLE_RSS);
    const now = Timestamp.now();
    const built = buildNewsItem(items[0], source, now);

    assert.ok(built);
    assert.equal(built!.source_name, "Sample Source");
    assert.equal(built!.source_url, "https://example.com/articles/bitcoin-resistance");
    assert.equal(built!.fetched_at, now);
    assert.equal(built!.published_at.toDate().toISOString(), "2026-08-10T09:30:00.000Z");
  });

  await t.test("a crypto-exclusive source keeps every item, even an unrelated one", async () => {
    const items = await parseFeedXml(SAMPLE_RSS);
    const now = Timestamp.now();
    const built = buildNewsItem(items[2], source, now); // the bakery item
    assert.ok(built, "crypto-exclusive sources should not be keyword-filtered");
  });

  await t.test("a mixed-content source drops an item with no crypto keyword in the title", async () => {
    const items = await parseFeedXml(SAMPLE_RSS);
    const now = Timestamp.now();
    const built = buildNewsItem(items[2], mixedSource, now); // the bakery item
    assert.equal(built, null);
  });

  await t.test("a mixed-content source keeps an item that does match a crypto keyword", async () => {
    const items = await parseFeedXml(SAMPLE_RSS);
    const now = Timestamp.now();
    const built = buildNewsItem(items[0], mixedSource, now); // "Bitcoin..."
    assert.ok(built);
  });

  await t.test("computeNewsItemId gives the same id for the same item across two parses (dedupe)", async () => {
    const firstParse = await parseFeedXml(SAMPLE_RSS);
    const secondParse = await parseFeedXml(SAMPLE_RSS);
    const idA = computeNewsItemId(firstParse[0].link!);
    const idB = computeNewsItemId(secondParse[0].link!);
    assert.equal(idA, idB);
  });

  await t.test("skips an item missing a title or link rather than throwing", async () => {
    const now = Timestamp.now();
    assert.equal(buildNewsItem({ title: "No link here" }, source, now), null);
    assert.equal(buildNewsItem({ link: "https://example.com/x" }, source, now), null);
  });
});
