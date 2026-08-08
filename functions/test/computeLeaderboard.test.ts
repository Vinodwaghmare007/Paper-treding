// Pure-logic test — no Firestore/emulator involved.
// Run via: npm run test:leaderboard
import { strict as assert } from "node:assert";
import test from "node:test";

import { buildLeaderboards, StatsRow } from "../src/traderProfile/computeLeaderboard";

const DAY = 24 * 60 * 60 * 1000;
const NOW = 100 * DAY;

function row(overrides: Partial<StatsRow>): StatsRow {
  return {
    userId: "u",
    displayName: "Trader",
    disciplineScore: 0,
    winRatePct: 0,
    totalTrades: 10,
    lastTradeAtMs: NOW,
    ...overrides,
  };
}

test("buildLeaderboards", async (t) => {
  await t.test("excludes profiles below the minimum trade count", () => {
    const { allTime } = buildLeaderboards(
      [row({ userId: "tiny", totalTrades: 2, disciplineScore: 100, winRatePct: 100 })],
      { nowMs: NOW },
    );
    assert.deepEqual(allTime, []);
  });

  await t.test("weights discipline higher than win rate in the blended score", () => {
    const { allTime } = buildLeaderboards(
      [
        row({ userId: "disciplined", disciplineScore: 90, winRatePct: 40 }),
        row({ userId: "gambler", disciplineScore: 30, winRatePct: 95 }),
      ],
      { nowMs: NOW },
    );

    // disciplined: 0.65*90 + 0.35*40 = 72.5
    // gambler:     0.65*30 + 0.35*95 = 52.75
    assert.equal(allTime[0].user_id, "disciplined");
    assert.equal(allTime[1].user_id, "gambler");
  });

  await t.test("caps each list at 100 entries", () => {
    const rows = Array.from({ length: 150 }, (_, i) =>
      row({ userId: `u${i}`, disciplineScore: i, winRatePct: i }),
    );
    const { allTime } = buildLeaderboards(rows, { nowMs: NOW });
    assert.equal(allTime.length, 100);
    // Highest scores first.
    assert.equal(allTime[0].user_id, "u149");
  });

  await t.test("weekly excludes traders inactive for more than 7 days, all_time does not", () => {
    const rows = [
      row({ userId: "active", lastTradeAtMs: NOW - 1 * DAY }),
      row({ userId: "stale", lastTradeAtMs: NOW - 30 * DAY }),
      row({ userId: "never_traded_since_join", lastTradeAtMs: null }),
    ];
    const { allTime, weekly } = buildLeaderboards(rows, { nowMs: NOW });

    assert.equal(allTime.length, 3);
    assert.deepEqual(
      weekly.map((e) => e.user_id).sort(),
      ["active"],
    );
  });

  await t.test("a trader exactly 7 days inactive is still included (boundary is inclusive)", () => {
    const rows = [row({ userId: "boundary", lastTradeAtMs: NOW - 7 * DAY })];
    const { weekly } = buildLeaderboards(rows, { nowMs: NOW });
    assert.equal(weekly.length, 1);
  });
});
