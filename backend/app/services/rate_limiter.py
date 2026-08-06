"""Per-symbol rate limiting for POST /forecast.

Deliberately not slowapi: slowapi's rate-limit key is derived from the
`Request` before the route's Pydantic body is parsed, which is a poor fit
here — the limit key is "symbol", a field inside the JSON body, not the
caller's IP/API key that slowapi is built around. A tiny in-memory limiter
keyed on whatever string the caller passes in is both simpler and more
correct for this one specific rule than fighting that mismatch.

In-memory is a deliberate, scale-appropriate choice: this is a single
solo-dev instance (see Dockerfile notes — one container, no horizontal
scaling), so there's no multi-process state to share. If this backend ever
runs more than one worker/replica, swap this for a Redis-backed limiter.
"""

from __future__ import annotations

import asyncio
import time


class SymbolRateLimiter:
    def __init__(self, window_seconds: float = 30.0) -> None:
        self._window_seconds = window_seconds
        self._last_request_at: dict[str, float] = {}
        self._lock = asyncio.Lock()

    async def check(self, key: str) -> float | None:
        """Returns None if the request is allowed (and records it), or the
        number of seconds the caller must still wait if it isn't.
        """
        async with self._lock:
            now = time.monotonic()
            last = self._last_request_at.get(key)
            if last is not None:
                elapsed = now - last
                if elapsed < self._window_seconds:
                    return self._window_seconds - elapsed
            self._last_request_at[key] = now
            return None


forecast_rate_limiter = SymbolRateLimiter(window_seconds=30.0)
