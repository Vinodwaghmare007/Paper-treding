from datetime import datetime, timedelta, timezone

import pytest

from app.services import ledger


@pytest.fixture(autouse=True)
def isolated_db(tmp_path, monkeypatch):
    monkeypatch.setattr(ledger, "DB_PATH", tmp_path / "test_forecasts.db")


async def test_record_and_fetch_forecast_round_trip():
    await ledger.init_db()

    forecast_id, resolve_at = await ledger.record_forecast(
        symbol="BTCUSDT",
        interval="1m",
        steps=3,
        predicted_path=[101.0, 102.0, 103.0],
        base_price=100.0,
    )

    assert resolve_at - datetime.now(timezone.utc) < timedelta(minutes=4)

    row = await ledger.fetch_forecast(forecast_id)
    assert row["symbol"] == "BTCUSDT"
    assert row["actual_path_after_fill"] is None


async def test_resolve_forecast_marks_direction_correct_when_both_up():
    await ledger.init_db()
    forecast_id, _ = await ledger.record_forecast(
        symbol="ETHUSDT", interval="1m", steps=2,
        predicted_path=[105.0, 110.0], base_price=100.0,
    )

    await ledger.resolve_forecast(forecast_id, actual_path=[103.0, 108.0])

    row = await ledger.fetch_forecast(forecast_id)
    assert row["direction_correct"] == 1  # predicted up (110>100), actual up (108>100)


async def test_resolve_forecast_marks_direction_incorrect_on_mismatch():
    await ledger.init_db()
    forecast_id, _ = await ledger.record_forecast(
        symbol="ETHUSDT", interval="1m", steps=2,
        predicted_path=[105.0, 110.0], base_price=100.0,  # predicted up
    )

    await ledger.resolve_forecast(forecast_id, actual_path=[95.0, 90.0])  # actually down

    row = await ledger.fetch_forecast(forecast_id)
    assert row["direction_correct"] == 0


async def test_accuracy_ledger_aggregates_resolved_forecasts():
    await ledger.init_db()

    id1, _ = await ledger.record_forecast(
        symbol="BTCUSDT", interval="1m", steps=1,
        predicted_path=[110.0], base_price=100.0,
    )
    id2, _ = await ledger.record_forecast(
        symbol="BTCUSDT", interval="1m", steps=1,
        predicted_path=[110.0], base_price=100.0,
    )
    # A third forecast intentionally left unresolved (pending).
    await ledger.record_forecast(
        symbol="BTCUSDT", interval="1m", steps=1,
        predicted_path=[110.0], base_price=100.0,
    )

    await ledger.resolve_forecast(id1, actual_path=[120.0])  # correct (up)
    await ledger.resolve_forecast(id2, actual_path=[90.0])  # incorrect (down)

    summary = await ledger.get_accuracy_ledger("BTCUSDT")

    assert summary["total_forecasts"] == 3
    assert summary["resolved_forecasts"] == 2
    assert summary["pending_forecasts"] == 1
    assert summary["direction_correct_count"] == 1
    assert summary["direction_accuracy_pct"] == 50.0
    assert len(summary["last_30_days"]) == 1
    assert summary["last_30_days"][0]["forecasts"] == 2
    assert summary["last_30_days"][0]["correct"] == 1


async def test_accuracy_ledger_handles_symbol_with_no_forecasts():
    await ledger.init_db()
    summary = await ledger.get_accuracy_ledger("DOGEUSDT")

    assert summary["total_forecasts"] == 0
    assert summary["direction_accuracy_pct"] is None
    assert summary["last_30_days"] == []


async def test_fetch_pending_due_only_returns_overdue_unresolved():
    await ledger.init_db()
    id_due, _ = await ledger.record_forecast(
        symbol="BTCUSDT", interval="1m", steps=1,
        predicted_path=[101.0], base_price=100.0,
    )
    future_time = datetime.now(timezone.utc) + timedelta(hours=1)

    due = await ledger.fetch_pending_due(as_of=future_time)
    assert any(row["id"] == id_due for row in due)

    past_time = datetime.now(timezone.utc) - timedelta(hours=1)
    not_yet_due = await ledger.fetch_pending_due(as_of=past_time)
    assert not any(row["id"] == id_due for row in not_yet_due)
