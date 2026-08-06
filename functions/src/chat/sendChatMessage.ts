import { HttpsError, onCall } from "firebase-functions/v2/https";
import { Timestamp } from "firebase-admin/firestore";

import { db } from "../lib/admin";
import { filterMessage } from "./profanityFilter";

const RATE_LIMIT_MS = 3000;

/**
 * Sends a chat message. This is deliberately a callable Cloud Function
 * rather than a direct client Firestore write, because per-message rate
 * limiting can't be made airtight with security rules alone: a rules-based
 * "cooldown doc" approach (compare `request.time` against a
 * `last_message_at` field) only works if the client is *also* trusted to
 * update that cooldown doc on every message — and a client that simply
 * never updates it gets a permanent bypass after the first successful
 * message. Doing the check-and-write as one server-side transaction closes
 * that gap entirely: there is no path to writing a message without the
 * same transaction updating the rate-limit record.
 *
 * The Flutter client (send_chat_message.dart) still does a local 3s
 * debounce before ever calling this, purely for instant UX feedback —
 * that debounce is not what's protecting anything; this transaction is.
 */
export const sendChatMessage = onCall(async (request) => {
  const auth = request.auth;
  if (!auth) {
    throw new HttpsError("unauthenticated", "Sign in to send messages.");
  }

  const roomId = request.data?.roomId;
  const text = request.data?.text;
  const displayName = request.data?.displayName;
  if (typeof roomId !== "string" || roomId.length === 0) {
    throw new HttpsError("invalid-argument", "roomId is required.");
  }
  if (typeof text !== "string") {
    throw new HttpsError("invalid-argument", "text is required.");
  }
  if (typeof displayName !== "string" || displayName.trim().length === 0) {
    throw new HttpsError("invalid-argument", "displayName is required.");
  }

  const filterResult = filterMessage(text);
  if (!filterResult.allowed) {
    throw new HttpsError("invalid-argument", filterResult.reason ?? "Message rejected.");
  }

  const uid = auth.uid;
  const [roomSnap, userSnap] = await Promise.all([
    db.doc(`chat_rooms/${roomId}`).get(),
    db.doc(`users/${uid}`).get(),
  ]);
  if (!roomSnap.exists) {
    throw new HttpsError("not-found", "That room doesn't exist.");
  }
  const roomSkillLevel = roomSnap.data()?.skill_level;

  // Reads the skill_level cached by updateSkillLevelOnOrder.ts (kept in
  // sync from the existing order history — no schema change needed to
  // Phase 2's execute_trade.dart writes) rather than a count() query here,
  // so this checks the exact same field firestore.rules trusts for chat
  // room *reads* — one source of truth for "what skill level is this user"
  // instead of two computations that could drift. A brand-new user with no
  // orders yet and thus no cached field defaults to "beginner", matching
  // skillLevelForCompletedTrades(0).
  const userSkillLevel = userSnap.data()?.skill_level ?? "beginner";

  if (userSkillLevel !== roomSkillLevel) {
    throw new HttpsError(
      "permission-denied",
      `This room is for ${roomSkillLevel} traders; you're currently ${userSkillLevel}.`,
    );
  }

  const rateLimitRef = db.doc(`chat_rate_limits/${uid}`);
  const messageRef = db.collection(`chat_rooms/${roomId}/messages`).doc();

  await db.runTransaction(async (tx) => {
    const rateLimitSnap = await tx.get(rateLimitRef);
    const now = Timestamp.now();
    const existing = rateLimitSnap.data();

    if (existing?.flagged === true) {
      throw new HttpsError(
        "permission-denied",
        "This account is under review and can't send messages right now.",
      );
    }

    const lastMessageAt = existing?.last_message_at as Timestamp | undefined;
    if (lastMessageAt && now.toMillis() - lastMessageAt.toMillis() < RATE_LIMIT_MS) {
      throw new HttpsError(
        "resource-exhausted",
        "You're sending messages too quickly — wait a few seconds.",
      );
    }

    tx.set(
      rateLimitRef,
      {
        last_message_at: now,
        flagged: existing?.flagged ?? false,
      },
      { merge: true },
    );
    tx.set(messageRef, {
      user_id: uid,
      display_name: displayName.trim().slice(0, 40),
      text: text.trim(),
      timestamp: now,
    });
  });

  return { messageId: messageRef.id };
});
