import { onSchedule } from "firebase-functions/v2/scheduler";
import { Timestamp } from "firebase-admin/firestore";

import { db } from "../lib/admin";
import { computeReturns, fetchKlines, standardDeviation } from "../lib/binance";

const SYMBOL = "BTCUSDT";

/** Population stddev of hourly returns, as a percentage. Thresholds are a
 * reasonable starting point for BTC's typical hourly volatility range —
 * tune against real data after this has been live a while. */
const TIERS = [
  { maxStdDevPct: 0.3, tier: "Calm", iconKey: "weather_calm" },
  { maxStdDevPct: 0.8, tier: "Active", iconKey: "weather_active" },
  { maxStdDevPct: 1.5, tier: "Volatile", iconKey: "weather_volatile" },
  { maxStdDevPct: Infinity, tier: "Extreme", iconKey: "weather_extreme" },
] as const;

function classify(stdDevPct: number): { tier: string; iconKey: string } {
  const match = TIERS.find((t) => stdDevPct < t.maxStdDevPct) ?? TIERS[TIERS.length - 1];
  return { tier: match.tier, iconKey: match.iconKey };
}

/**
 * Runs every 4 hours: rolling std-dev of BTCUSDT's last 24 hourly returns,
 * classified into a Calm/Active/Volatile/Extreme tier. Written to a tiny,
 * public, unauthenticated-readable doc — the Android home-screen widget
 * polls this directly without signing in.
 */
export const computeMarketWeather = onSchedule(
  { schedule: "0 */4 * * *", timeZone: "UTC" },
  async () => {
    const candles = await fetchKlines({ symbol: SYMBOL, interval: "1h", limit: 25 });
    const returns = computeReturns(candles);
    const stdDevPct = standardDeviation(returns) * 100;
    const { tier, iconKey } = classify(stdDevPct);

    await db.doc("public_market_weather/current").set({
      tier,
      icon_key: iconKey,
      std_dev_pct: Math.round(stdDevPct * 100) / 100,
      symbol: SYMBOL,
      updated_at: Timestamp.now(),
    });
  },
);
