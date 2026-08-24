import { Timestamp, FieldValue } from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";

import { db } from "../lib/admin";

// Must match UserAccount.lossStreakLimit / UserAccount.lockDuration
// (lib/domain/entities/user_account.dart) — replicated here (not
// imported — this is a separate TS project) so a stop-loss/take-profit
// firing server-side arms the exact same revenge-blocker lock a manual
// sell would.
const LOSS_STREAK_LIMIT = 3;
const LOCK_DURATION_MS = 30 * 60 * 1000;

export interface CloseLongParams {
  avgBuyPrice: number;
  quantityHeld: number;
  closeQuantity: number;
  price: number;
  consecutiveLossesBefore: number;
  buyLockedUntilMsBefore: number | null;
  nowMs: number;
}

export interface CloseLongResult {
  realizedPnl: number;
  proceeds: number;
  remainingQuantity: number;
  isFullyClosed: boolean;
  consecutiveLossesAfter: number;
  buyLockedUntilMsAfter: number | null;
}

/**
 * Server-side port of TradeMath.applySell's long-closing branch
 * (lib/domain/usecases/trade_math.dart) — a stop-loss/take-profit fires
 * from a scheduled Cloud Function with no client in the loop, so the
 * money-math has to be re-derived here rather than called into the Dart
 * engine. Kept as its own pure, isolate-free function (see
 * test/executeConditionalOrder.test.ts) exercising the identical cases
 * trade_math_test.dart does for the Dart side, specifically so this
 * doesn't silently drift from the live-trade rules.
 *
 * Only ever closes/reduces a LONG position (v1 scope — conditional orders
 * on a short are rejected at creation time, see firestore.rules'
 * conditional_orders match block).
 *
 * Note the same quirk trade_math.dart has: on a win/breakeven,
 * consecutiveLosses resets to 0 but buyLockedUntilMsBefore is carried
 * through unchanged rather than cleared — harmless because an existing
 * lock is purely time-based (UserAccount.isBuyLockedAt compares against
 * "now"), so a stale-but-expired timestamp never blocks anything.
 */
export function computeCloseLong(params: CloseLongParams): CloseLongResult {
  const {
    avgBuyPrice,
    quantityHeld,
    closeQuantity,
    price,
    consecutiveLossesBefore,
    buyLockedUntilMsBefore,
    nowMs,
  } = params;

  const realizedPnl = (price - avgBuyPrice) * closeQuantity;
  const remainingQuantity = quantityHeld - closeQuantity;
  // Guards against float dust leaving a near-zero residual position —
  // same 1e-9-scale epsilon trade_math.dart uses.
  const isFullyClosed = remainingQuantity <= 1e-9;
  const proceeds = price * closeQuantity;

  let consecutiveLossesAfter = consecutiveLossesBefore;
  let buyLockedUntilMsAfter = buyLockedUntilMsBefore;
  if (realizedPnl < 0) {
    consecutiveLossesAfter += 1;
    if (consecutiveLossesAfter >= LOSS_STREAK_LIMIT) {
      buyLockedUntilMsAfter = nowMs + LOCK_DURATION_MS;
    }
  } else {
    consecutiveLossesAfter = 0;
  }

  return {
    realizedPnl,
    proceeds,
    remainingQuantity,
    isFullyClosed,
    consecutiveLossesAfter,
    buyLockedUntilMsAfter,
  };
}

/**
 * Executes one triggered stop-loss/take-profit inside a single Firestore
 * transaction — mirrors ExecuteTradeUseCase.sell's shape (read account +
 * position, compute, write order + account + position) but via the Admin
 * SDK so it can run with no user present. All reads happen before any
 * write, as Firestore transactions require.
 */
