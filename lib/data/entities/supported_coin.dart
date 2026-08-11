/// A coin/pair this app lets someone chart, trade, and follow. Curated
/// (not a live "top N by market cap" feed) — see the coin-switcher feature
/// discussion: a curated list is predictable for testing and for Market
/// Replay/backtester curated data, and every entry here is meant to be a
/// long-established, high-liquidity Binance USDT pair to minimize the risk
/// of a symbol being delisted out from under the app.
///
/// [supportedCoins] below is the bundled DEFAULT/fallback list, shipped in
/// the app binary — it's what's used before the first Remote Config fetch
/// completes, and whenever Remote Config is unreachable. The list actually
/// shown to a signed-in user is [supportedCoinsProvider] in
/// coin_catalog_providers.dart, which overlays a live Remote Config JSON
/// payload on top of this default so coins can be added (or a bad symbol
/// pulled) without an app store release — see remote_config_coin_source
/// .dart for the fetch/parse/fallback logic.
///
/// PRE-LAUNCH TODO: the 35 entries added beyond the original 15 were
/// curated from general knowledge of long-listed, high-liquidity Binance
/// USDT pairs — this sandbox has no network access to verify them live
/// against Binance's `/exchangeInfo` or CoinGecko's `/coins/markets`
/// (both are blocked by this environment's egress proxy). Spot-check every
/// [symbol]/[coingeckoId] pair below against the live APIs before shipping;
/// treat this the same as the existing delisting-risk note below.
///
/// Binance's batch endpoints (`/ticker/price`, `/ticker/24hr` with a
/// `symbols=[...]` array) reject the *entire* request if even one symbol
/// in the array is invalid/delisted — so if the live-trading price feed
/// ever starts erroring out entirely, check this list first for a symbol
/// Binance has since removed. CoinGecko's `/coins/markets` (used by the
/// Markets/Watchlist screen for its sparkline data, which Binance doesn't
/// provide) has the same all-or-nothing failure mode for an unknown
/// [coingeckoId].
class SupportedCoin {
  const SupportedCoin({
    required this.symbol,
    required this.baseAsset,
    required this.displayName,
    required this.coingeckoId,
  });

  /// Binance trading pair, e.g. `'BTCUSDT'` — used for REST/WebSocket calls
  /// (live chart, trading, portfolio pricing).
  final String symbol;

  /// e.g. `'BTC'` — used for compact UI labels.
  final String baseAsset;

  /// e.g. `'Bitcoin'` — used in longer UI labels and the Markets list.
  final String displayName;

  /// CoinGecko's own id for this coin, e.g. `'bitcoin'` — unrelated to the
  /// Binance [symbol] naming, used only by coingecko_source.dart for the
  /// Markets/Watchlist screen's price+24h%+sparkline batch fetch.
  final String coingeckoId;
}

