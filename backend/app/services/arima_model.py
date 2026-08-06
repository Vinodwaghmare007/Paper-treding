"""ARIMA-based short-horizon price forecasting.

Model-selection approach: a small explicit grid search over
p, d, q in range(0, 3), scored by AIC, using statsmodels directly —
rather than pmdarima's auto_arima. Reasoning: pmdarima pins narrow,
frequently-stale ranges of numpy/statsmodels and has a history of breaking
on new releases of either, which is an outsized maintenance risk for a
27-combination search space this small. A plain grid search is slower per
request but has zero extra dependency risk and every candidate order is
visible right here.

This produces a *statistical projection* off a short recent window, not a
reliable prediction — see the disclaimer wired into the API response. If no
candidate order converges to a usable fit, we raise rather than return a
fabricated forecast.
"""

from __future__ import annotations

import itertools
import warnings
from datetime import datetime, timezone

import numpy as np
import pandas as pd
from statsmodels.tsa.arima.model import ARIMA

_ORDER_RANGE = range(0, 3)  # p, d, q each in {0, 1, 2}
_MIN_OBSERVATIONS = 20


class ForecastError(Exception):
    """Raised when no ARIMA order converges to a usable fit, or the input
    series is unsuitable for forecasting. Never caught to fabricate a
    result — callers must surface this as a failed request.
    """


def _best_order(series: pd.Series) -> tuple[int, int, int]:
    best_order: tuple[int, int, int] | None = None
    best_aic = np.inf

    with warnings.catch_warnings():
        # statsmodels warns loudly (ConvergenceWarning, ValueWarning) for
        # every order that doesn't fit well during the search — expected
        # noise here since most of the 27 candidates are bad fits by design.
        warnings.simplefilter("ignore")
        for p, d, q in itertools.product(_ORDER_RANGE, repeat=3):
            try:
                result = ARIMA(series, order=(p, d, q)).fit()
            except (ValueError, np.linalg.LinAlgError):
                continue
            if not np.isfinite(result.aic):
                continue
            if result.aic < best_aic:
                best_aic = result.aic
                best_order = (p, d, q)

    if best_order is None:
        raise ForecastError(
            "No (p,d,q) order in range(0,3) converged to a usable ARIMA fit "
            "for this series."
        )
    return best_order


def generate_forecast(close_prices: pd.Series, steps: int = 15) -> dict:
    """Fits an ARIMA model to `close_prices` and forecasts `steps` points
    ahead.

    Raises:
        ForecastError: if the input is unsuitable or no order converges.
    """
    series = close_prices.dropna()
    if len(series) < _MIN_OBSERVATIONS:
        raise ForecastError(
            f"Need at least {_MIN_OBSERVATIONS} price points, got {len(series)}."
        )
    if series.nunique() <= 1:
        raise ForecastError("Price series is constant — nothing to forecast.")
    if steps < 1:
        raise ForecastError("steps must be >= 1.")

    order = _best_order(series)

    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        try:
            fitted = ARIMA(series, order=order).fit()
            forecast_result = fitted.get_forecast(steps=steps)
            conf_int = forecast_result.conf_int(alpha=0.05)
        except (ValueError, np.linalg.LinAlgError) as exc:
            raise ForecastError(
                f"ARIMA{order} converged during selection but failed to "
                f"produce a forecast: {exc}"
            ) from exc

    predicted_path = forecast_result.predicted_mean.tolist()
    lower_col, upper_col = conf_int.columns
    confidence_lower = conf_int[lower_col].tolist()
    confidence_upper = conf_int[upper_col].tolist()

    if not all(np.isfinite(v) for v in predicted_path):
        raise ForecastError("ARIMA produced a non-finite forecast.")

    return {
        "predicted_path": predicted_path,
        "confidence_upper": confidence_upper,
        "confidence_lower": confidence_lower,
        "model_order": list(order),
        "generated_at": datetime.now(timezone.utc).isoformat(),
    }
