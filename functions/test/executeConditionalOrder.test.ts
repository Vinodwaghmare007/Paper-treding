// Pure-logic test — no Firestore/emulator involved, since computeCloseLong
// has no Firebase dependency at all. Run via: ts-node
// test/executeConditionalOrder.test.ts (or fold into a package.json script
// the same way test:trader-stats does).
//
// Cases deliberately mirror trade_math_test.dart's "TradeMath.applySell"
// group, since this function is a TypeScript port of that same
// long-closing branch — a mismatch here would mean a stop-loss/take-profit
// firing server-side computes a different result than a manual sell would.
import { strict as assert } from "node:assert";
import test from "node:test";

import { computeCloseLong } from "../src/trading/executeConditionalOrder";

const NOW_MS = Date.UTC(2026, 0, 1, 12);

test("computeCloseLong", async (t) => {
  await t.test("books realized P&L and credits proceeds", () => {
    const result = computeCloseLong({
      avgBuyPrice: 50000,
      quantityHeld: 1,
      closeQuantity: 0.5,
      price: 60000,
      consecutiveLossesBefore: 0,
      buyLockedUntilMsBefore: null,
      nowMs: NOW_MS,
    });
    assert.equal(result.realizedPnl, 5000); // (60000-50000)*0.5
    assert.equal(result.proceeds, 30000);
    assert.equal(result.remainingQuantity, 0.5);
    assert.equal(result.isFullyClosed, false);
  });

  await t.test("fully closing a position sets isFullyClosed", () => {
    const result = computeCloseLong({
      avgBuyPrice: 50000,
      quantityHeld: 1,
      closeQuantity: 1,
      price: 60000,
      consecutiveLossesBefore: 0,
      buyLockedUntilMsBefore: null,
      nowMs: NOW_MS,
    });
    assert.equal(result.isFullyClosed, true);
    assert.equal(result.remainingQuantity, 0);
  });

  await t.test("closing down to float dust is treated as fully closed", () => {
    // Same 0.1+0.1+0.1 hazard trade_math_test.dart's dusty-holding case
    // covers on the Dart side.
    const result = computeCloseLong({
      avgBuyPrice: 50000,
      quantityHeld: 0.1 + 0.1 + 0.1,
      closeQuantity: 0.3,
      price: 60000,
      consecutiveLossesBefore: 0,
      buyLockedUntilMsBefore: null,
      nowMs: NOW_MS,
    });
    assert.equal(result.isFullyClosed, true);
  });

  await t.test("a breakeven close (zero realized P&L) is not counted as a loss", () => {
    const result = computeCloseLong({
      avgBuyPrice: 50000,
      quantityHeld: 1,
      closeQuantity: 1,
      price: 50000, // == avgBuyPrice -> exactly zero P&L
      consecutiveLossesBefore: 2,
      buyLockedUntilMsBefore: null,
      nowMs: NOW_MS,
    });
    assert.equal(result.realizedPnl, 0);
    assert.equal(result.consecutiveLossesAfter, 0);
    assert.equal(result.buyLockedUntilMsAfter, null);
  });

  await t.test("a losing close increments consecutive losses", () => {
    const result = computeCloseLong({
      avgBuyPrice: 50000,
      quantityHeld: 1,
      closeQuantity: 1,
      price: 40000, // below avg buy price -> loss
      consecutiveLossesBefore: 1,
      buyLockedUntilMsBefore: null,
      nowMs: NOW_MS,
    });
    assert.ok(result.realizedPnl < 0);
    assert.equal(result.consecutiveLossesAfter, 2);
    assert.equal(result.buyLockedUntilMsAfter, null);
  });

  await t.test("the 3rd consecutive loss arms a 30-minute buy lock", () => {
    const result = computeCloseLong({
      avgBuyPrice: 50000,
      quantityHeld: 1,
      closeQuantity: 1,
      price: 40000,
      consecutiveLossesBefore: 2,
      buyLockedUntilMsBefore: null,
      nowMs: NOW_MS,
    });
    assert.equal(result.consecutiveLossesAfter, 3);
    assert.equal(result.buyLockedUntilMsAfter, NOW_MS + 30 * 60 * 1000);
  });

  await t.test("a profitable close resets consecutive losses to zero", () => {
    const result = computeCloseLong({
      avgBuyPrice: 50000,
      quantityHeld: 1,
      closeQuantity: 1,
      price: 60000,
      consecutiveLossesBefore: 2,
      buyLockedUntilMsBefore: null,
      nowMs: NOW_MS,
    });
    assert.equal(result.consecutiveLossesAfter, 0);
  });

  await t.test(
    "a win carries an existing buy lock through unchanged (matches TradeMath.applySell's " +
      "quirk: only a newly-armed lock overwrites buyLockedUntil, an old one is never actively " +
      "cleared — harmless since it's purely time-based)",
    () => {
      const staleLockMs = NOW_MS - 60 * 60 * 1000; // already expired
      const result = computeCloseLong({
        avgBuyPrice: 50000,
        quantityHeld: 1,
        closeQuantity: 1,
        price: 60000,
        consecutiveLossesBefore: 2,
        buyLockedUntilMsBefore: staleLockMs,
        nowMs: NOW_MS,
      });
      assert.equal(result.consecutiveLossesAfter, 0);
      assert.equal(result.buyLockedUntilMsAfter, staleLockMs);
    },
  );

  await t.test("weighted math stays exact for a partial close", () => {
    const result = computeCloseLong({
      avgBuyPrice: 10,
      quantityHeld: 3,
      closeQuantity: 2,
      price: 20,
      consecutiveLossesBefore: 0,
      buyLockedUntilMsBefore: null,
      nowMs: NOW_MS,
    });
    assert.equal(result.realizedPnl, 20); // (20-10)*2
    assert.equal(result.remainingQuantity, 1);
    assert.equal(result.proceeds, 40);
  });
});