const supportedCoins = <SupportedCoin>[
  SupportedCoin(symbol: 'BTCUSDT', baseAsset: 'BTC', displayName: 'Bitcoin', coingeckoId: 'bitcoin'),
  SupportedCoin(symbol: 'ETHUSDT', baseAsset: 'ETH', displayName: 'Ethereum', coingeckoId: 'ethereum'),
  SupportedCoin(symbol: 'BNBUSDT', baseAsset: 'BNB', displayName: 'BNB', coingeckoId: 'binancecoin'),
  SupportedCoin(symbol: 'SOLUSDT', baseAsset: 'SOL', displayName: 'Solana', coingeckoId: 'solana'),
  SupportedCoin(symbol: 'XRPUSDT', baseAsset: 'XRP', displayName: 'XRP', coingeckoId: 'ripple'),
  SupportedCoin(symbol: 'ADAUSDT', baseAsset: 'ADA', displayName: 'Cardano', coingeckoId: 'cardano'),
  SupportedCoin(symbol: 'DOGEUSDT', baseAsset: 'DOGE', displayName: 'Dogecoin', coingeckoId: 'dogecoin'),
  SupportedCoin(symbol: 'AVAXUSDT', baseAsset: 'AVAX', displayName: 'Avalanche', coingeckoId: 'avalanche-2'),
  SupportedCoin(symbol: 'DOTUSDT', baseAsset: 'DOT', displayName: 'Polkadot', coingeckoId: 'polkadot'),
  SupportedCoin(symbol: 'LINKUSDT', baseAsset: 'LINK', displayName: 'Chainlink', coingeckoId: 'chainlink'),
  SupportedCoin(symbol: 'POLUSDT', baseAsset: 'POL', displayName: 'Polygon', coingeckoId: 'matic-network'),
  SupportedCoin(symbol: 'LTCUSDT', baseAsset: 'LTC', displayName: 'Litecoin', coingeckoId: 'litecoin'),
  SupportedCoin(symbol: 'TRXUSDT', baseAsset: 'TRX', displayName: 'TRON', coingeckoId: 'tron'),
  SupportedCoin(symbol: 'ATOMUSDT', baseAsset: 'ATOM', displayName: 'Cosmos', coingeckoId: 'cosmos'),
  SupportedCoin(symbol: 'UNIUSDT', baseAsset: 'UNI', displayName: 'Uniswap', coingeckoId: 'uniswap'),
  SupportedCoin(symbol: 'BCHUSDT', baseAsset: 'BCH', displayName: 'Bitcoin Cash', coingeckoId: 'bitcoin-cash'),
  SupportedCoin(symbol: 'XLMUSDT', baseAsset: 'XLM', displayName: 'Stellar', coingeckoId: 'stellar'),
  SupportedCoin(symbol: 'ETCUSDT', baseAsset: 'ETC', displayName: 'Ethereum Classic', coingeckoId: 'ethereum-classic'),
  SupportedCoin(symbol: 'FILUSDT', baseAsset: 'FIL', displayName: 'Filecoin', coingeckoId: 'filecoin'),
  SupportedCoin(symbol: 'NEARUSDT', baseAsset: 'NEAR', displayName: 'NEAR Protocol', coingeckoId: 'near'),
  SupportedCoin(symbol: 'ICPUSDT', baseAsset: 'ICP', displayName: 'Internet Computer', coingeckoId: 'internet-computer'),
  SupportedCoin(symbol: 'APTUSDT', baseAsset: 'APT', displayName: 'Aptos', coingeckoId: 'aptos'),
  SupportedCoin(symbol: 'ARBUSDT', baseAsset: 'ARB', displayName: 'Arbitrum', coingeckoId: 'arbitrum'),
  SupportedCoin(symbol: 'OPUSDT', baseAsset: 'OP', displayName: 'Optimism', coingeckoId: 'optimism'),
  SupportedCoin(symbol: 'HBARUSDT', baseAsset: 'HBAR', displayName: 'Hedera', coingeckoId: 'hedera-hashgraph'),
  SupportedCoin(symbol: 'VETUSDT', baseAsset: 'VET', displayName: 'VeChain', coingeckoId: 'vechain'),
  SupportedCoin(symbol: 'ALGOUSDT', baseAsset: 'ALGO', displayName: 'Algorand', coingeckoId: 'algorand'),
  SupportedCoin(symbol: 'SANDUSDT', baseAsset: 'SAND', displayName: 'The Sandbox', coingeckoId: 'the-sandbox'),
  SupportedCoin(symbol: 'MANAUSDT', baseAsset: 'MANA', displayName: 'Decentraland', coingeckoId: 'decentraland'),
  SupportedCoin(symbol: 'AXSUSDT', baseAsset: 'AXS', displayName: 'Axie Infinity', coingeckoId: 'axie-infinity'),
  SupportedCoin(symbol: 'EOSUSDT', baseAsset: 'EOS', displayName: 'EOS', coingeckoId: 'eos'),
  SupportedCoin(symbol: 'XTZUSDT', baseAsset: 'XTZ', displayName: 'Tezos', coingeckoId: 'tezos'),
  SupportedCoin(symbol: 'THETAUSDT', baseAsset: 'THETA', displayName: 'Theta Network', coingeckoId: 'theta-token'),
  SupportedCoin(symbol: 'AAVEUSDT', baseAsset: 'AAVE', displayName: 'Aave', coingeckoId: 'aave'),
  SupportedCoin(symbol: 'MKRUSDT', baseAsset: 'MKR', displayName: 'Maker', coingeckoId: 'maker'),
  SupportedCoin(symbol: 'SNXUSDT', baseAsset: 'SNX', displayName: 'Synthetix', coingeckoId: 'havven'),
  SupportedCoin(symbol: 'GRTUSDT', baseAsset: 'GRT', displayName: 'The Graph', coingeckoId: 'the-graph'),
  SupportedCoin(symbol: 'CHZUSDT', baseAsset: 'CHZ', displayName: 'Chiliz', coingeckoId: 'chiliz'),
  SupportedCoin(symbol: 'ZECUSDT', baseAsset: 'ZEC', displayName: 'Zcash', coingeckoId: 'zcash'),
  SupportedCoin(symbol: 'NEOUSDT', baseAsset: 'NEO', displayName: 'NEO', coingeckoId: 'neo'),
  SupportedCoin(symbol: 'IOTAUSDT', baseAsset: 'IOTA', displayName: 'IOTA', coingeckoId: 'iota'),
  SupportedCoin(symbol: 'KSMUSDT', baseAsset: 'KSM', displayName: 'Kusama', coingeckoId: 'kusama'),
  SupportedCoin(symbol: 'CRVUSDT', baseAsset: 'CRV', displayName: 'Curve DAO', coingeckoId: 'curve-dao-token'),
  SupportedCoin(symbol: 'SUSHIUSDT', baseAsset: 'SUSHI', displayName: 'SushiSwap', coingeckoId: 'sushi'),
  SupportedCoin(symbol: 'QNTUSDT', baseAsset: 'QNT', displayName: 'Quant', coingeckoId: 'quant-network'),
  SupportedCoin(symbol: 'INJUSDT', baseAsset: 'INJ', displayName: 'Injective', coingeckoId: 'injective-protocol'),
  SupportedCoin(symbol: 'RUNEUSDT', baseAsset: 'RUNE', displayName: 'THORChain', coingeckoId: 'thorchain'),
  SupportedCoin(symbol: 'GALAUSDT', baseAsset: 'GALA', displayName: 'Gala', coingeckoId: 'gala'),
  SupportedCoin(symbol: 'LDOUSDT', baseAsset: 'LDO', displayName: 'Lido DAO', coingeckoId: 'lido-dao'),
  SupportedCoin(symbol: 'SUIUSDT', baseAsset: 'SUI', displayName: 'Sui', coingeckoId: 'sui'),
  SupportedCoin(symbol: 'PEPEUSDT', baseAsset: 'PEPE', displayName: 'Pepe', coingeckoId: 'pepe'),
  SupportedCoin(symbol: 'SHIBUSDT', baseAsset: 'SHIB', displayName: 'Shiba Inu', coingeckoId: 'shiba-inu'),
];

final _byBaseSymbol = {for (final c in supportedCoins) c.symbol: c};

/// Falls back to a synthetic entry (symbol used as its own display name,
/// no CoinGecko id) for any symbol outside the curated list — e.g. a
/// position opened before this feature existed, or held in a coin later
/// removed from the list — so lookups never throw for stale data.
SupportedCoin coinForSymbol(String symbol) =>
    _byBaseSymbol[symbol] ??
    SupportedCoin(symbol: symbol, baseAsset: symbol, displayName: symbol, coingeckoId: '');
