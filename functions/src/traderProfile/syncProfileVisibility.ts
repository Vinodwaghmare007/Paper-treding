import { onDocumentWritten } from "firebase-functions/v2/firestore";

import { db } from "../lib/admin";

/**
 * Testable core: mirrors is_public/display_name from profile_settings
 * onto profile_stats.
 *
 * Two reasons this exists rather than having compute_leaderboard.ts join
 * against profile_settings directly: (1) it lets the leaderboard's
 * collectionGroup query filter on profile_stats alone, with no per-entry
 * get() against a second collection; (2) it's what makes opting a profile
 * OUT take effect immediately — recomputeTraderStats.ts's on-write/daily
 * triggers only ever touch trade-derived fields, so without this, turning
 * is_public off wouldn't be reflected on profile_stats until whatever
 * happened to next recompute it, leaving a stale "still public" copy
 * readable (and possibly still leaderboard-eligible) in the meantime.
 */
export async function syncProfileVisibilityForUser(
  userId: string,
  after: Record<string, unknown> | undefined,
): Promise<void> {
  await db.doc(`users/${userId}/profile_stats/data`).set(
    {
      is_public: after?.is_public === true,
      display_name: (after?.display_name as string | undefined) ?? null,
    },
    { merge: true },
  );
}

export const syncProfileVisibility = onDocumentWritten(
  "users/{userId}/profile_settings/data",
  async (event) => {
    await syncProfileVisibilityForUser(event.params.userId, event.data?.after.data());
  },
);
