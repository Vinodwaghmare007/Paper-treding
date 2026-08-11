import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/kline_tick.dart';

/// Local sqflite cache backing offline mode (Phase G2 Part B) for the two
/// kinds of live data that AREN'T already covered by Firestore's own
/// built-in offline persistence:
///
/// - Last-known Binance/CoinGecko prices (REST/WebSocket-sourced, no
///   Firestore involved at all).
/// - The live chart's seed candles (fetched fresh via
///   BinanceRestService.fetchKlines on every visit — unlike Market
///   Replay's curated periods, which already have their own sqflite cache
///   in historical_data_cache.dart, the *live* chart never persisted its
///   candles before this).
///
/// Deliberately NOT duplicated here: portfolio positions, orders, account
/// balance, and watchlist entries. Those are all `cloud_firestore` reads
/// (`watchPortfolio`/`watchAccount`/`watchOrders`/`watchWatchlist`), and
/// `cloud_firestore` has offline persistence enabled by default on mobile
/// — the SDK already caches the last-received snapshot on disk and keeps
/// serving it (via the exact same `Stream` those providers already watch)
/// when the device goes offline, with no extra code needed. Building a
/// second, parallel sqflite cache for that data would be redundant and a
/// second source of truth to keep in sync for zero benefit.
class AppDatabase {
  AppDatabase({Database? database}) : _databaseOverride = database;

  final Database? _databaseOverride;
  Database? _db;

  Future<Database> _database() async {
    if (_databaseOverride != null) return _databaseOverride;
    if (_db != null) return _db!;

    final dbPath = p.join(await getDatabasesPath(), 'app_cache.db');
    _db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE cached_prices (
            symbol TEXT PRIMARY KEY,
            price REAL NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE cached_candles (
            cache_key TEXT NOT NULL,
            open_time INTEGER NOT NULL,
            close_time INTEGER NOT NULL,
            open REAL NOT NULL,
            high REAL NOT NULL,
            low REAL NOT NULL,
            close REAL NOT NULL,
            volume REAL NOT NULL,
            PRIMARY KEY (cache_key, open_time)
          )
        ''');
        await db.execute('''
          CREATE TABLE cached_candles_meta (
            cache_key TEXT PRIMARY KEY,
            fetched_at INTEGER NOT NULL
          )
        ''');
      },
    );
    return _db!;
  }

  /// Upserts one symbol's last-known price. Called opportunistically
  /// whenever a live price successfully arrives (WebSocket tick, REST
  /// poll) — see offline_providers.dart's wiring — so there's always
  /// something to fall back to the next time the device is offline.
  Future<void> savePrice(String symbol, double price) async {
    final db = await _database();
    await db.insert(
      'cached_prices',
      {'symbol': symbol, 'price': price, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Every cached price at once, for a portfolio-wide offline fallback.
  Future<Map<String, CachedPrice>> loadAllPrices() async {
    final db = await _database();
    final rows = await db.query('cached_prices');
    return {
      for (final row in rows)
        row['symbol'] as String: CachedPrice(
          price: row['price'] as double,
          updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
        ),
    };
  }

  Future<CachedPrice?> loadPrice(String symbol) async {
    final db = await _database();
    final rows = await db.query('cached_prices', where: 'symbol = ?', whereArgs: [symbol], limit: 1);
    if (rows.isEmpty) return null;
    return CachedPrice(
      price: rows.first['price'] as double,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(rows.first['updated_at'] as int),
    );
  }

  /// Replaces the cached candle set for [symbol]/[interval] wholesale —
  /// this is a full seed-candle snapshot (matching what
  /// BinanceRestService.fetchKlines returns), not something to merge
  /// incrementally, so a stale partial set can never linger.
  Future<void> saveCandles(String symbol, String interval, List<Candle> candles) async {
    final db = await _database();
    final cacheKey = _candleCacheKey(symbol, interval);
    final batch = db.batch();
    batch.delete('cached_candles', where: 'cache_key = ?', whereArgs: [cacheKey]);
    for (final candle in candles) {
      batch.insert(
        'cached_candles',
        {
          'cache_key': cacheKey,
          'open_time': candle.openTimeMs,
          'close_time': candle.closeTimeMs,
          'open': candle.open,
          'high': candle.high,
          'low': candle.low,
          'close': candle.close,
          'volume': candle.volume,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    batch.insert(
      'cached_candles_meta',
      {'cache_key': cacheKey, 'fetched_at': DateTime.now().millisecondsSinceEpoch},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await batch.commit(noResult: true);
  }

  /// Null if [symbol]/[interval] has never been cached — callers fall back
  /// to their own "no data at all" empty state in that case (a brand-new
  /// install that's never been online for this symbol/interval).
  Future<CachedCandles?> loadCandles(String symbol, String interval) async {
    final db = await _database();
    final cacheKey = _candleCacheKey(symbol, interval);
    final metaRows =
        await db.query('cached_candles_meta', where: 'cache_key = ?', whereArgs: [cacheKey], limit: 1);
    if (metaRows.isEmpty) return null;

    final rows = await db.query(
      'cached_candles',
      where: 'cache_key = ?',
      whereArgs: [cacheKey],
      orderBy: 'open_time ASC',
    );
    final candles = rows
        .map((row) => Candle(
              openTimeMs: row['open_time'] as int,
              closeTimeMs: row['close_time'] as int,
              open: row['open'] as double,
              high: row['high'] as double,
              low: row['low'] as double,
              close: row['close'] as double,
              volume: row['volume'] as double,
            ))
        .toList(growable: false);

    return CachedCandles(
      candles: candles,
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(metaRows.first['fetched_at'] as int),
    );
  }

  String _candleCacheKey(String symbol, String interval) => '$symbol|$interval';

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}

class CachedPrice {
  const CachedPrice({required this.price, required this.updatedAt});
  final double price;
  final DateTime updatedAt;
}

class CachedCandles {
  const CachedCandles({required this.candles, required this.fetchedAt});
  final List<Candle> candles;
  final DateTime fetchedAt;
}
