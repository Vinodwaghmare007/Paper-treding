from __future__ import annotations

import asyncio
import logging

import httpx
from fastapi import APIRouter, HTTPException

from ..models.schemas import AccuracyLedgerResponse, ForecastRequest, ForecastResponse
from ..services import ledger, scheduler
from ..services.arima_model import ForecastError, generate_forecast
from ..services.binance_client import BinanceApiError, BinanceRateLimitError, fetch_klines
from ..services.rate_limiter import forecast_rate_limiter

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/forecast", tags=["forecast"])

_HISTORY_LIMIT = 500


@router.post("", response_model=ForecastResponse)
async def create_forecast(payload: ForecastRequest) -> ForecastResponse:
    wait_seconds = await forecast_rate_limiter.check(payload.symbol)
    if wait_seconds is not None:
        raise HTTPException(
            status_code=429,
            detail=(
                f"Forecasts for {payload.symbol} are rate-limited to 1 per "
                f"30s (ARIMA fitting is CPU-heavy). Try again in "
                f"{wait_seconds:.1f}s."
            ),
        )

    try:
        history = await fetch_klines(
            payload.symbol, payload.interval, limit=_HISTORY_LIMIT
        )
    except BinanceRateLimitError as exc:
        raise HTTPException(status_code=429, detail=str(exc)) from exc
    except BinanceApiError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc
    except httpx.HTTPError as exc:
        # Network-level failure (timeout, DNS, proxy/connection refused) —
        # distinct from Binance answering with an error status, but the
        # caller shouldn't see a bare 500 either way.
        logger.warning("Network error fetching klines for %s: %s", payload.symbol, exc)
        raise HTTPException(
            status_code=503,
            detail=f"Could not reach Binance to fetch price history: {exc}",
        ) from exc

    try:
        # ARIMA fitting is synchronous/CPU-bound (statsmodels); running it
        # on the event loop directly would stall every other request this
        # process is serving (including the accuracy-ledger reads).
        result = await asyncio.to_thread(
            generate_forecast, history["close"], payload.steps
        )
    except ForecastError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc

    base_price = float(history["close"].iloc[-1])
    forecast_id, resolve_at = await ledger.record_forecast(
        symbol=payload.symbol,
        interval=payload.interval,
        steps=payload.steps,
        predicted_path=result["predicted_path"],
        base_price=base_price,
    )
    scheduler.schedule_resolution(forecast_id, resolve_at)

    return ForecastResponse(**result)


@router.get("/accuracy-ledger/{symbol}", response_model=AccuracyLedgerResponse)
async def get_accuracy_ledger(symbol: str) -> AccuracyLedgerResponse:
    data = await ledger.get_accuracy_ledger(symbol)
    return AccuracyLedgerResponse(**data)
