// Behavioral test against the real Firestore emulator — run via:
//   npm run test:trader-profile
import { strict as assert } from "node:assert";
import test from "node:test";
import { Timestamp } from "firebase-admin/firestore";

import { db } from "../src/lib/admin";
import { recomputeStatsForUser } from "../src/traderProfile/recomputeTraderStats";
import { adjustFollowCounts } from "../src/traderProfile/onFollowChange";
import { syncProfileVisibilityForUser } from "../src/traderProfile/syncProfileVisibility";
import {
  recordTradeActivity,
  recordRationaleActivity,
  recordCertificationActivity,
} from "../src/traderProfile/publicActivity";

async function makeOrder(
  uid: string,
  orderId: string,
  overrides: Record<string, unknown> = {},
): Promise<void> {
  await db.doc(`users/${uid}/orders/${orderId}`).set({
    coin_symbol: "BTCUSDT",
    order_type: "SELL",
    price: 100,
    quantity: 1,
    realized_pnl: 10,
    timestamp: Timestamp.now(),
    ...overrides,
  });
}

test("recomputeStatsForUser", async (t) => {
  await t.test("writes derived stats without touching follower/following counts", async () => {
    const uid = `stats-${Date.now()}`;
    await db.doc(`users/${uid}`).set({ created_at: Timestamp.now() });
    // Pre-seed counters the way onFollowChange.ts would, to prove
    // recompute doesn't clobber them.
    await db.doc(`users/${uid}/profile_stats/data`).set({ follower_count: 7, following_count: 2 });
    await makeOrder(uid, "order-1", { realized_pnl: 25 });

    await recomputeStatsForUser(uid);

    const statsSnap = await db.doc(`users/${uid}/profile_stats/data`).get();
    const stats = statsSnap.data()!;
    assert.equal(stats.total_trades, 1);
    assert.equal(stats.win_rate_pct, 100);
    assert.equal(stats.accuracy_pct, 100);
    assert.equal(stats.follower_count, 7, "recompute must not touch follower_count");
    assert.equal(stats.following_count, 2, "recompute must not touch following_count");
  });
});

test("syncProfileVisibilityForUser", async (t) => {
  await t.test("copies is_public and display_name onto profile_stats", async () => {
    const uid = `sync-${Date.now()}`;
    await syncProfileVisibilityForUser(uid, { is_public: true, display_name: "Nova" });

    const stats = (await db.doc(`users/${uid}/profile_stats/data`).get()).data()!;
    assert.equal(stats.is_public, true);
    assert.equal(stats.display_name, "Nova");
  });

  await t.test("treats a missing/undefined is_public as false, not truthy", async () => {
    const uid = `sync-off-${Date.now()}`;
    await syncProfileVisibilityForUser(uid, { display_name: "Nova" });

    const stats = (await db.doc(`users/${uid}/profile_stats/data`).get()).data()!;
    assert.equal(stats.is_public, false);
  });

  await t.test("does not touch trade-derived or counter fields", async () => {
    const uid = `sync-preserve-${Date.now()}`;
    await db.doc(`users/${uid}/profile_stats/data`).set({
      discipline_score: 88,
      follower_count: 4,
    });

    await syncProfileVisibilityForUser(uid, { is_public: true, display_name: "Nova" });

    const stats = (await db.doc(`users/${uid}/profile_stats/data`).get()).data()!;
    assert.equal(stats.discipline_score, 88);
    assert.equal(stats.follower_count, 4);
  });
});

test("adjustFollowCounts", async (t) => {
  await t.test("increments the followed user's follower_count and the follower's following_count", async () => {
    const follower = `follower-${Date.now()}`;
    const followed = `followed-${Date.now()}`;

    await adjustFollowCounts(follower, followed, 1);

    const followerStats = (await db.doc(`users/${follower}/profile_stats/data`).get()).data()!;
    const followedStats = (await db.doc(`users/${followed}/profile_stats/data`).get()).data()!;
    assert.equal(followerStats.following_count, 1);
    assert.equal(followedStats.follower_count, 1);
  });

  await t.test("a matching -1 delta (unfollow) brings counts back to zero", async () => {
    const follower = `follower2-${Date.now()}`;
    const followed = `followed2-${Date.now()}`;

    await adjustFollowCounts(follower, followed, 1);
    await adjustFollowCounts(follower, followed, -1);

    const followerStats = (await db.doc(`users/${follower}/profile_stats/data`).get()).data()!;
    const followedStats = (await db.doc(`users/${followed}/profile_stats/data`).get()).data()!;
    assert.equal(followerStats.following_count, 0);
    assert.equal(followedStats.follower_count, 0);
  });
});

