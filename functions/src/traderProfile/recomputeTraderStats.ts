import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { Timestamp } from "firebase-admin/firestore";

import { db } from "../lib/admin";
import { isPublicProfile } from "../lib/profileVisibility";
import { computeTraderStats, TraderOrderInput } from "../lib/traderStats";

async function fetchOrdersForUser(userId: string): Promise<TraderOrderInput[]> {
  const snap = await db.collection(`users/${userId}/orders`).get();
  return snap.docs.map((doc) => {
    const data = doc.data();
    return {
      orderType: data.order_type as "BUY" | "SELL",
      coinSymbol: data.coin_symbol as string,
      realizedPnl: (data.realized_pnl as number | undefined) ?? null,
      timestampMs: (data.timestamp as Timestamp).toMillis(),
    };
  });
}

/**
 * Testable core: recomputes and writes `profile_stats/data` for one user.
 * Deliberately does NOT touch follower_count/following_count (owned
 * exclusively by onFollowChange.ts's atomic increments) or
 * is_public/display_name (owned by syncProfileVisibility.ts) — this only
 * ever sets the fields actually derived from trade history, via merge, so
 * it can never clobber those.
 */
export async function recomputeStatsForUser(userId: string): Promise<void> {
  const orders = await fetchOrdersForUser(userId);
  const stats = computeTraderStats(orders);

  const userSnap = await db.doc(`users/${userId}`).get();
  const memberSince = userSnap.data()?.created_at ?? null;

  await db.doc(`users/${userId}/profile_stats/data`).set(
    {
      accuracy_pct: stats.accuracyPct,
      win_rate_pct: stats.winRatePct,
      discipline_score: stats.disciplineScore,
      total_trades: stats.totalTrades,
      member_since: memberSince,
      last_trade_at: stats.lastTradeAtMs != null ? Timestamp.fromMillis(stats.lastTradeAtMs) : null,
      updated_at: Timestamp.now(),
    },
    { merge: true },
  );
}

/**
 * On-demand recompute right after a closed (SELL) trade — "significant
 * trade activity," per the spec. Gated on the profile already being
 * public so a private account's trading never pays for work nobody will
 * ever read; syncProfileVisibility.ts handles the moment a profile
 * *becomes* public separately (see that file).
 */
export const recomputeTraderStatsOnOrder = onDocumentCreated(
  "users/{userId}/orders/{orderId}",
  async (event) => {
    const order = event.data?.data();
    if (!order || order.order_type !== "SELL") return;

    const userId = event.params.userId;
    if (!(await isPublicProfile(userId))) return;
    await recomputeStatsForUser(userId);
  },
);

/**
 * Daily sweep over every currently-public profile — a safety net for
 * anything the on-write trigger above might have missed (a transient
 * failure, or a profile that went public between trades), not the primary
 * mechanism. Bounded by the number of public profiles, not total users.
 */
export const recomputeTraderStatsDaily = onSchedule("every 24 hours", async () => {
  const publicSettings = await db
    .collectionGroup("profile_settings")
    .where("is_public", "==", true)
    .get();

  await Promise.all(
    publicSettings.docs.map((doc) => recomputeStatsForUser(doc.ref.parent.parent!.id)),
  );
});
