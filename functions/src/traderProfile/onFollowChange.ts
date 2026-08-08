import { onDocumentCreated, onDocumentDeleted } from "firebase-functions/v2/firestore";
import { FieldValue } from "firebase-admin/firestore";

import { db } from "../lib/admin";

/**
 * Testable core: atomically adjusts both sides of a follow relationship's
 * denormalized counters. FieldValue.increment on a `set(..., {merge:true})`
 * works even if profile_stats/data doesn't exist yet (e.g. a brand-new
 * account being followed before their first trade) — Firestore treats a
 * missing numeric field as 0 for increment's purposes.
 */
export async function adjustFollowCounts(
  followerId: string,
  followedId: string,
  delta: 1 | -1,
): Promise<void> {
  await Promise.all([
    db.doc(`users/${followerId}/profile_stats/data`).set(
      { following_count: FieldValue.increment(delta) },
      { merge: true },
    ),
    db.doc(`users/${followedId}/profile_stats/data`).set(
      { follower_count: FieldValue.increment(delta) },
      { merge: true },
    ),
  ]);
}

/**
 * `users/{followerId}/following/{followedId}` is the client-writable
 * relationship doc (see firestore.rules); the counters themselves are
 * never client-writable at all — only these atomic on-write/on-delete
 * triggers touch them, so a client can't inflate its own follower_count
 * by writing profile_stats directly.
 */
export const onFollowCreated = onDocumentCreated(
  "users/{followerId}/following/{followedId}",
  async (event) => {
    await adjustFollowCounts(event.params.followerId, event.params.followedId, 1);
  },
);

export const onFollowDeleted = onDocumentDeleted(
  "users/{followerId}/following/{followedId}",
  async (event) => {
    await adjustFollowCounts(event.params.followerId, event.params.followedId, -1);
  },
);
