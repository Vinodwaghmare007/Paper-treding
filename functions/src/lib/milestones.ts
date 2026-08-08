// Milestone catalog for the micro-certification feature. `type` is the
// exact string stored in `certifications/{certId}.milestone_type` (and
// used as the certId itself, for idempotent awarding — see
// certifications.ts) and in CertificationDisplay on the Flutter side —
// keep both in sync if a type string ever changes here.
export const MILESTONES = {
  disciplinedTrader: {
    type: "50_disciplined_trades",
    // 50 completed (SELL) round-trip trades. This counts sustained
    // engagement, not literally "never triggered the revenge-blocker" —
    // that per-trade state lives client-side only (trade_lock_provider
    // .dart) and isn't synced to Firestore, so it isn't something this
    // server-side trigger can verify. Naming kept as given in the spec;
    // treat it as "50 trades completed," not a stronger discipline claim.
    completedTradesThreshold: 50,
  },
  backtesterMaster: {
    type: "backtester_master",
    // Backtests run entirely client-side and aren't persisted — see
    // recordBacktestCompletion.ts for how this count reaches Firestore.
    backtestRunThreshold: 10,
  },
} as const;
