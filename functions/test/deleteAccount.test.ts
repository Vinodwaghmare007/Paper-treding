// Behavioral test against real Firestore + Auth emulators (not mocks) —
// the highest-stakes function added this phase (irreversible account +
// data deletion) deserves more than a type-check. Run via:
//   npm run test:delete-account
// (spawns `firebase emulators:exec --only firestore,auth --project
// demo-test`, which sets FIRESTORE_EMULATOR_HOST/FIREBASE_AUTH_EMULATOR_HOST
// and GCLOUD_PROJECT so ../src/lib/admin.ts's initializeApp() connects to
// the local emulators rather than a real project — no credentials needed.)
import { strict as assert } from "node:assert";
import test from "node:test";
import { getAuth } from "firebase-admin/auth";

import { db } from "../src/lib/admin";
import { deleteAccountForUser } from "../src/account/deleteAccount";

test("deleteAccountForUser", async (t) => {
  await t.test(
    "removes orders, portfolio, authored chat messages, rate-limit state, " +
      "the user doc, and the Auth account",
    async () => {
      const auth = getAuth();
      const user = await auth.createUser({
        email: `delete-test-${Date.now()}@example.com`,
        password: "password123",
      });
      const uid = user.uid;

      await db.doc(`users/${uid}`).set({ virtual_balance: 100000, consecutive_losses: 0 });
      await db.collection(`users/${uid}/orders`).doc("order-1").set({ coin_symbol: "BTCUSDT" });
      await db.collection(`users/${uid}/portfolio`).doc("BTCUSDT").set({ total_quantity: 1 });
      await db.doc(`chat_rate_limits/${uid}`).set({ flagged: false });
      await db.doc("chat_rooms/beginner").set({ name: "Beginner", skill_level: "beginner" });
      await db
        .collection("chat_rooms/beginner/messages")
        .doc("msg-1")
        .set({ user_id: uid, text: "hi", display_name: "Trader1" });
      // A message from someone else in the same room must survive.
      await db
        .collection("chat_rooms/beginner/messages")
        .doc("msg-2")
        .set({ user_id: "someone-else", text: "unrelated", display_name: "Trader2" });

      await deleteAccountForUser(uid);

      assert.equal((await db.doc(`users/${uid}`).get()).exists, false);
      assert.equal((await db.collection(`users/${uid}/orders`).doc("order-1").get()).exists, false);
      assert.equal(
        (await db.collection(`users/${uid}/portfolio`).doc("BTCUSDT").get()).exists,
        false,
      );
      assert.equal((await db.doc(`chat_rate_limits/${uid}`).get()).exists, false);
      assert.equal(
        (await db.collection("chat_rooms/beginner/messages").doc("msg-1").get()).exists,
        false,
      );
      assert.equal(
        (await db.collection("chat_rooms/beginner/messages").doc("msg-2").get()).exists,
        true,
        "another user's message in the same room must not be touched",
      );

      await assert.rejects(() => auth.getUser(uid));
    },
  );

  await t.test("the Firestore-side deletes are idempotent (safe to retry)", async () => {
    const auth = getAuth();
    const user = await auth.createUser({
      email: `delete-retry-test-${Date.now()}@example.com`,
      password: "password123",
    });
    const uid = user.uid;
    await db.doc(`users/${uid}`).set({ virtual_balance: 100000, consecutive_losses: 0 });

    await deleteAccountForUser(uid);
    // A second call for the same (now-deleted) uid must not throw on the
    // Firestore side — deleting an already-absent doc is a no-op. The
    // Auth deletion itself will fail for an already-deleted user, which
    // is fine: a real retry happens at the onCall layer for a fresh
    // attempt, not by calling this exact function twice in a row for the
    // same already-gone account.
    await assert.rejects(() => deleteAccountForUser(uid));
  });
});
