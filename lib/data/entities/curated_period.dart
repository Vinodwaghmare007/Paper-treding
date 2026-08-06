/// A curated historical window offered for Market Replay — a fixed,
/// hand-picked list rather than an arbitrary date picker, so replay always
/// lands on a period that's actually interesting to trade through.
class CuratedPeriod {
  const CuratedPeriod({
    required this.id,
    required this.name,
    required this.description,
    required this.symbol,
    required this.interval,
    required this.start,
    required this.end,
  });

  final String id;
  final String name;
  final String description;
  final String symbol;
  final String interval;
  final DateTime start;
  final DateTime end;
}

/// Fixed catalog of replay periods.
///
/// NOTE ON DATES: these mark well-known BTC volatility regimes (the 2021
/// bull run into its all-time high, the Nov 2022 FTX-collapse crash, and an
/// Oct 2025 leveraged-liquidation cascade — the same event referenced
/// elsewhere in the product roadmap's Liquidation Reality Simulator). The
/// exact boundaries here are best-effort from memory, not fact-checked
/// against a primary source in this environment, and worth double-checking
/// before shipping — replay's correctness doesn't depend on them being
/// exact, since the actual candles always come live from Binance for
/// whatever window is configured here, but the *story* ("this is the FTX
/// week") should match reality.
final List<CuratedPeriod> curatedPeriods = [
  CuratedPeriod(
    id: '2021_bull_run',
    name: '2021 Bull Run',
    description:
        "BTC's run into its 2021 all-time high (~\$69k) — strong, sustained upward momentum.",
    symbol: 'BTCUSDT',
    interval: '1h',
    start: DateTime.utc(2021, 9, 1),
    end: DateTime.utc(2021, 11, 15),
  ),
  CuratedPeriod(
    id: '2022_ftx_crash',
    name: '2022 Crash (FTX Collapse)',
    description:
        'The week FTX halted withdrawals and filed for bankruptcy — a sharp, fast crash.',
    symbol: 'BTCUSDT',
    interval: '15m',
    start: DateTime.utc(2022, 11, 6),
    end: DateTime.utc(2022, 11, 15),
  ),
  CuratedPeriod(
    id: '2025_oct_liquidation_cascade',
    name: '2025 Oct Liquidation Cascade',
    description:
        'A fast, leveraged-liquidation-driven cascade in October 2025 — high volatility over a short window.',
    symbol: 'BTCUSDT',
    interval: '5m',
    start: DateTime.utc(2025, 10, 9),
    end: DateTime.utc(2025, 10, 14),
  ),
];
