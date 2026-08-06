"""SQLite-backed accuracy ledger: every forecast is recorded, then resolved
`steps` bars later against the actual close prices Binance printed.

This exists for transparency, not just debugging: the whole point of the
"Prediction Accuracy Ledger" feature is that users can see, honestly, how
often the model's *direction* call (price up vs. down from the forecast
baseline) actually panned out — hence "direction_correct" as the single
headline number, rather than pretending point-forecast error is meaningful
to a non-technical user.

Plain sqlite3 (stdlib) is enough at this scale — one solo-dev service,
low request volume — so no extra dependency for a database driver. Calls
are pushed onto a worker thread via asyncio.to_thread so a slow disk write
never blocks the event loop.
"""

from __future__ import annotations

import asyncio
import json
import os
import sqlite3
from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
from pathlib import Path

DB_PATH = Path(os.environ.get("FORECAST_DB_PATH", Path(__file__).parents[2] / "data" / "forecasts.db"))

_INTERVAL_MINUTES = {
    "1m": 1, "3m": 3, "5m": 5, "15m": 15, "30m": 30,
    "1h": 60, "2h": 120, "4h": 240, "6h": 360, "8h": 480, "12h": 720,
    "1d": 1440, "3d": 4320, "1w": 10080, "1M": 43200,
}


def interval_to_minutes(interval: str) -> int:
    try:
        return _INTERVAL_MINUTES[interval]
    except KeyError as exc:
        raise ValueError(f"Unknown interval '{interval}'") from exc


@contextmanager
def _connect():
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()


def _init_db_sync() -> None:
    with _connect() as conn:
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS forecasts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                symbol TEXT NOT NULL,
                interval TEXT NOT NULL,
                steps INTEGER NOT NULL,
                predicted_at TEXT NOT NULL,
                resolve_at TEXT NOT NULL,
                base_price REAL NOT NULL,
                predicted_path TEXT NOT NULL,
                actual_path_after_fill TEXT,
                direction_correct INTEGER,
                resolved_at TEXT
            )
            """
        )
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_forecasts_symbol ON forecasts(symbol)"
        )
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_forecasts_resolve_at "
            "ON forecasts(resolve_at) WHERE actual_path_after_fill IS NULL"
        )


async def init_db() -> None:
    await asyncio.to_thread(_init_db_sync)


def _record_forecast_sync(
    symbol: str,
    interval: str,
    steps: int,
    predicted_path: list[float],
    base_price: float,
) -> tuple[int, datetime]:
    now = datetime.now(timezone.utc)
    resolve_at = now + timedelta(minutes=interval_to_minutes(interval) * steps)
    with _connect() as conn:
        cursor = conn.execute(
            """
            INSERT INTO forecasts
                (symbol, interval, steps, predicted_at, resolve_at,
                 base_price, predicted_path)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (
                symbol,
                interval,
                steps,
                now.isoformat(),
                resolve_at.isoformat(),
                base_price,
                json.dumps(predicted_path),
            ),
        )
        forecast_id = cursor.lastrowid
    return forecast_id, resolve_at


async def record_forecast(
    symbol: str,
    interval: str,
    steps: int,
    predicted_path: list[float],
    base_price: float,
) -> tuple[int, datetime]:
    return await asyncio.to_thread(
        _record_forecast_sync, symbol, interval, steps, predicted_path, base_price
    )


def _resolve_forecast_sync(forecast_id: int, actual_path: list[float]) -> None:
    with _connect() as conn:
        row = conn.execute(
            "SELECT base_price, predicted_path FROM forecasts WHERE id = ?",
            (forecast_id,),
        ).fetchone()
        if row is None:
            return
        predicted_path = json.loads(row["predicted_path"])
        base_price = row["base_price"]
        predicted_direction_up = predicted_path[-1] >= base_price
        actual_direction_up = actual_path[-1] >= base_price
        direction_correct = predicted_direction_up == actual_direction_up

        conn.execute(
            """
            UPDATE forecasts
            SET actual_path_after_fill = ?, direction_correct = ?, resolved_at = ?
            WHERE id = ?
            """,
            (
                json.dumps(actual_path),
                1 if direction_correct else 0,
                datetime.now(timezone.utc).isoformat(),
                forecast_id,
            ),
        )


