// Behavioral test against the real Firestore emulator (not mocks) — run via:
//   npm run test:certifications
import { strict as assert } from "node:assert";
import test from "node:test";

import { evaluateBacktestMilestonesForCounts } from "../src/certifications/evaluateBacktestMilestones";
import { evaluateTradeMilestonesForOrder } from "../src/certifications/evaluateTradeMilestones";
import { awardCertificationIfNeeded } from "../src/lib/certifications";
import { db } from "../src/lib/admin";

test("awardCertificationIfNeeded", async (t) => {
  await t.test("creates the cert and a PII-free public mirror", async () => {
    const uid = `cert-test-${Date.now()}`;
    await awardCertificationIfNeeded(uid, "50_disciplined_trades");

    const certDoc = await db.doc(`users/${uid}/certifications/50_disciplined_trades`).get();
    assert.equal(certDoc.exists, true);
    const cert = certDoc.data()!;
    assert.equal(cert.milestone_type, "50_disciplined_trades");
    assert.equal(typeof cert.verification_code, "string");

    const publicDoc = await db.doc(`public_certifications/${cert.verification_code}`).get();
    assert.equal(publicDoc.exists, true);
    assert.equal(publicDoc.data()!.milestone_type, "50_disciplined_trades");
    // No uid/email anywhere in the public mirror.
    assert.equal("uid" in publicDoc.data()!, false);
  });

  await t.test("is idempotent — a second award for the same milestone is a no-op", async () => {
    const uid = `cert-idempotent-test-${Date.now()}`;
    await awardCertificationIfNeeded(uid, "backtester_master");
    const firstCode = (await db.doc(`users/${uid}/certifications/backtester_master`).get())
      .data()!.verification_code;

    await awardCertificationIfNeeded(uid, "backtester_master");
    const secondCode = (await db.doc(`users/${uid}/certifications/backtester_master`).get())
      .data()!.verification_code;

    assert.equal(firstCode, secondCode, "the verification code must not change on re-award");
  });
});

test("evaluateTradeMilestonesForOrder", async (t) => {
  await t.test("does nothing for an order that opened/added a position (no realized_pnl)", async () => {
    const uid = `trade-milestone-open-${Date.now()}`;
    await evaluateTradeMilestonesForOrder(uid, { order_type: "BUY", realized_pnl: null });
    const certDoc = await db.doc(`users/${uid}/certifications/50_disciplined_trades`).get();
    assert.equal(certDoc.exists, false);
  });

  await t.test("awards the cert once 50 closed trades exist", async () => {
    const uid = `trade-milestone-sell-${Date.now()}`;
    const batch = db.batch();
    for (let i = 0; i < 49; i++) {
      batch.set(db.doc(`users/${uid}/orders/order-${i}`), { order_type: "SELL", realized_pnl: 1 });
    }
    await batch.commit();

    // The 49th completed trade shouldn't award anything yet.
    await evaluateTradeMilestonesForOrder(uid, { order_type: "SELL", realized_pnl: 1 });
    assert.equal(
      (await db.doc(`users/${uid}/certifications/50_disciplined_trades`).get()).exists,
      false,
    );

    // The 50th order pushes the count() query result to 50.
    await db.doc(`users/${uid}/orders/order-49`).set({ order_type: "SELL", realized_pnl: 1 });
    await evaluateTradeMilestonesForOrder(uid, { order_type: "SELL", realized_pnl: 1 });
    assert.equal(
      (await db.doc(`users/${uid}/certifications/50_disciplined_trades`).get()).exists,
      true,
    );
  });

  await t.test("counts a short-covering BUY (realized_pnl set) the same as a closing SELL", async () => {
    const uid = `trade-milestone-cover-${Date.now()}`;
    const batch = db.batch();
    for (let i = 0; i < 49; i++) {
      batch.set(db.doc(`users/${uid}/orders/order-${i}`), { order_type: "SELL", realized_pnl: 1 });
    }
    await batch.commit();

    // The 50th trade is a BUY that covered a short, not a SELL — should
    // still push the count to 50 and award the cert.
    await db.doc(`users/${uid}/orders/order-49`).set({ order_type: "BUY", realized_pnl: 5 });
    await evaluateTradeMilestonesForOrder(uid, { order_type: "BUY", realized_pnl: 5 });
    assert.equal(
      (await db.doc(`users/${uid}/certifications/50_disciplined_trades`).get()).exists,
      true,
    );
  });
});

test("evaluateBacktestMilestonesForCounts", async (t) => {
  await t.test("does nothing when the count did not increase", async () => {
    const uid = `backtest-milestone-nochange-${Date.now()}`;
    await evaluateBacktestMilestonesForCounts(uid, 10, 10);
    assert.equal(
      (await db.doc(`users/${uid}/certifications/backtester_master`).get()).exists,
      false,
    );
  });

  await t.test("does nothing below the threshold", async () => {
    const uid = `backtest-milestone-below-${Date.now()}`;
    await evaluateBacktestMilestonesForCounts(uid, 8, 9);
    assert.equal(
      (await db.doc(`users/${uid}/certifications/backtester_master`).get()).exists,
      false,
    );
  });

  await t.test("awards the cert once the count reaches the threshold", async () => {
    const uid = `backtest-milestone-hit-${Date.now()}`;
    await evaluateBacktestMilestonesForCounts(uid, 9, 10);
    assert.equal(
      (await db.doc(`users/${uid}/certifications/backtester_master`).get()).exists,
      true,
    );
  });
});
