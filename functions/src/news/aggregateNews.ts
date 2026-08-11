import { onSchedule } from "firebase-functions/v2/scheduler";
import { Timestamp } from "firebase-admin/firestore";

import { db } from "../lib/admin";
import { buildNewsItem, NewsItemData, computeNewsItemId, parseFeedXml } from "./newsParsing";
import { fetchRssSourceConfigs, RssSourceConfig } from "./rssSources";

const FIRESTORE_BATCH_LIMIT = 500;
const NEWS_RETENTION_DAYS = 14;
/** Safety cap on how many prune batches run per invocation (up to 2500
 * stale docs/run) — this job runs every ~25 minutes, so a backlog this
 * large should never actually accumulate; the cap just bounds a single
 * run's worst case rather than looping unboundedly. */
const MAX_PRUNE_BATCHES_PER_RUN = 5;

async function fetchFeedXml(url: string): Promise<string> {
  const response = await fetch(url, {
    headers: {
      // A distinctive, contactable UA — some publishers rate-limit or
      // reject requests with no/generic User-Agent.
      "User-Agent":
        "CryptoPaperTraderNewsBot/1.0 (+https://vinodwaghmare007.github.io/Paper-treding/)",
    },
  });
  if (!response.ok) {
    throw new Error(`HTTP ${response.status} fetching ${url}`);
  }
  return response.text();
}

function chunk<T>(items: T[], size: number): T[][] {
  const chunks: T[][] = [];
  for (let i = 0; i < items.length; i += size) {
    chunks.push(items.slice(i, i + size));
  }
  return chunks;
}

/** Blind idempotent upsert by the deterministic link-hash doc ID — no
 * existence check beforehand. Two concurrent runs (or the same item
 * re-appearing on the next poll, which RSS feeds always do) both converge
 * on the exact same doc ID and simply overwrite each other's write with
 * equivalent data; there is no read-then-write race window to protect
 * against, which is the whole point of hashing the link into the ID
 * instead of querying for an existing doc first. */
async function writeNewsItems(items: NewsItemData[]): Promise<void> {
  for (const group of chunk(items, FIRESTORE_BATCH_LIMIT)) {
    const batch = db.batch();
    for (const item of group) {
      const ref = db.collection("news_items").doc(computeNewsItemId(item.source_url));
      batch.set(ref, item);
    }
    await batch.commit();
  }
}

/** Deletes news_items older than NEWS_RETENTION_DAYS. Returns how many
 * were deleted (0 in the common case once the collection is caught up). */
async function pruneOldNewsItems(now: Timestamp): Promise<number> {
  const cutoff = Timestamp.fromMillis(now.toMillis() - NEWS_RETENTION_DAYS * 24 * 60 * 60 * 1000);
  let deleted = 0;

  for (let i = 0; i < MAX_PRUNE_BATCHES_PER_RUN; i++) {
    const staleSnap = await db
      .collection("news_items")
      .where("published_at", "<", cutoff)
      .limit(FIRESTORE_BATCH_LIMIT)
      .get();
    if (staleSnap.empty) break;

    const batch = db.batch();
    for (const doc of staleSnap.docs) {
      batch.delete(doc.ref);
    }
    await batch.commit();
    deleted += staleSnap.size;

    if (staleSnap.size < FIRESTORE_BATCH_LIMIT) break; // caught up
  }

  return deleted;
}

/**
 * Testable core: fetches every configured RSS source, parses + filters +
 * truncates each item, writes them all, and prunes anything past
 * retention. Each source is wrapped in its own try/catch — one dead or
 * malformed feed is logged and skipped, never allowed to stop the
 * remaining sources from updating or to fail the whole scheduled run.
 */
export async function aggregateAllFeeds(
  options: { now?: Timestamp; sources?: RssSourceConfig[] } = {},
): Promise<{ written: number; failedSources: string[]; pruned: number }> {
  const now = options.now ?? Timestamp.now();
  const sources = options.sources ?? (await fetchRssSourceConfigs());

  const allItems: NewsItemData[] = [];
  const failedSources: string[] = [];

  for (const source of sources) {
    try {
      const xml = await fetchFeedXml(source.url);
      const rawItems = await parseFeedXml(xml);
      for (const rawItem of rawItems) {
        const built = buildNewsItem(rawItem, source, now);
        if (built) allItems.push(built);
      }
    } catch (e) {
      const message = e instanceof Error ? e.message : String(e);
      console.error(`[aggregateCryptoNews] source "${source.name}" failed, skipping:`, message);
      failedSources.push(source.name);
    }
  }

  await writeNewsItems(allItems);
  const pruned = await pruneOldNewsItems(now);

  console.log(
    `[aggregateCryptoNews] wrote ${allItems.length} item(s) from ${sources.length - failedSources.length}/${sources.length} source(s), pruned ${pruned} stale item(s)`,
  );

  return { written: allItems.length, failedSources, pruned };
}

export const aggregateCryptoNews = onSchedule(
  { schedule: "every 25 minutes", timeZone: "UTC" },
  async () => {
    await aggregateAllFeeds();
  },
);
