/** One Binance kline, positional per their REST API:
 * [openTime, open, high, low, close, volume, closeTime, ...] */
export interface Candle {
  openTimeMs: number;
  closeTimeMs: number;
  open: number;
  high: number;
  low: number;
  close: number;
  volume: number;
}

export class BinanceApiError extends Error {
  constructor(
    message: string,
    public readonly statusCode?: number,
  ) {
    super(message);
    this.name = "BinanceApiError";
  }
}

const BASE_URL = "https://api.binance.com";

/** GET /api/v3/klines — oldest-first, matching Binance's own ordering. */
export async function fetchKlines(params: {
  symbol: string;
  interval: string;
  limit?: number;
  startTimeMs?: number;
  endTimeMs?: number;
}): Promise<Candle[]> {
  const query = new URLSearchParams({
    symbol: params.symbol,
    interval: params.interval,
    limit: String(params.limit ?? 500),
  });
  if (params.startTimeMs !== undefined) {
    query.set("startTime", String(params.startTimeMs));
  }
  if (params.endTimeMs !== undefined) {
    query.set("endTime", String(params.endTimeMs));
  }

  const response = await fetch(`${BASE_URL}/api/v3/klines?${query.toString()}`);
  if (!response.ok) {
    throw new BinanceApiError(
      `Binance klines request failed: HTTP ${response.status}`,
      response.status,
    );
  }

  const raw = (await response.json()) as unknown[];
  return raw.map((entry) => {
    const row = entry as [number, string, string, string, string, string, number, ...unknown[]];
    return {
      openTimeMs: row[0],
      open: Number(row[1]),
      high: Number(row[2]),
      low: Number(row[3]),
      close: Number(row[4]),
      volume: Number(row[5]),
      closeTimeMs: row[6],
    };
  });
}

/** Simple % returns between consecutive closes: returns[i] = (close[i] -
 * close[i-1]) / close[i-1]. One shorter than `candles`. */
export function computeReturns(candles: Candle[]): number[] {
  const returns: number[] = [];
  for (let i = 1; i < candles.length; i++) {
    const prev = candles[i - 1].close;
    const curr = candles[i].close;
    if (prev !== 0) returns.push((curr - prev) / prev);
  }
  return returns;
}

/** Population standard deviation of `values`. */
export function standardDeviation(values: number[]): number {
  if (values.length === 0) return 0;
  const mean = values.reduce((a, b) => a + b, 0) / values.length;
  const variance =
    values.reduce((sum, v) => sum + (v - mean) ** 2, 0) / values.length;
  return Math.sqrt(variance);
}
