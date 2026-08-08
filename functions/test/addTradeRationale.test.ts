// Behavioral test against the real Firestore emulator — run via:
//   npm run test:trade-rationale
import { strict as assert } from "node:assert";
import test from "node:test";
import { Timestamp } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";

import { addTradeRationaleForUser } from "../src/rationale/addTradeRationale";
import { db } from "../src/lib/admin";

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

test("addTradeRationaleForUser", async (t) => {
  await t.test("writes a rationale for a closed (SELL) trade", async () => {
    const uid = `rationale-ok-${Date.now()}`;
    await makeOrder(uid, "order-1");

    const result = await addTradeRationaleForUser(uid, "order-1", "Took profit after the RSI cooled off.");
    assert.equal(result.flagged, false);

    const noteSnap = await db.doc(`users/${uid}/orders/order-1/rationale/note`).get();
    assert.equal(noteSnap.exists, true);
    assert.equal(noteSnap.data()!.text, "Took profit after the RSI cooled off.");
    assert.equal(noteSnap.data()!.flagged_for_review, false);
    assert.equal(noteSnap.data()!.user_id, uid);
    assert.equal(noteSnap.data()!.coin_symbol, "BTCUSDT");
  });

  await t.test("rejects a rationale on an open (BUY) order", async () => {
    const uid = `rationale-buy-${Date.now()}`;
    await makeOrder(uid, "order-1", { order_type: "BUY", realized_pnl: null });

    await assert.rejects(
      () => addTradeRationaleForUser(uid, "order-1", "This is going up."),
      (err: unknown) => err instanceof HttpsError && err.code === "failed-precondition",
    );
  });

  await t.test("rejects a rationale timestamped before the order closed", async () => {
    const uid = `rationale-preclose-${Date.now()}`;
    const orderTimestamp = Timestamp.now();
    await makeOrder(uid, "order-1", { timestamp: orderTimestamp });

    const beforeClose = Timestamp.fromMillis(orderTimestamp.toMillis() - 5000);
    await assert.rejects(
      () => addTradeRationaleForUser(uid, "order-1", "Selling because...", { now: beforeClose }),
      (err: unknown) => err instanceof HttpsError && err.code === "failed-precondition",
    );

    const noteSnap = await db.doc(`users/${uid}/orders/order-1/rationale/note`).get();
    assert.equal(noteSnap.exists, false, "no doc should be written when the timestamp check fails");
  });

  await t.test("rejects a rationale exactly at the order's own timestamp", async () => {
    const uid = `rationale-exact-${Date.now()}`;
    const orderTimestamp = Timestamp.now();
    await makeOrder(uid, "order-1", { timestamp: orderTimestamp });

    await assert.rejects(
      () => addTradeRationaleForUser(uid, "order-1", "Note", { now: orderTimestamp }),
      (err: unknown) => err instanceof HttpsError && err.code === "failed-precondition",
    );
  });

  await t.test("rejects a nonexistent order", async () => {
    const uid = `rationale-missing-${Date.now()}`;
    await assert.rejects(
      () => addTradeRationaleForUser(uid, "no-such-order", "Note"),
      (err: unknown) => err instanceof HttpsError && err.code === "not-found",
    );
  });

  await t.test("rejects text over 280 characters", async () => {
    const uid = `rationale-toolong-${Date.now()}`;
    await makeOrder(uid, "order-1");
    await assert.rejects(
      () => addTradeRationaleForUser(uid, "order-1", "x".repeat(281)),
      (err: unknown) => err instanceof HttpsError && err.code === "invalid-argument",
    );
  });

  await t.test("hard-rejects denylisted content instead of just flagging it", async () => {
    const uid = `rationale-denylist-${Date.now()}`;
    await makeOrder(uid, "order-1");
    await assert.rejects(
      () => addTradeRationaleForUser(uid, "order-1", "this trade was shit"),
      (err: unknown) => err instanceof HttpsError && err.code === "invalid-argument",
    );
  });

  await t.test("soft-flags forward-looking phrasing but still writes it", async () => {
    const uid = `rationale-flag-${Date.now()}`;
    await makeOrder(uid, "order-1");

    const result = await addTradeRationaleForUser(
      uid,
      "order-1",
      "I think BTC will keep dropping after this.",
    );
    assert.equal(result.flagged, true);

    const noteSnap = await db.doc(`users/${uid}/orders/order-1/rationale/note`).get();
    assert.equal(noteSnap.exists, true);
    assert.equal(noteSnap.data()!.flagged_for_review, true);
  });

  await t.test("a second submission overwrites the first (edit path)", async () => {
    const uid = `rationale-edit-${Date.now()}`;
    await makeOrder(uid, "order-1");

    await addTradeRationaleForUser(uid, "order-1", "First note.");
    await addTradeRationaleForUser(uid, "order-1", "Revised note.");

    const noteSnap = await db.doc(`users/${uid}/orders/order-1/rationale/note`).get();
    assert.equal(noteSnap.data()!.text, "Revised note.");
  });
});
