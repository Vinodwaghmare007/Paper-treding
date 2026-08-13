import { onSchedule } from "firebase-functions/v2/scheduler";
import { Timestamp } from "firebase-admin/firestore";

import { db } from "../lib/admin";
import { buildNewsItem, computeNewsItemId, NewsItemData } from "./newsItems";
import { NewsProvider } from "./newsProvider";
import { RssNewsProvider } from "./rssNewsProvider";

const FIRESTORE_BATCH_LIMIT = 500;
const NEWS_RETENTION_DAYS = 14;
/** Safety cap on how many prune batches run per invocation (up to 2500
 * stale docs/run) — this job runs every ~25 minutes, so a backlog this
 * large should never actually accumulate; the cap just bounds a single
 * run's worst case rather than looping unboundedly. */
const MAX_PRUNE_BATCHES_PER_RUN = 5;

function chunk<T>(items: T[], size: number): T[][] {
  const chunks: T[][] = [];
  for (let i = 0; i < items.length; i += size) {
    chunks.push(items.slice(i, i + size));
  }
  return chunks;
}

/** Blind idempotent upsert by the deterministic url-hash doc ID — no
 * existence check beforehand. Two concurrent runs (or the same item
 * reappearing on the next poll) converge on the same doc ID and simply
 * overwrite each other's equivalent write; there's no read-then-write
 * race window to protect against. */
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
 * Testable core: fetches from whichever [provider] is passed in, builds
 * + truncates + writes every item, and prunes anything past retention.
 * Deliberately does NOT catch the provider's own fetch errors — those
 * propagate to the caller (the scheduled handler below), which is what
 * decides how to log/record a failed run, per the "log clearly and skip
 * this run, never crash or leave partial writes" requirement: nothing is
 * written at all if fetchLatestNews() throws, since that happens before
 * any Firestore call in this function.
 */
export async function fetchAndStoreNews(
  provider: NewsProvider,
  options: { now?: Timestamp } = {},
): Promise<{ written: number; pruned: number }> {
  const now = options.now ?? Timestamp.now();

  const rawItems = await provider.fetchLatestNews();
  const built: NewsItemData[] = [];
  for (const raw of rawItems) {
    const item = buildNewsItem(raw, now);
    if (item) built.push(item);
  }

  await writeNewsItems(built);
  const pruned = await pruneOldNewsItems(now);
  return { written: built.length, pruned };
}

const PIPELINE_STATUS_PATH = "news_pipeline_status/state";
/** How many consecutive failed runs before the log line escalates to an
 * ALERT-tagged message. Wire a Cloud Logging log-based metric matching
 * that exact string to an Alerting policy so a silently-broken news feed
 * doesn't go unnoticed for days — see docs/RELEASE.md. */
const CONSECUTIVE_FAILURE_ALERT_THRESHOLD = 3;

async function recordNewsRunSuccess(now: Timestamp): Promise<void> {
  await db.doc(PIPELINE_STATUS_PATH).set(
    { consecutive_failures: 0, last_success_at: now },
    { merge: true },
  );
}

async function recordNewsRunFailure(now: Timestamp, errorMessage: string): Promise<number> {
  const ref = db.doc(PIPELINE_STATUS_PATH);
  const snap = await ref.get();
  const consecutiveFailures =
    ((snap.data()?.consecutive_failures as number | undefined) ?? 0) + 1;

  await ref.set(
    { consecutive_failures: consecutiveFailures, last_failure_at: now, last_error: errorMessage },
    { merge: true },
  );
  return consecutiveFailures;
}

export const aggregateCryptoNews = onSchedule(
  { schedule: "every 25 minutes", timeZone: "UTC" },
  async () => {
    const now = Timestamp.now();

    // ACTIVE PROVIDER — RSS, the only one of the three confirmed
    // genuinely free. CoinGecko's News endpoint was never confirmed to
    // exist (coinGeckoNewsProvider.ts). CryptoPanic's API turned out to
    // require a paid plan (cryptoPanicNewsProvider.ts) — confirmed live,
    // not just unverified: every plan tier on their v2 docs sits behind
    // "Get PLUS", with no free API-key path found anywhere in the
    // account UI. No secret/API key is needed for this provider at all.
    // Swapping providers again requires no changes below this line
    // beyond constructing a different one — that's the entire point of
    // the NewsProvider interface.
    const provider: NewsProvider = new RssNewsProvider();

    try {
      const { written, pruned } = await fetchAndStoreNews(provider, { now });
      await recordNewsRunSuccess(now);
      console.log(
        `[aggregateCryptoNews] wrote ${written} item(s) via ${provider.name}, pruned ${pruned} stale item(s)`,
      );
    } catch (e) {
      // Logged and skipped, never rethrown — a failed run must not crash
      // the scheduled invocation or leave partial writes (fetchAndStoreNews
      // never reaches its Firestore writes if the provider call itself
      // throws, so there's nothing partial to clean up here).
      const message = e instanceof Error ? e.message : String(e);
      const consecutiveFailures = await recordNewsRunFailure(now, message);

      if (consecutiveFailures >= CONSECUTIVE_FAILURE_ALERT_THRESHOLD) {
        console.error(
          `[aggregateCryptoNews] ALERT: ${consecutiveFailures} consecutive failed runs. Last error: ${message}`,
        );
      } else {
        console.error(
          `[aggregateCryptoNews] run failed (${consecutiveFailures} consecutive so far): ${message}`,
        );
      }
    }
  },
);
