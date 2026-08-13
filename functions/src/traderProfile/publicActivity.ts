import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { Timestamp } from "firebase-admin/firestore";

import { db } from "../lib/admin";
import { isPublicProfile } from "../lib/profileVisibility";

/**
 * Small, factual activity log powering following_feed_screen.dart —
 * written here, never client-writable (see firestore.rules). Only three
 * event shapes exist, matching what's actually verifiable from this
 * app's own server-side data:
 *
 *   - "trade": a closed/covered order (realized_pnl set — a SELL closing
 *     a long, or a BUY covering a short) — symbol, side, and win/loss/
 *     breakeven outcome only. No forward guidance, no price target.
 *   - "rationale": a Trade Rationale was posted on a specific closed
 *     trade (Phase 8 Part C) — references the trade, not its text, so
 *     the feed itself never surfaces free-text content directly; a
 *     visitor taps through to the trade to read it.
 *   - "certification": a Phase 7 micro-certification was earned.
 *
 * The spec also lists a 4th type, "hit a milestone (e.g. discipline
 * streak)" — not implemented. This app has no existing data model for a
 * "discipline streak" distinct from the certifications above (which
 * already includes "50 Disciplined Trades"), and inventing a new
 * streak-tracking mechanism wasn't specified precisely enough to build
 * responsibly. Certifications are the one concrete "milestone" concept
 * this schema actually has.
 *
 * No pruning job: reads are bounded by following_feed_screen.dart's
 * per-user query limit, not by capping what's stored here. If storage
 * ever becomes a real concern, a scheduled prune (keep the most recent
 * N per user) would be the next step — not needed at this app's scale.
 */

async function writeActivity(userId: string, activity: Record<string, unknown>): Promise<void> {
  if (!(await isPublicProfile(userId))) return;
  await db.collection(`users/${userId}/public_activity`).add({
    ...activity,
    created_at: Timestamp.now(),
  });
}

/** Testable core for the order-created trigger. */
export async function recordTradeActivity(
  userId: string,
  order: Record<string, unknown> | undefined,
): Promise<void> {
  if (!order || order.realized_pnl == null) return;

  const pnl = order.realized_pnl as number;
  const outcome = pnl > 0 ? "profit" : pnl < 0 ? "loss" : "breakeven";

  await writeActivity(userId, {
    type: "trade",
    coin_symbol: order.coin_symbol,
    order_type: order.order_type,
    outcome,
  });
}

/** Testable core for the rationale-created trigger. */
export async function recordRationaleActivity(userId: string, orderId: string): Promise<void> {
  const orderSnap = await db.doc(`users/${userId}/orders/${orderId}`).get();
  const coinSymbol = orderSnap.data()?.coin_symbol ?? null;

  await writeActivity(userId, {
    type: "rationale",
    order_id: orderId,
    coin_symbol: coinSymbol,
  });
}

/** Testable core for the certification-created trigger. */
export async function recordCertificationActivity(
  userId: string,
  cert: Record<string, unknown> | undefined,
): Promise<void> {
  if (!cert) return;
  await writeActivity(userId, {
    type: "certification",
    milestone_type: cert.milestone_type,
  });
}

export const publicActivityOnTrade = onDocumentCreated(
  "users/{userId}/orders/{orderId}",
  async (event) => {
    await recordTradeActivity(event.params.userId, event.data?.data());
  },
);

export const publicActivityOnRationale = onDocumentCreated(
  "users/{userId}/orders/{orderId}/rationale/{noteId}",
  async (event) => {
    await recordRationaleActivity(event.params.userId, event.params.orderId);
  },
);

export const publicActivityOnCertification = onDocumentCreated(
  "users/{userId}/certifications/{certId}",
  async (event) => {
    await recordCertificationActivity(event.params.userId, event.data?.data());
  },
);
