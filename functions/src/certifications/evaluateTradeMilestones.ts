import { onDocumentCreated } from "firebase-functions/v2/firestore";

import { db } from "../lib/admin";
import { awardCertificationIfNeeded } from "../lib/certifications";
import { MILESTONES } from "../lib/milestones";

/** Testable core: given a newly-created order, award the trade milestone
 * if it's now been earned. Split out from the trigger wrapper below so
 * emulator tests can call it directly without going through a real
 * Firestore-triggered event. */
export async function evaluateTradeMilestonesForOrder(
  userId: string,
  order: Record<string, unknown> | undefined,
): Promise<void> {
  // A "completed trade" is one that closed or reduced a position —
  // realized_pnl is set on exactly those orders (a SELL closing a long, or
  // a BUY covering a short), regardless of order_type.
  if (!order || order.realized_pnl == null) return;

  const completedTradesSnap = await db
    .collection(`users/${userId}/orders`)
    .where("realized_pnl", "!=", null)
    .count()
    .get();

  if (completedTradesSnap.data().count >= MILESTONES.disciplinedTrader.completedTradesThreshold) {
    await awardCertificationIfNeeded(userId, MILESTONES.disciplinedTrader.type);
  }
}

/**
 * Fires once per new order, not on every read — same count()-on-write
 * shape as updateSkillLevelOnOrder.ts.
 */
export const evaluateTradeMilestones = onDocumentCreated(
  "users/{userId}/orders/{orderId}",
  async (event) => {
    await evaluateTradeMilestonesForOrder(event.params.userId, event.data?.data());
  },
);
