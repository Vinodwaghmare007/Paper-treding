import httpx
import pytest

from app.services.binance_client import (
    BinanceApiError,
    BinanceRateLimitError,
    fetch_klines,
)


def _kline_row(open_time_ms: int, close: float) -> list:
    return [
        open_time_ms, "100.0", "110.0", "90.0", str(close), "5.0",
        open_time_ms + 59_999, "500.0", 10, "2.5", "250.0", "0",
    ]


@pytest.mark.asyncio
async def test_fetch_klines_parses_dataframe():
    rows = [_kline_row(1_700_000_000_000 + i * 60_000, 100 + i) for i in range(3)]

    def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.params["symbol"] == "BTCUSDT"
        return httpx.Response(200, json=rows)

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        frame = await fetch_klines("btcusdt", "1m", limit=3, client=client)

    assert list(frame.columns) == ["open", "high", "low", "close", "volume"]
    assert len(frame) == 3
    assert frame["close"].tolist() == [100.0, 101.0, 102.0]
    assert frame.index.tz is not None  # UTC-aware index


@pytest.mark.asyncio
async def test_fetch_klines_rate_limit_raises_clear_exception():
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(429, headers={"Retry-After": "5"}, text="rate limited")

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        with pytest.raises(BinanceRateLimitError) as exc_info:
            await fetch_klines("BTCUSDT", client=client)

    assert exc_info.value.status_code == 429
    assert exc_info.value.retry_after == "5"


@pytest.mark.asyncio
async def test_fetch_klines_other_error_raises_api_error():
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(500, text="server error")

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        with pytest.raises(BinanceApiError):
            await fetch_klines("BTCUSDT", client=client)


@pytest.mark.asyncio
async def test_fetch_klines_passes_start_end_time():
    captured = {}

    def handler(request: httpx.Request) -> httpx.Response:
        captured["startTime"] = request.url.params.get("startTime")
        captured["endTime"] = request.url.params.get("endTime")
        return httpx.Response(200, json=[_kline_row(1_700_000_000_000, 100)])

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        await fetch_klines(
            "BTCUSDT", start_time_ms=123, end_time_ms=456, client=client
        )

    assert captured == {"startTime": "123", "endTime": "456"}