export async function executeConditionalOrderTransaction(
  uid: string,
  orderRef: FirebaseFirestore.DocumentReference,
  price: number,
): Promise<void> {
  await db.runTransaction(async (transaction) => {
    const orderSnap = await transaction.get(orderRef);
    // The order may have been cancelled, or already fired by a concurrent
    // run, between the crossing-check query and this transaction — the
    // fresh read here is the actual guard, not the caller's snapshot.
    if (!orderSnap.exists || orderSnap.data()?.is_active !== true) return;

    const conditionalOrder = orderSnap.data()!;
    const coinSymbol = conditionalOrder.coin_symbol as string;
    const requestedQuantity = conditionalOrder.quantity as number;
    const kind = conditionalOrder.kind as "STOP_LOSS" | "TAKE_PROFIT";

    const userRef = db.doc(`users/${uid}`);
    const positionRef = db.doc(`users/${uid}/portfolio/${coinSymbol}`);
    const siblingKind = kind === "STOP_LOSS" ? "TAKE_PROFIT" : "STOP_LOSS";
    const siblingQuery = db
      .collection(`users/${uid}/conditional_orders`)
      .where("coin_symbol", "==", coinSymbol)
      .where("kind", "==", siblingKind)
      .where("is_active", "==", true);

    const [userSnap, positionSnap, siblingSnap] = await Promise.all([
      transaction.get(userRef),
      transaction.get(positionRef),
      transaction.get(siblingQuery),
    ]);

    if (!userSnap.exists || !positionSnap.exists) {
      // Position was fully sold manually since this order was created —
      // nothing left to close. Deactivate the now-stale order rather than
      // leaving it dangling as "active" forever.
      transaction.update(orderRef, {
        is_active: false,
        triggered_at: FieldValue.serverTimestamp(),
      });
      return;
    }

    const account = userSnap.data()!;
    const position = positionSnap.data()!;
    const quantityHeld = position.total_quantity as number;

    // The held quantity may have shrunk (a manual partial sell) since
    // this order was created — clamp rather than fail outright, so a
    // stop-loss still protects whatever's actually left instead of
    // silently doing nothing because the original size no longer matches.
    const closeQuantity = Math.min(requestedQuantity, quantityHeld);
    if (closeQuantity <= 0) {
      transaction.update(orderRef, {
        is_active: false,
        triggered_at: FieldValue.serverTimestamp(),
      });
      return;
    }

    const nowMs = Date.now();
    const buyLockedUntilTs = account.buy_locked_until as FirebaseFirestore.Timestamp | null;
    const result = computeCloseLong({
      avgBuyPrice: position.avg_buy_price as number,
      quantityHeld,
      closeQuantity,
      price,
      consecutiveLossesBefore: account.consecutive_losses as number,
      buyLockedUntilMsBefore: buyLockedUntilTs ? buyLockedUntilTs.toMillis() : null,
      nowMs,
    });

    const newOrderRef = db.collection(`users/${uid}/orders`).doc();
    transaction.set(newOrderRef, {
      coin_symbol: coinSymbol,
      order_type: "SELL",
      price,
      quantity: closeQuantity,
      realized_pnl: result.realizedPnl,
      timestamp: Timestamp.fromMillis(nowMs),
    });

    transaction.update(userRef, {
      virtual_balance: (account.virtual_balance as number) + result.proceeds,
      consecutive_losses: result.consecutiveLossesAfter,
      buy_locked_until:
        result.buyLockedUntilMsAfter === null
          ? (account.buy_locked_until ?? null)
          : Timestamp.fromMillis(result.buyLockedUntilMsAfter),
    });

    if (result.isFullyClosed) {
      transaction.delete(positionRef);
    } else {
      transaction.update(positionRef, { total_quantity: result.remainingQuantity });
    }

    transaction.update(orderRef, {
      is_active: false,
      triggered_at: FieldValue.serverTimestamp(),
      last_checked_price: price,
    });

    // OCO behavior: the sibling order (the other kind, same symbol) would
    // now be closing a position that's gone or smaller than it assumed —
    // deactivate it too rather than leaving a stale stop-loss or
    // take-profit sitting active.
    for (const siblingDoc of siblingSnap.docs) {
      transaction.update(siblingDoc.ref, {
        is_active: false,
        triggered_at: FieldValue.serverTimestamp(),
      });
    }
  });
}

export async function safeExecuteConditionalOrder(
  uid: string,
  orderRef: FirebaseFirestore.DocumentReference,
  price: number,
): Promise<void> {
  try {
    await executeConditionalOrderTransaction(uid, orderRef, price);
  } catch (error) {
    logger.error(`[executeConditionalOrder] failed for ${orderRef.path}`, error);
  }
}
