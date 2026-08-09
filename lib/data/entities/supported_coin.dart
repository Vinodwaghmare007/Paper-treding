/// A coin/pair this app lets someone chart, trade, and follow. Deliberately
/// a small, hand-curated list (not a live "top N by market cap" feed) —
/// see the coin-switcher feature discussion: a fixed list is predictable
/// for testing and for Market Replay/backtester curated data, and every
/// entry here is a long-established, high-liquidity Binance USDT pair to
/// minimize the risk of a symbol being delisted out from under the app.
///
/// Binance's batch endpoints (`/ticker/price`, `/ticker/24hr` with a
/// `symbols=[...]` array) reject the *entire* request if even one symbol
/// in the array is invalid/delisted — so if the Markets screen or
/// portfolio pricing ever starts erroring out entirely, check this list
/// first for a symbol Binance has since removed.
class SupportedCoin {
  const SupportedCoin({
    required this.symbol,
    required this.baseAsset,
    required this.displayName,
  });

  /// Binance trading pair, e.g. `'BTCUSDT'` — used for REST/WebSocket calls.
  final String symbol;

  /// e.g. `'BTC'` — used for compact UI labels.
  final String baseAsset;

  /// e.g. `'Bitcoin'` — used in longer UI labels and the Markets list.
  final String displayName;
}

const supportedCoins = <SupportedCoin>[
  SupportedCoin(symbol: 'BTCUSDT', baseAsset: 'BTC', displayName: 'Bitcoin'),
  SupportedCoin(symbol: 'ETHUSDT', baseAsset: 'ETH', displayName: 'Ethereum'),
  SupportedCoin(symbol: 'BNBUSDT', baseAsset: 'BNB', displayName: 'BNB'),
  SupportedCoin(symbol: 'SOLUSDT', baseAsset: 'SOL', displayName: 'Solana'),
  SupportedCoin(symbol: 'XRPUSDT', baseAsset: 'XRP', displayName: 'XRP'),
  SupportedCoin(symbol: 'ADAUSDT', baseAsset: 'ADA', displayName: 'Cardano'),
  SupportedCoin(symbol: 'DOGEUSDT', baseAsset: 'DOGE', displayName: 'Dogecoin'),
  SupportedCoin(symbol: 'AVAXUSDT', baseAsset: 'AVAX', displayName: 'Avalanche'),
  SupportedCoin(symbol: 'DOTUSDT', baseAsset: 'DOT', displayName: 'Polkadot'),
  SupportedCoin(symbol: 'LINKUSDT', baseAsset: 'LINK', displayName: 'Chainlink'),
  SupportedCoin(symbol: 'POLUSDT', baseAsset: 'POL', displayName: 'Polygon'),
  SupportedCoin(symbol: 'LTCUSDT', baseAsset: 'LTC', displayName: 'Litecoin'),
  SupportedCoin(symbol: 'TRXUSDT', baseAsset: 'TRX', displayName: 'TRON'),
  SupportedCoin(symbol: 'ATOMUSDT', baseAsset: 'ATOM', displayName: 'Cosmos'),
  SupportedCoin(symbol: 'UNIUSDT', baseAsset: 'UNI', displayName: 'Uniswap'),
];

final _byBaseSymbol = {for (final c in supportedCoins) c.symbol: c};

/// Falls back to a synthetic entry (symbol used as its own display name)
/// for any symbol outside the curated list — e.g. a position opened before
/// this feature existed, or held in a coin later removed from the list —
/// so lookups never throw for stale data.
SupportedCoin coinForSymbol(String symbol) =>
    _byBaseSymbol[symbol] ??
    SupportedCoin(symbol: symbol, baseAsset: symbol, displayName: symbol);