test("publicActivity", async (t) => {
  await t.test("recordTradeActivity is a no-op for a private profile", async () => {
    const uid = `activity-private-${Date.now()}`;
    await db.doc(`users/${uid}/profile_settings/data`).set({ is_public: false, display_name: "x" });

    await recordTradeActivity(uid, { order_type: "SELL", coin_symbol: "BTCUSDT", realized_pnl: 5 });

    const activitySnap = await db.collection(`users/${uid}/public_activity`).get();
    assert.equal(activitySnap.size, 0);
  });

  await t.test("recordTradeActivity writes a profit/loss/breakeven trade event for a public profile", async () => {
    const uid = `activity-public-${Date.now()}`;
    await db.doc(`users/${uid}/profile_settings/data`).set({ is_public: true, display_name: "x" });

    await recordTradeActivity(uid, { order_type: "SELL", coin_symbol: "ETHUSDT", realized_pnl: -5 });

    const activitySnap = await db.collection(`users/${uid}/public_activity`).get();
    assert.equal(activitySnap.size, 1);
    const activity = activitySnap.docs[0].data();
    assert.equal(activity.type, "trade");
    assert.equal(activity.coin_symbol, "ETHUSDT");
    assert.equal(activity.outcome, "loss");
  });

  await t.test("recordTradeActivity ignores an order that opened/added a position (no realized_pnl)", async () => {
    const uid = `activity-buy-${Date.now()}`;
    await db.doc(`users/${uid}/profile_settings/data`).set({ is_public: true, display_name: "x" });

    await recordTradeActivity(uid, { order_type: "BUY", coin_symbol: "BTCUSDT", realized_pnl: null });

    const activitySnap = await db.collection(`users/${uid}/public_activity`).get();
    assert.equal(activitySnap.size, 0);
  });

  await t.test("recordTradeActivity records a short-covering BUY the same as a closing SELL", async () => {
    const uid = `activity-cover-${Date.now()}`;
    await db.doc(`users/${uid}/profile_settings/data`).set({ is_public: true, display_name: "x" });

    await recordTradeActivity(uid, { order_type: "BUY", coin_symbol: "BTCUSDT", realized_pnl: 12 });

    const activitySnap = await db.collection(`users/${uid}/public_activity`).get();
    assert.equal(activitySnap.size, 1);
    const activity = activitySnap.docs[0].data();
    assert.equal(activity.type, "trade");
    assert.equal(activity.order_type, "BUY");
    assert.equal(activity.outcome, "profit");
  });

  await t.test("recordRationaleActivity looks up the order's coin_symbol", async () => {
    const uid = `activity-rationale-${Date.now()}`;
    await db.doc(`users/${uid}/profile_settings/data`).set({ is_public: true, display_name: "x" });
    await makeOrder(uid, "order-1", { coin_symbol: "SOLUSDT" });

    await recordRationaleActivity(uid, "order-1");

    const activitySnap = await db.collection(`users/${uid}/public_activity`).get();
    assert.equal(activitySnap.size, 1);
    const activity = activitySnap.docs[0].data();
    assert.equal(activity.type, "rationale");
    assert.equal(activity.order_id, "order-1");
    assert.equal(activity.coin_symbol, "SOLUSDT");
  });

  await t.test("recordCertificationActivity writes the milestone_type", async () => {
    const uid = `activity-cert-${Date.now()}`;
    await db.doc(`users/${uid}/profile_settings/data`).set({ is_public: true, display_name: "x" });

    await recordCertificationActivity(uid, { milestone_type: "backtester_master" });

    const activitySnap = await db.collection(`users/${uid}/public_activity`).get();
    assert.equal(activitySnap.size, 1);
    assert.equal(activitySnap.docs[0].data().type, "certification");
    assert.equal(activitySnap.docs[0].data().milestone_type, "backtester_master");
  });
});
