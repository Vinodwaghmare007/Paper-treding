"""Pydantic request/response models for the forecasting API."""

from __future__ import annotations

from pydantic import BaseModel, Field, field_validator

_VALID_INTERVALS = {
    "1m", "3m", "5m", "15m", "30m",
    "1h", "2h", "4h", "6h", "8h", "12h",
    "1d", "3d", "1w", "1M",
}

DISCLAIMER = (
    "This is a mathematical projection based on historical price patterns. "
    "It is not financial advice and carries no guarantee of accuracy."
)


class ForecastRequest(BaseModel):
    symbol: str = Field(..., min_length=1, max_length=20, examples=["BTCUSDT"])
    interval: str = "1m"
    steps: int = Field(15, ge=1, le=60)

    @field_validator("symbol")
    @classmethod
    def _normalize_symbol(cls, value: str) -> str:
        return value.strip().upper()

    @field_validator("interval")
    @classmethod
    def _validate_interval(cls, value: str) -> str:
        if value not in _VALID_INTERVALS:
            raise ValueError(
                f"Unsupported interval '{value}'. Must be one of {sorted(_VALID_INTERVALS)}."
            )
        return value


class ForecastResponse(BaseModel):
    predicted_path: list[float]
    confidence_upper: list[float]
    confidence_lower: list[float]
    model_order: list[int]
    generated_at: str
    disclaimer: str = DISCLAIMER


class DailyAccuracy(BaseModel):
    date: str
    forecasts: int
    correct: int
    accuracy_pct: float | None


class AccuracyLedgerResponse(BaseModel):
    symbol: str
    total_forecasts: int
    resolved_forecasts: int
    pending_forecasts: int
    direction_correct_count: int
    direction_accuracy_pct: float | None
    last_30_days: list[DailyAccuracy]
    generated_at: str
