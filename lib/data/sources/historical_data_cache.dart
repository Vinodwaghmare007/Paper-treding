import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../entities/curated_period.dart';
import '../models/kline_tick.dart';
import 'binance_rest_service.dart';

/// Local SQLite cache for [curatedPeriods]' candle data, so Market Replay
/// only ever pulls each curated window from Binance once. Downloading
/// respects Binance's REST rate limits via
/// [BinanceRestService.fetchKlinesRange]'s built-in pagination + delay
/// between requests — this class only owns persistence and progress
/// reporting on top of that.
class HistoricalDataCache {
  HistoricalDataCache({Database? database}) : _databaseOverride = database;

  final Database? _databaseOverride;
  Database? _db;

  Future<Database> _database() async {
    if (_databaseOverride != null) return _databaseOverride;
    if (_db != null) return _db!;

    final dbPath = p.join(await getDatabasesPath(), 'historical_replay_cache.db');
    _db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE candles (
            period_id TEXT NOT NULL,
            open_time INTEGER NOT NULL,
            close_time INTEGER NOT NULL,
            open REAL NOT NULL,
            high REAL NOT NULL,
            low REAL NOT NULL,
            close REAL NOT NULL,
            volume REAL NOT NULL,
            PRIMARY KEY (period_id, open_time)
          )
        ''');
        await db.execute('''
          CREATE TABLE download_status (
            period_id TEXT PRIMARY KEY,
            completed INTEGER NOT NULL,
            candle_count INTEGER NOT NULL
          )
        ''');
      },
    );
    return _db!;
  }

  Future<bool> isPeriodCached(String periodId) async {
    final db = await _database();
    final rows = await db.query(
      'download_status',
      where: 'period_id = ? AND completed = 1',
      whereArgs: [periodId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Downloads [period]'s full candle range and caches it, reporting
  /// progress as candles arrive. Safe to call again on a partially-failed
  /// prior attempt — clears any partial rows for this period first so a
  /// retry can't leave duplicate or truncated data behind.
  Future<void> downloadPeriod(
    CuratedPeriod period, {
    required BinanceRestService restService,
    void Function(int fetchedCandles)? onProgress,
  }) async {
    final db = await _database();
    await db.delete('candles', where: 'period_id = ?', whereArgs: [period.id]);
    await db.delete('download_status', where: 'period_id = ?', whereArgs: [period.id]);

    final candles = await restService.fetchKlinesRange(
      symbol: period.symbol,
      interval: period.interval,
      start: period.start,
      end: period.end,
      onProgress: onProgress,
    );

    final batch = db.batch();
    for (final candle in candles) {
      batch.insert(
        'candles',
        {
          'period_id': period.id,
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
      'download_status',
      {'period_id': period.id, 'completed': 1, 'candle_count': candles.length},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await batch.commit(noResult: true);
  }

  /// Loads a previously-downloaded period's candles, oldest first. Throws
  /// [StateError] if the period was never (fully) downloaded — callers
  /// should check [isPeriodCached] first, or catch this and fall back to
  /// [downloadPeriod].
  Future<List<Candle>> loadPeriod(String periodId) async {
    if (!await isPeriodCached(periodId)) {
      throw StateError('Period "$periodId" has not been downloaded yet.');
    }
    final db = await _database();
    final rows = await db.query(
      'candles',
      where: 'period_id = ?',
      whereArgs: [periodId],
      orderBy: 'open_time ASC',
    );
    return rows
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
  }

  Future<void> deletePeriod(String periodId) async {
    final db = await _database();
    await db.delete('candles', where: 'period_id = ?', whereArgs: [periodId]);
    await db.delete('download_status', where: 'period_id = ?', whereArgs: [periodId]);
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
