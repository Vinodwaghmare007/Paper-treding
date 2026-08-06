"""Thin async client for Binance's public spot market-data REST API.

Only the read-only `/api/v3/klines` endpoint is used — no API key required,
since this backend only ever reads public candle history to feed the
forecasting model.
"""

from __future__ import annotations

import pandas as pd
import httpx

BINANCE_BASE_URL = "https://api.binance.com"
_KLINES_PATH = "/api/v3/klines"

_COLUMNS = [
    "open_time",
    "open",
    "high",
    "low",
    "close",
    "volume",
    "close_time",
    "quote_asset_volume",
    "number_of_trades",
    "taker_buy_base_asset_volume",
    "taker_buy_quote_asset_volume",
    "ignore",
]

_NUMERIC_COLUMNS = ["open", "high", "low", "close", "volume"]


class BinanceRateLimitError(Exception):
    """Raised when Binance responds 429 (rate limit) or 418 (IP ban)."""

    def __init__(self, status_code: int, retry_after: str | None) -> None:
        self.status_code = status_code
        self.retry_after = retry_after
        message = (
            f"Binance rate limit hit (HTTP {status_code})."
            + (f" Retry-After: {retry_after}s." if retry_after else "")
        )
        super().__init__(message)


class BinanceApiError(Exception):
    """Raised for any other non-2xx response from Binance."""

    def __init__(self, status_code: int, body: str) -> None:
        self.status_code = status_code
        self.body = body
        super().__init__(f"Binance API error (HTTP {status_code}): {body}")


async def fetch_klines(
    symbol: str,
    interval: str = "1m",
    limit: int = 500,
    *,
    start_time_ms: int | None = None,
    end_time_ms: int | None = None,
    client: httpx.AsyncClient | None = None,
) -> pd.DataFrame:
    """Fetches recent candles and returns a DataFrame indexed by `open_time`
    (UTC `pandas.Timestamp`) with float columns: open, high, low, close,
    volume — oldest first, matching Binance's own ordering.

    `start_time_ms`/`end_time_ms` map to Binance's own `startTime`/`endTime`
    kline params, for fetching a precise historical window (e.g. the bars
    immediately following a past forecast) instead of "most recent N".

    Raises:
        BinanceRateLimitError: on HTTP 429/418.
        BinanceApiError: on any other non-2xx response.
        httpx.HTTPError: on network-level failures (timeout, DNS, etc.).
    """
    params: dict[str, str | int] = {
        "symbol": symbol.upper(),
        "interval": interval,
        "limit": limit,
    }
    if start_time_ms is not None:
        params["startTime"] = start_time_ms
    if end_time_ms is not None:
        params["endTime"] = end_time_ms

    owns_client = client is None
    http_client = client or httpx.AsyncClient(timeout=10.0)
    try:
        response = await http_client.get(
            f"{BINANCE_BASE_URL}{_KLINES_PATH}", params=params
        )
        if response.status_code in (429, 418):
            raise BinanceRateLimitError(
                response.status_code, response.headers.get("Retry-After")
            )
        if response.status_code != 200:
            raise BinanceApiError(response.status_code, response.text)

        raw = response.json()
    finally:
        if owns_client:
            await http_client.aclose()

    if not raw:
        raise BinanceApiError(200, "Empty klines payload")

    frame = pd.DataFrame(raw, columns=_COLUMNS)
    frame["open_time"] = pd.to_datetime(frame["open_time"], unit="ms", utc=True)
    frame[_NUMERIC_COLUMNS] = frame[_NUMERIC_COLUMNS].astype(float)
    frame = frame.set_index("open_time")
    return frame[_NUMERIC_COLUMNS]
