import { createHash } from "node:crypto";

import Parser from "rss-parser";
import { Timestamp } from "firebase-admin/firestore";

import { RssSourceConfig } from "./rssSources";

/** Deterministic doc ID for `news_items/{itemId}` — same link always hashes
 * to the same id, so a blind `.set()` from two concurrent scheduled runs
 * (or the same item re-appearing in a feed on every poll) is naturally
 * idempotent: no pre-existence read, no race window, per the requirement
 * that dedupe must be robust across concurrent runs. SHA-256 hex (64
 * chars) is well within Firestore's document-ID limits and collision risk
 * is not a practical concern at this app's scale. */
export function computeNewsItemId(link: string): string {
  return createHash("sha256").update(link.trim()).digest("hex");
}

const CRYPTO_KEYWORDS = [
  "bitcoin", "btc", "crypto", "cryptocurrency", "ethereum", "eth",
  "blockchain", "defi", "nft", "web3", "altcoin", "token", "stablecoin",
  "binance", "coinbase", "solana", "dogecoin", "xrp", "ripple", "ledger",
  "mining", "wallet", "exchange", "satoshi",
];

/** Only meant for a source NOT already flagged `cryptoExclusive` — see
 * RssSourceConfig. Every bundled default source today is crypto-only, so
 * this only actually filters anything once a mixed-content source is
 * added via Remote Config. */
export function containsCryptoKeyword(title: string): boolean {
  const lower = title.toLowerCase();
  return CRYPTO_KEYWORDS.some((kw) => lower.includes(kw));
}

const HTML_TAG_RE = /<[^>]*>/g;
const COMMON_ENTITIES: Record<string, string> = {
  "&amp;": "&",
  "&lt;": "<",
  "&gt;": ">",
  "&quot;": '"',
  "&#39;": "'",
  "&apos;": "'",
  "&nbsp;": " ",
};

function decodeCommonEntities(text: string): string {
  return text.replace(/&(amp|lt|gt|quot|#39|apos|nbsp);/g, (m) => COMMON_ENTITIES[m] ?? m);
}

/** Strips HTML tags and truncates to [maxLength], cutting at the last full
 * word rather than mid-word — an extra copyright safety margin applied
 * server-side REGARDLESS of how short a source's own summary/description
 * field already is (never rely solely on "the source's own summary is
 * short enough"). */
export function truncateSummary(raw: string, maxLength = 150): string {
  const plain = decodeCommonEntities(raw.replace(HTML_TAG_RE, " "))
    .replace(/\s+/g, " ")
    .trim();
  if (plain.length <= maxLength) return plain;

  const cut = plain.slice(0, maxLength);
  const lastSpace = cut.lastIndexOf(" ");
  const wordBoundary = lastSpace > 0 ? cut.slice(0, lastSpace) : cut;
  return `${wordBoundary.trimEnd()}…`;
}

/**
 * Parses raw RSS/Atom XML into rss-parser's item list. Kept separate from
 * the HTTP fetch (see aggregateNews.ts's fetchFeedXml) specifically so
 * this can be unit-tested against a saved sample XML string with no
 * network involved.
 */
export async function parseFeedXml(xml: string): Promise<Parser.Item[]> {
  const parser = new Parser();
  const feed = await parser.parseString(xml);
  return feed.items;
}

export interface NewsItemData {
  headline: string;
  summary: string;
  source_name: string;
  source_url: string;
  published_at: Timestamp;
  fetched_at: Timestamp;
}

/**
 * Maps one rss-parser item to the exact shape stored in Firestore, or null
 * if the item should be skipped (missing the fields needed to display/
 * dedupe it, or fails the crypto-keyword filter for a mixed-content
 * source).
 *
 * SUMMARY FIELD — READ THIS BEFORE CHANGING: `item.summary` and
 * `item.contentSnippet`/`item.content` are safe short-summary fields.
 * `item['content:encoded']` and `item['content:encodedSnippet']` are NOT
 * safe — verified directly against the installed rss-parser source
 * (lib/parser.js + lib/fields.js): an RSS `<content:encoded>` tag (full
 * article body, when a feed includes one) is copied to the separate key
 * `content:encoded`/`content:encodedSnippet`, never to `.content`/
 * `.contentSnippet` — those two are populated ONLY from the short
 * `<description>` tag for RSS feeds (Atom feeds populate `.content` from
 * `<content>`, which is why `.summary`, sourced from Atom's `<summary>`,
 * is tried first below). This function must never read
 * `item['content:encoded']` or `item['content:encodedSnippet']`.
 */
export function buildNewsItem(
  item: Parser.Item,
  source: RssSourceConfig,
  now: Timestamp,
): NewsItemData | null {
  const title = item.title?.trim();
  const link = item.link?.trim();
  if (!title || !link) return null;

  if (!source.cryptoExclusive && !containsCryptoKeyword(title)) {
    return null;
  }

  const rawSummary = item.summary || item.contentSnippet || item.content || "";
  const summary = truncateSummary(rawSummary);

  const pubDateMs = item.pubDate ? Date.parse(item.pubDate) : NaN;
  const publishedAt = Number.isFinite(pubDateMs) ? Timestamp.fromMillis(pubDateMs) : now;

  return {
    headline: title,
    summary,
    source_name: source.name,
    source_url: link,
    published_at: publishedAt,
    fetched_at: now,
  };
}
