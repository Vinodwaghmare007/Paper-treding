import { createHash } from "node:crypto";

import { Timestamp } from "firebase-admin/firestore";

import { NewsProviderItem } from "./newsProvider";

/** Deterministic doc ID for `news_items/{itemId}` — same article URL
 * always hashes to the same id, so a blind `.set()` from two concurrent
 * scheduled runs (or the same item re-appearing in the next poll) is
 * naturally idempotent: no pre-existence read, no race window. SHA-256
 * hex (64 chars) is well within Firestore's document-ID limits. */
export function computeNewsItemId(url: string): string {
  return createHash("sha256").update(url.trim()).digest("hex");
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

/** Strips any HTML tags and truncates to [maxLength], cutting at the last
 * full word rather than mid-word — an extra copyright safety margin
 * applied server-side REGARDLESS of how short a provider's own summary
 * field already is (never rely solely on "the provider's summary is
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

export interface NewsItemData {
  headline: string;
  summary: string;
  source_name: string;
  source_url: string;
  published_at: Timestamp;
  fetched_at: Timestamp;
}

/** Maps one provider-agnostic item to the exact shape stored in
 * Firestore, or null if it's missing what's needed to display/dedupe it
 * (a headline or a url). */
export function buildNewsItem(item: NewsProviderItem, now: Timestamp): NewsItemData | null {
  const headline = item.headline.trim();
  const url = item.url.trim();
  if (!headline || !url) return null;

  return {
    headline,
    summary: truncateSummary(item.summary),
    source_name: item.sourceName,
    source_url: url,
    published_at:
      item.publishedAtMs !== undefined ? Timestamp.fromMillis(item.publishedAtMs) : now,
    fetched_at: now,
  };
}
