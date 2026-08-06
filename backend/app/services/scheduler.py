"""APScheduler wiring for the accuracy ledger.

Each forecast gets its own one-off "date" job, fired exactly `steps` bars
after it was made, that fetches what actually happened and fills in the
ledger row. Using per-forecast jobs (rather than a generic poll loop) keeps
the "steps minutes after each forecast" requirement literal and makes each
job's intent traceable by id (`resolve-<forecast_id>`) in the scheduler's
job store.

APScheduler's in-memory job store doesn't survive a process restart, so
`reconcile_pending_on_startup` re-arms every still-unresolved forecast
(and immediately resolves any that matured while the process was down)
once at application startup.
"""

from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone

import httpx
from apscheduler.schedulers.asyncio import AsyncIOScheduler

from . import ledger
from .binance_client import BinanceApiError, BinanceRateLimitError, fetch_klines

logger = logging.getLogger(__name__)

_scheduler: AsyncIOScheduler | None = None

_RETRY_DELAY = timedelta(minutes=5)


def _require_scheduler() -> AsyncIOScheduler:
    if _scheduler is None:
        raise RuntimeError("Scheduler not started — call scheduler.start() first.")
    return _scheduler


def start() -> None:
    """(Re)creates and starts the scheduler.

    Deliberately builds a fresh AsyncIOScheduler rather than reusing one
    instance for the process's lifetime: APScheduler binds to whichever
    asyncio event loop is running when it starts, so a bare singleton would
    break on any second start/shutdown cycle against a new loop — which
    happens for real in tests (each TestClient spins up its own loop) and,
    just as much a risk in production, on any in-process lifespan restart.
    """
    global _scheduler
    if _scheduler is not None and _scheduler.running:
        return
    _scheduler = AsyncIOScheduler()
    _scheduler.start()


def shutdown() -> None:
    global _scheduler
    if _scheduler is not None and _scheduler.running:
        _scheduler.shutdown(wait=False)
    _scheduler = None


def schedule_resolution(forecast_id: int, resolve_at: datetime) -> None:
    _require_scheduler().add_job(
        _resolve_job,
        trigger="date",
        run_date=resolve_at,
        args=[forecast_id],
        id=f"resolve-{forecast_id}",
        replace_existing=True,
        # Fire immediately on catch-up rather than being silently dropped
        # if the event loop was briefly busy past run_date.
        misfire_grace_time=None,
    )


async def _resolve_job(forecast_id: int) -> None:
    row = await ledger.fetch_forecast(forecast_id)
    if row is None or row["actual_path_after_fill"] is not None:
        return  # already resolved, or the row was removed

    predicted_at = datetime.fromisoformat(row["predicted_at"])
    start_ms = int(predicted_at.timestamp() * 1000)

    try:
        frame = await fetch_klines(
            row["symbol"],
            row["interval"],
            limit=row["steps"],
            start_time_ms=start_ms,
        )
    except (BinanceApiError, BinanceRateLimitError, httpx.HTTPError) as exc:
        logger.warning(
            "Forecast %s: Binance fetch failed (%s), retrying in %s.",
            forecast_id, exc, _RETRY_DELAY,
        )
        _require_scheduler().add_job(
            _resolve_job,
            trigger="date",
            run_date=datetime.now(timezone.utc) + _RETRY_DELAY,
            args=[forecast_id],
            id=f"resolve-{forecast_id}",
            replace_existing=True,
        )
        return

    actual_path = frame["close"].tolist()[: row["steps"]]
    if len(actual_path) < row["steps"]:
        # Binance hasn't printed all the bars yet — check back shortly
        # instead of resolving against a short window.
        logger.info(
            "Forecast %s: only %d/%d actual bars available, retrying in %s.",
            forecast_id, len(actual_path), row["steps"], _RETRY_DELAY,
        )
        _require_scheduler().add_job(
            _resolve_job,
            trigger="date",
            run_date=datetime.now(timezone.utc) + _RETRY_DELAY,
            args=[forecast_id],
            id=f"resolve-{forecast_id}",
            replace_existing=True,
        )
        return

    await ledger.resolve_forecast(forecast_id, actual_path)
    logger.info("Resolved forecast %s against %d actual bars.", forecast_id, len(actual_path))


async def reconcile_pending_on_startup() -> None:
    now = datetime.now(timezone.utc)
    for row in await ledger.fetch_all_pending():
        resolve_at = datetime.fromisoformat(row["resolve_at"])
        if resolve_at <= now:
            await _resolve_job(row["id"])
        else:
            schedule_resolution(row["id"], resolve_at)
