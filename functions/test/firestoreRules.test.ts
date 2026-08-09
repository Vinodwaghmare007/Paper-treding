/**
 * Behavioral tests for ../../firestore.rules against the Firestore
 * emulator — not just a syntax check (the emulator already refuses to
 * start on a rules parse error), but verifying the actual access-control
 * properties the rules are supposed to guarantee.
 *
 * Run via: firebase emulators:exec --only firestore --project demo-test
 *   "ts-node test/firestoreRules.test.ts"
 * (see package.json's "test:rules" script)
 */
import * as fs from "node:fs";
import * as path from "node:path";
import { test } from "node:test";
import { serverTimestamp } from "firebase/firestore";
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";

let testEnv: RulesTestEnvironment;

async function setup() {
  testEnv = await initializeTestEnvironment({
    projectId: "demo-test",
    firestore: {
      rules: fs.readFileSync(path.resolve(__dirname, "../../firestore.rules"), "utf8"),
      host: "127.0.0.1",
      port: 8080,
    },
  });
}

async function teardown() {
  await testEnv.cleanup();
}

test("firestore.rules", async (t) => {
  await setup();

  await t.test("a user can create their own account doc with the correct starting shape", async () => {
    const db = testEnv.authenticatedContext("alice").firestore();
    await assertSucceeds(
      db.doc("users/alice").set({
        virtual_balance: 100000,
        starting_balance: 100000,
        consecutive_losses: 0,
        buy_locked_until: null,
        created_at: serverTimestamp(),
      }),
    );
  });

  await t.test("a user cannot create their account doc with the wrong starting balance", async () => {
    const db = testEnv.authenticatedContext("bob").firestore();
    await assertFails(
      db.doc("users/bob").set({
        virtual_balance: 999999, // forged
        starting_balance: 100000,
        consecutive_losses: 0,
        buy_locked_until: null,
        created_at: serverTimestamp(),
      }),
    );
  });

  await t.test("a user cannot create an account doc on someone else's uid", async () => {
    const db = testEnv.authenticatedContext("eve").firestore();
    await assertFails(
      db.doc("users/alice").set({
        virtual_balance: 100000,
        starting_balance: 100000,
        consecutive_losses: 0,
        buy_locked_until: null,
        created_at: serverTimestamp(),
      }),
    );
  });

  await t.test("a user cannot forge skill_level through an account update", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context
        .firestore()
        .doc("users/carol")
        .set({
          virtual_balance: 100000,
          starting_balance: 100000,
          consecutive_losses: 0,
          buy_locked_until: null,
          created_at: serverTimestamp(),
          skill_level: "beginner",
        });
    });

    const db = testEnv.authenticatedContext("carol").firestore();
    await assertFails(db.doc("users/carol").set({ skill_level: "advanced" }, { merge: true }));
    // A legitimate update that leaves skill_level untouched still works.
    await assertSucceeds(db.doc("users/carol").set({ consecutive_losses: 1 }, { merge: true }));
  });

  await t.test("nobody can write a chat message directly — only the sendChatMessage callable can", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc("chat_rooms/beginner-room").set({
        name: "Beginner Room",
        skill_level: "beginner",
        member_count: 0,
        created_at: serverTimestamp(),
      });
    });

    const db = testEnv.authenticatedContext("dave").firestore();
    await assertFails(
      db.collection("chat_rooms/beginner-room/messages").add({
        user_id: "dave",
        display_name: "dave",
        text: "hi",
        timestamp: new Date(),
      }),
    );
  });

  await t.test("a user can only read chat messages in a room matching their cached skill level", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const admin = context.firestore();
      await admin.doc("users/frank").set({
        virtual_balance: 100000,
        starting_balance: 100000,
        consecutive_losses: 0,
        buy_locked_until: null,
        created_at: serverTimestamp(),
        skill_level: "beginner",
      });
      await admin.doc("chat_rooms/advanced-room").set({
        name: "Advanced Room",
        skill_level: "advanced",
        member_count: 0,
        created_at: serverTimestamp(),
      });
      await admin.doc("chat_rooms/beginner-room-2").set({
        name: "Beginner Room 2",
        skill_level: "beginner",
        member_count: 0,
        created_at: serverTimestamp(),
      });
      await admin.collection("chat_rooms/advanced-room/messages").doc("m1").set({
        user_id: "someone",
        display_name: "someone",
        text: "advanced talk",
        timestamp: new Date(),
      });
      await admin.collection("chat_rooms/beginner-room-2/messages").doc("m1").set({
        user_id: "someone",
        display_name: "someone",
        text: "beginner talk",
        timestamp: new Date(),
      });
    });

    const db = testEnv.authenticatedContext("frank").firestore();
    await assertFails(db.collection("chat_rooms/advanced-room/messages").get());
    await assertSucceeds(db.collection("chat_rooms/beginner-room-2/messages").get());
  });

  await t.test("anyone, including signed-out users, can read the daily puzzle and sentiment docs", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc("daily_puzzle/2026-08-06").set({
        symbol: "BTCUSDT",
        shown_candles: [],
        total_answers: 0,
        correct_answers: 0,
      });
      await context.firestore().doc("public_sentiment/BTCUSDT").set({
        symbol: "BTCUSDT",
        bullish_pct: 55,
      });
    });

    const db = testEnv.unauthenticatedContext().firestore();
    await assertSucceeds(db.doc("daily_puzzle/2026-08-06").get());
    await assertSucceeds(db.doc("public_sentiment/BTCUSDT").get());
  });

  await t.test("the puzzle answer subcollection is never client-readable, even signed in", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc("daily_puzzle/2026-08-06/secret/answer").set({
        correct_answer: "up",
        actual_move_pct: 1.2,
      });
    });

    const db = testEnv.authenticatedContext("grace").firestore();
    await assertFails(db.doc("daily_puzzle/2026-08-06/secret/answer").get());
  });

  await t.test("a user can file a report for themselves but can't read the reports queue", async () => {
    const db = testEnv.authenticatedContext("henry").firestore();
    await assertSucceeds(
      db.collection("reports").add({
        room_id: "beginner-room",
        message_id: "m1",
        reported_by: "henry",
        reason: "spam",
        timestamp: serverTimestamp(),
      }),
    );
    await assertFails(db.collection("reports").get());
  });

  await t.test("a user cannot file a report claiming to be someone else", async () => {
    const db = testEnv.authenticatedContext("ivan").firestore();
    await assertFails(
      db.collection("reports").add({
        room_id: "beginner-room",
        message_id: "m1",
        reported_by: "someone-else",
        reason: "spam",
        timestamp: serverTimestamp(),
      }),
    );
  });

  // ------------------------------------------------------------------
  // Trader Profiles (Phase 8)
  // ------------------------------------------------------------------

  await t.test("a user can write their own profile_settings within the size/type limits", async () => {
    const db = testEnv.authenticatedContext("kara").firestore();
    await assertSucceeds(
      db.doc("users/kara/profile_settings/data").set({ display_name: "Kara", is_public: true }),
    );
    await assertFails(
      db.doc("users/kara/profile_settings/data").set({ display_name: "", is_public: true }),
    );
    await assertFails(
      db.doc("users/kara/profile_settings/data").set({ display_name: "Kara", is_public: "yes" }),
    );
  });

  await t.test("a user cannot write someone else's profile_settings", async () => {
    const db = testEnv.authenticatedContext("liam").firestore();
    await assertFails(
      db.doc("users/kara/profile_settings/data").set({ display_name: "Liam", is_public: true }),
    );
  });

  await t.test("nobody can write profile_stats directly, even the owner", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc("users/mona/profile_settings/data").set({
        display_name: "Mona",
        is_public: true,
      });
    });
    const db = testEnv.authenticatedContext("mona").firestore();
    await assertFails(db.doc("users/mona/profile_stats/data").set({ discipline_score: 100 }));
  });

  await t.test("a public profile's stats are readable by anyone signed in; a private one is not", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const admin = context.firestore();
      await admin.doc("users/nina/profile_settings/data").set({ display_name: "Nina", is_public: true });
      await admin.doc("users/nina/profile_stats/data").set({ discipline_score: 80, is_public: true });
      await admin.doc("users/oscar/profile_settings/data").set({ display_name: "Oscar", is_public: false });
      await admin.doc("users/oscar/profile_stats/data").set({ discipline_score: 40, is_public: false });
    });

    const db = testEnv.authenticatedContext("visitor").firestore();
    await assertSucceeds(db.doc("users/nina/profile_stats/data").get());
    await assertFails(db.doc("users/oscar/profile_stats/data").get());
  });

  await t.test("a user can follow another user but not themselves, and can unfollow", async () => {
    const db = testEnv.authenticatedContext("paul").firestore();
    await assertSucceeds(
      db.doc("users/paul/following/quinn").set({ created_at: serverTimestamp() }),
    );
    await assertFails(
      db.doc("users/paul/following/paul").set({ created_at: serverTimestamp() }),
    );
    await assertSucceeds(db.doc("users/paul/following/quinn").delete());
  });

  await t.test("a user cannot read another user's following list", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc("users/paul/following/quinn").set({ created_at: serverTimestamp() });
    });
    const db = testEnv.authenticatedContext("rachel").firestore();
    await assertFails(db.collection("users/paul/following").get());
  });

  await t.test("nobody can write a Trade Rationale directly — only the addTradeRationale callable can", async () => {
    const db = testEnv.authenticatedContext("sam").firestore();
    await assertFails(
      db.doc("users/sam/orders/order-1/rationale/note").set({
        text: "I sold because volume dried up.",
        created_at: serverTimestamp(),
        flagged_for_review: false,
      }),
    );
  });

  // ------------------------------------------------------------------
  // Coin watchlist
  // ------------------------------------------------------------------

  await t.test("a user can add and remove their own watchlist entries but not someone else's", async () => {
    const db = testEnv.authenticatedContext("tara").firestore();
    await assertSucceeds(
      db.doc("users/tara/watchlist/ETHUSDT").set({ created_at: serverTimestamp() }),
    );
    await assertSucceeds(db.doc("users/tara/watchlist/ETHUSDT").delete());
    await assertFails(
      db.doc("users/uma/watchlist/ETHUSDT").set({ created_at: serverTimestamp() }),
    );
  });

  await t.test("a user cannot read another user's watchlist", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc("users/tara/watchlist/ETHUSDT").set({ created_at: serverTimestamp() });
    });
    const db = testEnv.authenticatedContext("uma").firestore();
    await assertFails(db.collection("users/tara/watchlist").get());
  });

  await t.test("a public_leaderboard doc is readable by anyone, including signed-out users", async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc("public_leaderboard/weekly").set({ entries: [] });
    });
    const db = testEnv.unauthenticatedContext().firestore();
    await assertSucceeds(db.doc("public_leaderboard/weekly").get());
    await assertFails(db.doc("public_leaderboard/weekly").set({ entries: [] }));
  });

  await teardown();
});
