import { onSchedule } from "firebase-functions/v2/scheduler";
import { Timestamp } from "firebase-admin/firestore";

import { db } from "../lib/admin";

const MIN_TRADES_FOR_LEADERBOARD = 5; // guards against a 1-trade lucky streak topping the board
const TOP_N = 100;
const WEEKLY_WINDOW_MS = 7 * 24 * 60 * 60 * 1000;

// Discipline weighted higher than raw win-rate on purpose, per the spec:
// this reinforces the app's psychology-first positioning (avoiding
// revenge-trading, holding with intent) rather than rewarding a lucky
// gambler who happens to have a high win rate. Both inputs are already
// 0-100 scales.
const DISCIPLINE_WEIGHT = 0.65;
const WIN_RATE_WEIGHT = 0.35;

export interface LeaderboardEntry {
  user_id: string;
  display_name: string;
  discipline_score: number;
  win_rate_pct: number;
  blended_score: number;
}

export interface StatsRow {
  userId: string;
  displayName: string;
  disciplineScore: number;
  winRatePct: number;
  totalTrades: number;
  lastTradeAtMs: number | null;
}

function blendedScore(disciplineScore: number, winRatePct: number): number {
  return DISCIPLINE_WEIGHT * disciplineScore + WIN_RATE_WEIGHT * winRatePct;
}

function toEntry(row: StatsRow): LeaderboardEntry {
  return {
    user_id: row.userId,
    display_name: row.displayName,
    discipline_score: row.disciplineScore,
    win_rate_pct: row.winRatePct,
    blended_score: blendedScore(row.disciplineScore, row.winRatePct),
  };
}

function rankTop(rows: StatsRow[]): LeaderboardEntry[] {
  return rows
    .map(toEntry)
    .sort((a, b) => b.blended_score - a.blended_score)
    .slice(0, TOP_N);
}

/**
 * Testable core. `nowMs` is injectable so the "active in the last 7 days"
 * weekly filter can be tested deterministically rather than depending on
 * the real clock at test-run time.
 */
export function buildLeaderboards(
  rows: StatsRow[],
  { nowMs = Date.now() }: { nowMs?: number } = {},
): { allTime: LeaderboardEntry[]; weekly: LeaderboardEntry[] } {
  const eligible = rows.filter((row) => row.totalTrades >= MIN_TRADES_FOR_LEADERBOARD);
  const weeklyCutoffMs = nowMs - WEEKLY_WINDOW_MS;

  return {
    allTime: rankTop(eligible),
    // "Weekly" ranks currently-active traders (traded in the last 7 days)
    // by their existing all-time discipline/win-rate stats — it is NOT a
    // separate week-windowed recomputation of those stats resetting to
    // zero each week. A true rolling reset would mean either a second
    // parallel stats window tracked per user, or querying every public
    // user's last-7-days orders on every leaderboard run — both of which
    // conflict with the "single small public-readable doc, not a live
    // query over all users" / "avoid expensive reads at scale" constraint
    // this function was given. Documented trade-off, not an oversight.
    weekly: rankTop(eligible.filter((row) => row.lastTradeAtMs != null && row.lastTradeAtMs >= weeklyCutoffMs)),
  };
}

export async function computeLeaderboards(): Promise<void> {
  const publicStats = await db
    .collectionGroup("profile_stats")
    .where("is_public", "==", true)
    .get();

  const rows: StatsRow[] = publicStats.docs.map((doc) => {
    const data = doc.data();
    const lastTradeAt = data.last_trade_at as Timestamp | undefined | null;
    return {
      userId: doc.ref.parent.parent!.id,
      displayName: (data.display_name as string | undefined) ?? "Trader",
      disciplineScore: (data.discipline_score as number | undefined) ?? 0,
      winRatePct: (data.win_rate_pct as number | undefined) ?? 0,
      totalTrades: (data.total_trades as number | undefined) ?? 0,
      lastTradeAtMs: lastTradeAt ? lastTradeAt.toMillis() : null,
    };
  });

  const { allTime, weekly } = buildLeaderboards(rows);
  const computedAt = Timestamp.now();

  await Promise.all([
    db.doc("public_leaderboard/all_time").set({ entries: allTime, computed_at: computedAt }),
    db.doc("public_leaderboard/weekly").set({ entries: weekly, computed_at: computedAt }),
  ]);
}

export const computeLeaderboard = onSchedule("every 6 hours", computeLeaderboards);
