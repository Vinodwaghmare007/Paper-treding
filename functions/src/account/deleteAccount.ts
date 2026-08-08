import { HttpsError, onCall } from "firebase-functions/v2/https";
import { getAuth } from "firebase-admin/auth";

import { db } from "../lib/admin";

const BATCH_SIZE = 400; // headroom under Firestore's 500-writes-per-batch cap

/** Deletes every doc matching [query], paging through in batches rather
 * than a single unbounded batch (a long-lived chatty user could easily
 * have more than 500 messages, which would blow past Firestore's
 * per-batch write limit). */
async function deleteAllMatching(query: FirebaseFirestore.Query): Promise<void> {
  for (;;) {
    const snap = await query.limit(BATCH_SIZE).get();
    if (snap.empty) return;
    const batch = db.batch();
    snap.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
    if (snap.size < BATCH_SIZE) return;
  }
}

/**
 * Permanently deletes a user's account and the data that's clearly
 * "theirs": trading history (orders/portfolio), the account doc itself,
 * rate-limit state, and every chat message they authored across every
 * room (a collectionGroup query, since those live under shared
 * chat_rooms/{roomId}/messages, not under the user's own doc).
 *
 * Deliberately NOT touched:
 * - `reports/{reportId}` where reported_by == uid — moderation records
 *   about content this user *reported*, not their own content; kept for
 *   moderation integrity, same as most platforms retain moderation logs
 *   past account deletion. They were never client-readable in the first
 *   place (see firestore.rules), so nothing is newly exposed by keeping
 *   them.
 * - `public_sentiment`, `public_cohort_medians`, daily_puzzle aggregate
 *   counters — already-anonymized aggregates with no per-user
 *   attribution; there's no "this user's part" to individually remove
 *   from a number that's already just a count.
 *
 * This is a callable (Admin SDK, bypasses firestore.rules) rather than a
 * client-side batch delete for the same reason as sendChatMessage.ts /
 * submitPuzzleAnswer.ts: `orders` is an append-only ledger from the
 * client's perspective (`allow update, delete: if false` in
 * firestore.rules) specifically so nobody can quietly edit their own
 * trade history — deletion-on-account-deletion is the one legitimate
 * exception, and routing it through a server-side function that also
 * deletes the Auth account itself (so there's no way to trigger this and
 * keep using the account) is what keeps that exception from becoming a
 * loophole.
 *
 * The Auth account is deleted last, deliberately: if anything above
 * throws, the user still has a working (if partially-cleaned-up) account
 * rather than a deleted Auth identity with orphaned Firestore data, and a
 * client that retries after a failure just finds those docs already gone
 * (deleting an already-deleted doc is a no-op).
 */
/** The actual deletion logic, factored out from the onCall wrapper below
 * so it can be exercised directly against the Firestore/Auth emulators in
 * test/deleteAccount.test.ts without needing the (heavier, slower)
 * Functions emulator just to construct a callable request. */
export async function deleteAccountForUser(uid: string): Promise<void> {
  await deleteAllMatching(db.collection(`users/${uid}/orders`));
  await deleteAllMatching(db.collection(`users/${uid}/portfolio`));
  await deleteAllMatching(db.collectionGroup("messages").where("user_id", "==", uid));

  await db.doc(`chat_rate_limits/${uid}`).delete();
  await db.doc(`users/${uid}`).delete();

  await getAuth().deleteUser(uid);
}

export const deleteAccount = onCall(async (request) => {
  const auth = request.auth;
  if (!auth) {
    throw new HttpsError("unauthenticated", "Sign in to delete your account.");
  }
  await deleteAccountForUser(auth.uid);
  return { deleted: true };
});
