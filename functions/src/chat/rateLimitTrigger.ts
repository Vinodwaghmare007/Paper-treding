import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { Timestamp } from "firebase-admin/firestore";

import { db } from "../lib/admin";

const WINDOW_MINUTES = 10;
// Airtight per-message spacing already happens inside sendChatMessage's
// transaction (nothing can be written faster than one message per 3s), so
// hitting this many messages in the window below means something unusual
// is going on — many rooms in parallel, a compromised account, etc. — not
// just "a chatty user." This flags for human review; it does not
// auto-ban, since a false positive here shouldn't silently lock someone
// out of every room.
const FLAG_THRESHOLD = 50;

/**
 * Fires after every chat message write. sendChatMessage.ts already makes
 * per-message rate limiting airtight (see the comment there for why); this
 * trigger is a second, independent layer looking for *longer-window*
 * abuse patterns a per-message check can't see — e.g. legitimate-looking
 * 3-second-apart messages sustained across many rooms for an hour.
 */
export const onChatMessageCreated = onDocumentCreated(
  "chat_rooms/{roomId}/messages/{messageId}",
  async (event) => {
    const message = event.data?.data();
    if (!message) return;
    const userId = message.user_id as string | undefined;
    if (!userId) return;

    const windowStart = Timestamp.fromMillis(Date.now() - WINDOW_MINUTES * 60 * 1000);
    const recentCountSnap = await db
      .collectionGroup("messages")
      .where("user_id", "==", userId)
      .where("timestamp", ">=", windowStart)
      .count()
      .get();

    const recentCount = recentCountSnap.data().count;
    if (recentCount < FLAG_THRESHOLD) return;

    const rateLimitRef = db.doc(`chat_rate_limits/${userId}`);
    await rateLimitRef.set(
      {
        flagged: true,
        flagged_at: Timestamp.now(),
        flagged_reason: `${recentCount} messages in the last ${WINDOW_MINUTES} minutes`,
      },
      { merge: true },
    );
  },
);