async def resolve_forecast(forecast_id: int, actual_path: list[float]) -> None:
    await asyncio.to_thread(_resolve_forecast_sync, forecast_id, actual_path)


def _fetch_pending_due_sync(as_of: datetime) -> list[sqlite3.Row]:
    with _connect() as conn:
        return conn.execute(
            """
            SELECT id, symbol, interval, steps, predicted_at, resolve_at
            FROM forecasts
            WHERE actual_path_after_fill IS NULL AND resolve_at <= ?
            """,
            (as_of.isoformat(),),
        ).fetchall()


async def fetch_pending_due(as_of: datetime | None = None) -> list[sqlite3.Row]:
    return await asyncio.to_thread(_fetch_pending_due_sync, as_of or datetime.now(timezone.utc))


def _fetch_all_pending_sync() -> list[sqlite3.Row]:
    with _connect() as conn:
        return conn.execute(
            """
            SELECT id, symbol, interval, steps, predicted_at, resolve_at
            FROM forecasts
            WHERE actual_path_after_fill IS NULL
            """
        ).fetchall()


async def fetch_all_pending() -> list[sqlite3.Row]:
    """Every unresolved forecast regardless of due date — used once at
    startup to re-arm in-memory scheduler jobs that don't survive a
    process restart.
    """
    return await asyncio.to_thread(_fetch_all_pending_sync)


def _fetch_forecast_sync(forecast_id: int) -> sqlite3.Row | None:
    with _connect() as conn:
        return conn.execute(
            "SELECT * FROM forecasts WHERE id = ?", (forecast_id,)
        ).fetchone()


async def fetch_forecast(forecast_id: int) -> sqlite3.Row | None:
    return await asyncio.to_thread(_fetch_forecast_sync, forecast_id)


def _get_accuracy_ledger_sync(symbol: str) -> dict:
    with _connect() as conn:
        rows = conn.execute(
            """
            SELECT predicted_at, resolved_at, direction_correct
            FROM forecasts
            WHERE symbol = ?
            ORDER BY predicted_at
            """,
            (symbol,),
        ).fetchall()

    total = len(rows)
    resolved = [r for r in rows if r["direction_correct"] is not None]
    correct = [r for r in resolved if r["direction_correct"] == 1]

    cutoff = datetime.now(timezone.utc) - timedelta(days=30)
    by_day: dict[str, dict[str, int]] = {}
    for row in resolved:
        resolved_at = datetime.fromisoformat(row["resolved_at"])
        if resolved_at < cutoff:
            continue
        day_key = resolved_at.date().isoformat()
        bucket = by_day.setdefault(day_key, {"forecasts": 0, "correct": 0})
        bucket["forecasts"] += 1
        if row["direction_correct"] == 1:
            bucket["correct"] += 1

    last_30_days = [
        {
            "date": day,
            "forecasts": stats["forecasts"],
            "correct": stats["correct"],
            "accuracy_pct": round(100 * stats["correct"] / stats["forecasts"], 2)
            if stats["forecasts"]
            else None,
        }
        for day, stats in sorted(by_day.items())
    ]

    return {
        "symbol": symbol,
        "total_forecasts": total,
        "resolved_forecasts": len(resolved),
        "pending_forecasts": total - len(resolved),
        "direction_correct_count": len(correct),
        "direction_accuracy_pct": round(100 * len(correct) / len(resolved), 2)
        if resolved
        else None,
        "last_30_days": last_30_days,
        "generated_at": datetime.now(timezone.utc).isoformat(),
    }


async def get_accuracy_ledger(symbol: str) -> dict:
    return await asyncio.to_thread(_get_accuracy_ledger_sync, symbol.upper())
