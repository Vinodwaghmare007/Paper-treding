// Pure, Firestore-free trader performance math — the "auditable, not
// vague" formulas the Phase 8 spec asked for, kept in one place so
// recomputeTraderStats.ts (real Firestore reads) and this file's own
// tests (synthetic order lists) exercise the exact same logic.

export interface TraderOrderInput {
  orderType: "BUY" | "SELL";
  coinSymbol: string;
  realizedPnl: number | null;
  timestampMs: number;
}

export interface TraderStats {
  totalTrades: number;
  winRatePct: number;
  accuracyPct: number;
  disciplineScore: number;
  lastTradeAtMs: number | null;
}

// Matches UserAccount.lossStreakLimit (lib/domain/entities/user_account
// .dart) — the exact loss-streak length that arms the revenge-blocker's
// buy lock in TradeMath.applySell. Replicated here (not imported — this
// is a separate TS project) so a "revenge lock trigger" in this replay
// means literally the same thing as it does in the live trading engine.
const LOSS_STREAK_LIMIT = 3;

// Matches highFrequencyWindow (lib/domain/usecases/trade_frequency_monitor
// .dart) — reusing the app's own existing "this is a fast flip" window as
// the holding-time target, rather than inventing an unrelated number:
// holding a position for at least this long earns full credit toward the
// holding-time half of the discipline score.
const HOLDING_TIME_TARGET_MINUTES = 60;

// discipline_score = 100 * clamp01(
//   DISCIPLINE_LOCK_WEIGHT   * (1 - revengeLockTriggers / totalClosedTrades) +
//   DISCIPLINE_HOLDING_WEIGHT * clamp01(avgHoldingMinutes / HOLDING_TIME_TARGET_MINUTES)
// )
//
// Lock-avoidance is weighted higher than holding time because avoiding
// the revenge-blocker entirely is the sharper, more direct signal of
// "traded with discipline" — holding time is a softer proxy (a long hold
// isn't always deliberate) so it only fills in the remaining 30%.
const DISCIPLINE_LOCK_WEIGHT = 0.7;
const DISCIPLINE_HOLDING_WEIGHT = 0.3;

function clamp01(value: number): number {
  return Math.max(0, Math.min(1, value));
}

/**
 * accuracy_pct and win_rate_pct: % of closed (SELL) trades with
 * realized_pnl > 0. The Phase 8 spec lists these as two separate stats
 * fields but only ever defines one formula for them (step 2's "accuracy_pct:
 * % of closed trades that were profitable"), which is the standard
 * definition of win rate — this app has no separate "did the user follow
 * the AI forecast" tracking that a distinct "accuracy" metric could be
 * built from, so both fields are intentionally computed identically here
 * rather than one of them being invented. Revisit if a real
 * forecast-following signal is ever added.
 *
 * discipline_score: see the weight comments above. A trade with
 * realized_pnl == 0 (breakeven) resets the loss streak (same as a win,
 * per TradeMath.applySell's `else` branch) but does not count toward
 * wins/win_rate_pct — matches trade_math_test.dart's "breakeven P&L not
 * counted as loss".
 *
 * Holding time per SELL is approximated as (this SELL's timestamp − the
 * most recent prior BUY of the same symbol). This app tracks positions by
 * weighted-average price, not per-lot FIFO, so there's no single
 * "purchase time" for a partially-filled position — this is a
 * documented, reasonable proxy, not an exact per-unit holding time.
 */
export function computeTraderStats(orders: TraderOrderInput[]): TraderStats {
  const sorted = [...orders].sort((a, b) => a.timestampMs - b.timestampMs);

  const lastBuyMsBySymbol = new Map<string, number>();
  let consecutiveLosses = 0;
  let revengeLockTriggers = 0;
  let wins = 0;
  let totalClosedTrades = 0;
  let holdingMinutesSum = 0;
  let holdingSamples = 0;
  let lastTradeAtMs: number | null = null;

  for (const order of sorted) {
    lastTradeAtMs = order.timestampMs;

    if (order.orderType === "BUY") {
      lastBuyMsBySymbol.set(order.coinSymbol, order.timestampMs);
      continue;
    }

    totalClosedTrades += 1;
    const pnl = order.realizedPnl ?? 0;
    if (pnl > 0) {
      wins += 1;
      consecutiveLosses = 0;
    } else if (pnl === 0) {
      consecutiveLosses = 0;
    } else {
      consecutiveLosses += 1;
      if (consecutiveLosses === LOSS_STREAK_LIMIT) {
        revengeLockTriggers += 1;
      }
    }

    const lastBuyMs = lastBuyMsBySymbol.get(order.coinSymbol);
    if (lastBuyMs !== undefined) {
      holdingMinutesSum += (order.timestampMs - lastBuyMs) / 60000;
      holdingSamples += 1;
    }
  }

  if (totalClosedTrades === 0) {
    return {
      totalTrades: 0,
      winRatePct: 0,
      accuracyPct: 0,
      disciplineScore: 0,
      lastTradeAtMs,
    };
  }

  const winRatePct = (wins / totalClosedTrades) * 100;
  const avgHoldingMinutes = holdingSamples > 0 ? holdingMinutesSum / holdingSamples : 0;
  const lockAvoidance = clamp01(1 - revengeLockTriggers / totalClosedTrades);
  const holdingFactor = clamp01(avgHoldingMinutes / HOLDING_TIME_TARGET_MINUTES);
  const disciplineScore =
    clamp01(DISCIPLINE_LOCK_WEIGHT * lockAvoidance + DISCIPLINE_HOLDING_WEIGHT * holdingFactor) * 100;

  return {
    totalTrades: totalClosedTrades,
    winRatePct,
    accuracyPct: winRatePct,
    disciplineScore,
    lastTradeAtMs,
  };
}
