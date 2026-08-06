from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .routers import forecast
from .services import ledger, scheduler

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    await ledger.init_db()
    scheduler.start()
    await scheduler.reconcile_pending_on_startup()
    logger.info("Forecast service ready.")
    yield
    scheduler.shutdown()


app = FastAPI(
    title="Crypto Paper Trader — Forecast Service",
    description=(
        "Educational ARIMA-based short-horizon price projections for the "
        "Crypto Paper Trader app, plus a public accuracy ledger tracking "
        "how often each forecast's direction call actually panned out."
    ),
    version="1.0.0",
    lifespan=lifespan,
)

# The Flutter app calls this API directly from the device, not from a
# browser page on a fixed origin, so there's no single origin to allow-list;
# CORS here only matters for the OpenAPI docs UI / any future web client.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET", "POST"],
    allow_headers=["*"],
)

app.include_router(forecast.router)


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}
