/// A coin/pair this app lets someone chart, trade, and follow. Deliberately
/// a small, hand-curated list (not a live "top N by market cap" feed) —
/// see the coin-switcher feature discussion: a fixed list is predictable
/// for testing and for Market Replay/backtester curated data, and every
/// entry here is a long-established, high-liquidity Binance USDT pair to
/// minimize the risk of a symbol being delisted out from under the app.
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
];

final _byBaseSymbol = {for (final c in supportedCoins) c.symbol: c};

/// Falls back to a synthetic entry (symbol used as its own display name,
/// no CoinGecko id) for any symbol outside the curated list — e.g. a
/// position opened before this feature existed, or held in a coin later
/// removed from the list — so lookups never throw for stale data.
SupportedCoin coinForSymbol(String symbol) =>
    _byBaseSymbol[symbol] ??
    SupportedCoin(symbol: symbol, baseAsset: symbol, displayName: symbol, coingeckoId: '');
