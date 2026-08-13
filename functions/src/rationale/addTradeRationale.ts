import { HttpsError, onCall } from "firebase-functions/v2/https";
import { Timestamp } from "firebase-admin/firestore";

import { db } from "../lib/admin";
import { filterMessage } from "../chat/profanityFilter";
import { containsForwardLookingLanguage } from "./forwardLookingPhrases";

const MAX_LENGTH = 280;

/**
 * Testable core — a callable Cloud Function rather than a direct client
 * Firestore write, same reasoning as sendChatMessage.ts: the two things
 * that actually make Trade Rationale retrospective-only (order must be a
 * closed SELL; the note's timestamp must be after the order's) need to be
 * enforced somewhere the client can't simply skip, and the content filter
 * needs real string processing rules alone can't do. See
 * firestore.rules's `rationale` match block (write: false) — this
 * callable, using the Admin SDK, is the only path that can ever write one.
 *
 * `now` is injectable so tests can exercise the pre-close rejection
 * deterministically instead of racing the real clock.
 */
export async function addTradeRationaleForUser(
  userId: string,
  orderId: string,
  rawText: string,
  { now }: { now?: Timestamp } = {},
): Promise<{ flagged: boolean }> {
  const text = rawText.trim();
  if (text.length === 0) {
    throw new HttpsError("invalid-argument", "Rationale can't be empty.");
  }
  if (text.length > MAX_LENGTH) {
    throw new HttpsError(
      "invalid-argument",
      `Rationale must be ${MAX_LENGTH} characters or fewer.`,
    );
  }

  const filterResult = filterMessage(text);
  if (!filterResult.allowed) {
    throw new HttpsError("invalid-argument", filterResult.reason ?? "Rationale rejected.");
  }

  const orderSnap = await db.doc(`users/${userId}/orders/${orderId}`).get();
  if (!orderSnap.exists) {
    throw new HttpsError("not-found", "That trade doesn't exist.");
  }
  const order = orderSnap.data()!;

  // "Closed trade" in this schema means realized_pnl is set — a SELL that
  // closed a long, or (short-selling) a BUY that covered a short. See
  // updateSkillLevelOnOrder.ts's identical convention. An order that
  // opened/added to a position has nothing to be retrospective about yet.
  if (order.realized_pnl == null) {
    throw new HttpsError(
      "failed-precondition",
      "A rationale can only be added to a closed trade, not an open position.",
    );
  }

  const effectiveNow = now ?? Timestamp.now();
  const orderTimestamp = order.timestamp as Timestamp;
  if (effectiveNow.toMillis() <= orderTimestamp.toMillis()) {
    throw new HttpsError(
      "failed-precondition",
      "A rationale must be added after the trade has closed.",
    );
  }

  const flagged = containsForwardLookingLanguage(text);

  // A fixed doc ID ("note") rather than an auto ID: one rationale per
  // trade, and re-submitting (an edit) overwrites it via the same
  // validated path rather than needing a separate update codepath.
  //
  // user_id and coin_symbol are redundant with the doc's own path/order
  // (the path already implies which user and order this belongs to) but
  // are what let trader_profile_screen.dart list a visited trader's
  // rationale notes via a `collectionGroup('rationale').where('user_id',
  // ...)` query and show which coin each note is about — a visitor's
  // security rules grant read access to this rationale doc but not to
  // the order doc itself (orders/{orderId} is owner-only), so the coin
  // symbol has to live here to be visible at all.
  await db.doc(`users/${userId}/orders/${orderId}/rationale/note`).set({
    text,
    created_at: effectiveNow,
    flagged_for_review: flagged,
    user_id: userId,
    coin_symbol: order.coin_symbol,
  });

  return { flagged };
}

export const addTradeRationale = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }

  const orderId = request.data?.orderId;
  const text = request.data?.text;
  if (typeof orderId !== "string" || orderId.length === 0) {
    throw new HttpsError("invalid-argument", "orderId is required.");
  }
  if (typeof text !== "string") {
    throw new HttpsError("invalid-argument", "text is required.");
  }

  return addTradeRationaleForUser(uid, orderId, text);
});
