/** Mirrors lib/data/entities/supported_coin.dart's curated coin list —
 * kept in sync manually (same duplication tradeoff already accepted for
 * aggregateSentiment.ts's TRACKED_SYMBOLS), since Cloud Functions
 * (TypeScript) and the Flutter app (Dart) can't share a single source
 * file across that language boundary. */
export const SYMBOL_TO_COINGECKO_ID: Record<string, string> = {
  BTCUSDT: "bitcoin",
  ETHUSDT: "ethereum",
  BNBUSDT: "binancecoin",
  SOLUSDT: "solana",
  XRPUSDT: "ripple",
  ADAUSDT: "cardano",
  DOGEUSDT: "dogecoin",
  AVAXUSDT: "avalanche-2",
  DOTUSDT: "polkadot",
  LINKUSDT: "chainlink",
  POLUSDT: "matic-network",
  LTCUSDT: "litecoin",
  TRXUSDT: "tron",
  ATOMUSDT: "cosmos",
  UNIUSDT: "uniswap",
};
