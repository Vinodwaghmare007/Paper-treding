/** Mirrors lib/data/entities/supported_coin.dart's curated coin list —
 * kept in sync manually (same duplication tradeoff already accepted for
 * aggregateSentiment.ts's TRACKED_SYMBOLS), since Cloud Functions
 * (TypeScript) and the Flutter app (Dart) can't share a single source
 * file across that language boundary.
 *
 * This is the bundled DEFAULT — same role as supported_coin.dart's
 * `supportedCoins` const. The Flutter app additionally overlays a live
 * Remote Config coin list at runtime (see remote_config_coin_source.dart)
 * so a coin can be added without an app update; if that becomes something
 * alert-checking/sentiment also need to honor immediately (rather than on
 * the next manual sync of this file), have checkPriceAlerts.ts /
 * aggregateSentiment.ts read the same Remote Config parameter via
 * firebase-admin's getRemoteConfig() instead — not done here to keep this
 * phase's blast radius contained to what's actually needed for launch. */
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
  BCHUSDT: "bitcoin-cash",
  XLMUSDT: "stellar",
  ETCUSDT: "ethereum-classic",
  FILUSDT: "filecoin",
  NEARUSDT: "near",
  ICPUSDT: "internet-computer",
  APTUSDT: "aptos",
  ARBUSDT: "arbitrum",
  OPUSDT: "optimism",
  HBARUSDT: "hedera-hashgraph",
  VETUSDT: "vechain",
  ALGOUSDT: "algorand",
  SANDUSDT: "the-sandbox",
  MANAUSDT: "decentraland",
  AXSUSDT: "axie-infinity",
  EOSUSDT: "eos",
  XTZUSDT: "tezos",
  THETAUSDT: "theta-token",
  AAVEUSDT: "aave",
  MKRUSDT: "maker",
  SNXUSDT: "havven",
  GRTUSDT: "the-graph",
  CHZUSDT: "chiliz",
  ZECUSDT: "zcash",
  NEOUSDT: "neo",
  IOTAUSDT: "iota",
  KSMUSDT: "kusama",
  CRVUSDT: "curve-dao-token",
  SUSHIUSDT: "sushi",
  QNTUSDT: "quant-network",
  INJUSDT: "injective-protocol",
  RUNEUSDT: "thorchain",
  GALAUSDT: "gala",
  LDOUSDT: "lido-dao",
  SUIUSDT: "sui",
  PEPEUSDT: "pepe",
  SHIBUSDT: "shiba-inu",
};
