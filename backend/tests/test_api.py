import numpy as np
import pandas as pd
import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.routers import forecast as forecast_router
from app.services import ledger, rate_limiter


def _synthetic_frame(n: int = 200) -> pd.DataFrame:
    rng = np.random.default_rng(7)
    prices = 100 + np.cumsum(rng.normal(0, 1, n))
    index = pd.date_range("2026-01-01", periods=n, freq="1min", tz="UTC")
    return pd.DataFrame(
        {
            "open": prices,
            "high": prices + 1,
            "low": prices - 1,
            "close": prices,
            "volume": np.full(n, 10.0),
        },
        index=index,
    )


@pytest.fixture(autouse=True)
def isolated_backend(tmp_path, monkeypatch):
    monkeypatch.setattr(ledger, "DB_PATH", tmp_path / "test_api_forecasts.db")
    # Fresh limiter state per test so tests don't trip each other's 30s window.
    monkeypatch.setattr(
        rate_limiter, "forecast_rate_limiter", rate_limiter.SymbolRateLimiter(30.0)
    )
    monkeypatch.setattr(
        forecast_router, "forecast_rate_limiter", rate_limiter.forecast_rate_limiter
    )

    async def fake_fetch_klines(symbol, interval="1m", limit=500, **kwargs):
        return _synthetic_frame()

    monkeypatch.setattr(forecast_router, "fetch_klines", fake_fetch_klines)


def test_post_forecast_returns_expected_shape_and_disclaimer():
    with TestClient(app) as client:
        response = client.post(
            "/forecast", json={"symbol": "BTCUSDT", "interval": "1m", "steps": 5}
        )

    assert response.status_code == 200
    body = response.json()
    assert len(body["predicted_path"]) == 5
    assert len(body["confidence_upper"]) == 5
    assert len(body["confidence_lower"]) == 5
    assert len(body["model_order"]) == 3
    assert "not financial advice" in body["disclaimer"]


def test_post_forecast_rate_limits_repeat_requests_for_same_symbol():
    with TestClient(app) as client:
        first = client.post(
            "/forecast", json={"symbol": "BTCUSDT", "interval": "1m", "steps": 3}
        )
        second = client.post(
            "/forecast", json={"symbol": "BTCUSDT", "interval": "1m", "steps": 3}
        )

    assert first.status_code == 200
    assert second.status_code == 429
    assert "rate-limited" in second.json()["detail"]


def test_post_forecast_different_symbols_not_mutually_rate_limited():
    with TestClient(app) as client:
        btc = client.post(
            "/forecast", json={"symbol": "BTCUSDT", "interval": "1m", "steps": 3}
        )
        eth = client.post(
            "/forecast", json={"symbol": "ETHUSDT", "interval": "1m", "steps": 3}
        )

    assert btc.status_code == 200
    assert eth.status_code == 200


def test_post_forecast_rejects_invalid_interval():
    with TestClient(app) as client:
        response = client.post(
            "/forecast", json={"symbol": "BTCUSDT", "interval": "7x", "steps": 3}
        )
    assert response.status_code == 422


def test_accuracy_ledger_reflects_recorded_forecast():
    with TestClient(app) as client:
        client.post(
            "/forecast", json={"symbol": "SOLUSDT", "interval": "1m", "steps": 3}
        )
        response = client.get("/forecast/accuracy-ledger/SOLUSDT")

    assert response.status_code == 200
    body = response.json()
    assert body["symbol"] == "SOLUSDT"
    assert body["total_forecasts"] == 1
    assert body["pending_forecasts"] == 1


def test_health_endpoint():
    with TestClient(app) as client:
        response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}
