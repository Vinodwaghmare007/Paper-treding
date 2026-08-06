import numpy as np
import pandas as pd
import pytest

from app.services.arima_model import ForecastError, generate_forecast


def _synthetic_series(n: int = 200, seed: int = 42) -> pd.Series:
    rng = np.random.default_rng(seed)
    # A random walk is a much more realistic stand-in for a price series
    # than white noise — ARIMA's whole point is modeling that kind of
    # drift/autocorrelation.
    steps = rng.normal(loc=0.0, scale=1.0, size=n)
    prices = 100 + np.cumsum(steps)
    index = pd.date_range("2026-01-01", periods=n, freq="1min", tz="UTC")
    return pd.Series(prices, index=index, name="close")


def test_generate_forecast_returns_expected_shape():
    result = generate_forecast(_synthetic_series(), steps=5)

    assert len(result["predicted_path"]) == 5
    assert len(result["confidence_upper"]) == 5
    assert len(result["confidence_lower"]) == 5
    assert len(result["model_order"]) == 3
    assert all(isinstance(v, int) for v in result["model_order"])
    # generated_at must be a parseable ISO 8601 timestamp
    from datetime import datetime
    datetime.fromisoformat(result["generated_at"])


def test_confidence_band_contains_point_forecast():
    result = generate_forecast(_synthetic_series(), steps=5)
    for lower, point, upper in zip(
        result["confidence_lower"], result["predicted_path"], result["confidence_upper"]
    ):
        assert lower <= point <= upper


def test_generate_forecast_rejects_too_short_series():
    short_series = _synthetic_series(n=5)
    with pytest.raises(ForecastError):
        generate_forecast(short_series, steps=5)


def test_generate_forecast_rejects_constant_series():
    index = pd.date_range("2026-01-01", periods=50, freq="1min", tz="UTC")
    constant_series = pd.Series([100.0] * 50, index=index)
    with pytest.raises(ForecastError):
        generate_forecast(constant_series, steps=5)


def test_generate_forecast_rejects_invalid_steps():
    with pytest.raises(ForecastError):
        generate_forecast(_synthetic_series(), steps=0)
