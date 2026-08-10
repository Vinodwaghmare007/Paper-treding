/**
 * Pure-logic tests for checkPriceAlerts.ts's crossing detector — no
 * emulator needed. Run via: ts-node test/checkPriceAlerts.test.ts
 * (see package.json's "test:price-alerts" script).
 */
import { test } from "node:test";
import * as assert from "node:assert/strict";

import { detectCrossing } from "../src/alerts/checkPriceAlerts";

test("detectCrossing", async (t) => {
  await t.test("does not fire on the very first check, even if already past target", () => {
    assert.equal(detectCrossing("above", 70000, undefined, 75000), false);
    assert.equal(detectCrossing("below", 70000, undefined, 65000), false);
  });

  await t.test("fires when price crosses from below to at/above the target ('above' direction)", () => {
    assert.equal(detectCrossing("above", 70000, 69000, 70000), true);
    assert.equal(detectCrossing("above", 70000, 69999, 71000), true);
  });

  await t.test("does not re-fire on subsequent checks once already past the target", () => {
    // Simulates minute-by-minute checks after the price is already above
    // target: 69000->70000 fires once; 70000->71000 must NOT fire again
    // because lastCheckedPrice (70000) is not below the target anymore.
    assert.equal(detectCrossing("above", 70000, 70000, 71000), false);
    assert.equal(detectCrossing("above", 70000, 71000, 72000), false);
  });

  await t.test("fires when price crosses from above to at/below the target ('below' direction)", () => {
    assert.equal(detectCrossing("below", 60000, 61000, 60000), true);
    assert.equal(detectCrossing("below", 60000, 60001, 58000), true);
  });

  await t.test("does not fire when the price moves away from the target", () => {
    assert.equal(detectCrossing("above", 70000, 65000, 66000), false);
    assert.equal(detectCrossing("below", 60000, 65000, 66000), false);
  });

  await t.test("does not fire when the price stays on the same side without reaching target", () => {
    assert.equal(detectCrossing("above", 70000, 68000, 69000), false);
  });
});
