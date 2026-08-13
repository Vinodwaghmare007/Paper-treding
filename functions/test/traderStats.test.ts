// Pure-logic test — no Firestore/emulator involved, since traderStats.ts
// has no Firebase dependency at all. Run via: npm run test:trader-stats
import { strict as assert } from "node:assert";
import test from "node:test";

import { computeTraderStats, TraderOrderInput } from "../src/lib/traderStats";

const MINUTE = 60000;

function order(
  orderType: "BUY" | "SELL",
  timestampMs: number,
  opts: { coinSymbol?: string; realizedPnl?: number | null } = {},
): TraderOrderInput {
  return {
    orderType,
    coinSymbol: opts.coinSymbol ?? "BTCUSDT",
    realizedPnl: opts.realizedPnl ?? null,
    timestampMs,
  };
}

test("computeTraderStats", async (t) => {
  await t.test("returns all zeros for an account with no closed trades", () => {
    const stats = computeTraderStats([order("BUY", 0)]);
    assert.deepEqual(stats, {
      totalTrades: 0,
      winRatePct: 0,
      accuracyPct: 0,
      disciplineScore: 0,
      lastTradeAtMs: 0,
    });
  });

  await t.test("win_rate_pct and accuracy_pct are % of profitable SELLs", () => {
    const orders: TraderOrderInput[] = [
      order("BUY", 0),
      order("SELL", 1 * MINUTE, { realizedPnl: 100 }), // win
      order("BUY", 2 * MINUTE),
      order("SELL", 3 * MINUTE, { realizedPnl: -50 }), // loss
      order("BUY", 4 * MINUTE),
      order("SELL", 5 * MINUTE, { realizedPnl: 0 }), // breakeven — not a win
      order("BUY", 6 * MINUTE),
      order("SELL", 7 * MINUTE, { realizedPnl: 30 }), // win
    ];
    const stats = computeTraderStats(orders);

    assert.equal(stats.totalTrades, 4);
    assert.equal(stats.winRatePct, 50); // 2 of 4
    assert.equal(stats.accuracyPct, stats.winRatePct);
  });

  await t.test("counts a revenge-lock trigger exactly at the 3rd consecutive loss", () => {
    // 3 losses in a row -> exactly one trigger, matching
    // UserAccount.lossStreakLimit / TradeMath.applySell.
    const orders: TraderOrderInput[] = [
      order("BUY", 0),
      order("SELL", 1 * MINUTE, { realizedPnl: -10 }),
      order("BUY", 2 * MINUTE),
      order("SELL", 3 * MINUTE, { realizedPnl: -10 }),
      order("BUY", 4 * MINUTE),
      order("SELL", 5 * MINUTE, { realizedPnl: -10 }),
    ];
    const stats = computeTraderStats(orders);

    // lockAvoidance = 1 - 1/3 = 0.667; no BUY precedes any SELL by more
    // than a minute, so holdingFactor is tiny — discipline_score should
    // land close to 0.7 * 66.7 ≈ 46.7, well below a clean track record.
    assert.equal(stats.totalTrades, 3);
    assert.equal(stats.winRatePct, 0);
    assert.ok(stats.disciplineScore < 50, `expected < 50, got ${stats.disciplineScore}`);
    assert.ok(stats.disciplineScore > 40, `expected > 40, got ${stats.disciplineScore}`);
  });

  await t.test("a win resets the loss streak so a later 2-loss run never triggers a lock", () => {
    const orders: TraderOrderInput[] = [
      order("BUY", 0),
      order("SELL", 1 * MINUTE, { realizedPnl: -10 }),
      order("BUY", 2 * MINUTE),
      order("SELL", 3 * MINUTE, { realizedPnl: -10 }),
      order("BUY", 4 * MINUTE),
      order("SELL", 5 * MINUTE, { realizedPnl: 10 }), // resets the streak
      order("BUY", 6 * MINUTE),
      order("SELL", 7 * MINUTE, { realizedPnl: -10 }),
      order("BUY", 8 * MINUTE),
      order("SELL", 9 * MINUTE, { realizedPnl: -10 }),
    ];
    const stats = computeTraderStats(orders);

    // No 3-in-a-row anywhere in this sequence -> perfect lock-avoidance.
    // discipline_score should be noticeably higher than the "one trigger"
    // case above given the same near-zero holding times.
    assert.ok(stats.disciplineScore > 65, `expected > 65, got ${stats.disciplineScore}`);
  });

  await t.test("longer holding time increases discipline_score, all else equal", () => {
    const quickFlip: TraderOrderInput[] = [
      order("BUY", 0),
      order("SELL", 1 * MINUTE, { realizedPnl: 10 }),
    ];
    const longHold: TraderOrderInput[] = [
      order("BUY", 0),
      order("SELL", 120 * MINUTE, { realizedPnl: 10 }),
    ];

    const quickStats = computeTraderStats(quickFlip);
    const longStats = computeTraderStats(longHold);

    assert.ok(
      longStats.disciplineScore > quickStats.disciplineScore,
      `expected ${longStats.disciplineScore} > ${quickStats.disciplineScore}`,
    );
  });

  await t.test("holding time is measured from the most recent prior BUY of the same symbol", () => {
    const orders: TraderOrderInput[] = [
      order("BUY", 0, { coinSymbol: "ETHUSDT" }),
      order("BUY", 0, { coinSymbol: "BTCUSDT" }),
      order("BUY", 59 * MINUTE, { coinSymbol: "BTCUSDT" }), // tops up BTC right before selling
      order("SELL", 60 * MINUTE, { coinSymbol: "BTCUSDT", realizedPnl: 5 }),
    ];
    const stats = computeTraderStats(orders);

    // Holding time should be measured against the 59-minute BTC top-up,
    // not the unrelated ETH buy or the very first BTC buy at t=0 — i.e.
    // ~1 minute, not ~60.
    assert.equal(stats.totalTrades, 1);
    assert.ok(stats.disciplineScore < 75, `expected a quick-flip-sized score, got ${stats.disciplineScore}`);
  });

  await t.test("a short (opening SELL, closing/covering BUY) counts and measures holding time symmetrically", () => {
    const orders: TraderOrderInput[] = [
      order("SELL", 0), // opens a short — no realizedPnl
      order("BUY", 60 * MINUTE, { realizedPnl: 20 }), // covers it at a profit
    ];
    const stats = computeTraderStats(orders);

    assert.equal(stats.totalTrades, 1);
    assert.equal(stats.winRatePct, 100);
    // Holding time measured against the opening SELL, same proxy as the
    // long case measuring against an opening BUY.
    assert.ok(stats.disciplineScore > 65, `expected a long-hold-sized score, got ${stats.disciplineScore}`);
  });

  await t.test("lastTradeAtMs is the latest order timestamp regardless of input order", () => {
    const stats = computeTraderStats([
      order("SELL", 5 * MINUTE, { realizedPnl: 1 }),
      order("BUY", 0),
      order("SELL", 10 * MINUTE, { realizedPnl: 1 }),
      order("BUY", 2 * MINUTE),
    ]);
    assert.equal(stats.lastTradeAtMs, 10 * MINUTE);
  });
});
