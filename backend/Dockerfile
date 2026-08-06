# --- Crypto Paper Trader forecast service ---------------------------------
# Single-stage image: statsmodels/numpy/pandas need a real build toolchain
# for their C extensions, and python:3.11-slim already ships the compiled
# wheels for these on PyPI (manylinux), so there's nothing to gain from a
# multi-stage build here — it would only add complexity.

FROM python:3.11-slim

WORKDIR /app

# Keep pip's cache out of the image and fail fast on install errors.
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app

# Where the accuracy-ledger SQLite file lives — see deploy notes below for
# why this MUST be a mounted volume in production, not container-local disk.
ENV FORECAST_DB_PATH=/data/forecasts.db
RUN mkdir -p /data

EXPOSE 8000

# $PORT is how Railway/Render tell the container which port to bind; default
# to 8000 for plain `docker run` / local testing.
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]

# ----------------------------------------------------------------------------
# DEPLOYMENT NOTES — cheapest options for a solo dev
# ----------------------------------------------------------------------------
#
# Both Railway and Render can build this image directly from the Dockerfile
# (no separate CI needed). Pick whichever's free/hobby tier you already have
# an account on; there's no functional difference for this service.
#
# IMPORTANT — SQLite persistence: the accuracy ledger lives in a SQLite file
# at $FORECAST_DB_PATH (/data/forecasts.db). Container-local disk is wiped
# on every redeploy on both platforms, so you MUST attach a persistent
# volume mounted at /data, or the accuracy ledger silently resets every time
# you ship a change. This is a one-time setup step on each platform (below).
#
# --- Railway ------------------------------------------------------------
#   1. railway login
#   2. railway init                     # from this backend/ directory
#   3. railway up                       # builds from this Dockerfile, deploys
#   4. In the Railway dashboard: Service -> Settings -> Volumes -> "New
#      Volume", mount path "/data". (Railway's free tier includes a small
#      amount of volume storage — plenty for a SQLite ledger file.)
#   5. Service -> Variables: Railway auto-injects $PORT; no extra env vars
#      are required unless you want to override FORECAST_DB_PATH.
#   6. Your public URL is under Service -> Settings -> Networking ->
#      "Generate Domain". Put that URL into the Flutter app's
#      ForecastApiSource base URL.
#
# --- Render --------------------------------------------------------------
#   1. Push this repo to GitHub (Render deploys from a connected repo, not
#      a local CLI push).
#   2. Render dashboard -> New -> Web Service -> connect the repo, set
#      "Root Directory" to `backend`, and "Environment" to Docker (Render
#      auto-detects this Dockerfile).
#   3. Instance type: the free tier works for testing, but free-tier
#      services spin down when idle (the next request pays a ~30-60s cold
#      start, and APScheduler jobs don't fire while the service is asleep,
#      which will delay ledger resolution) — use the cheapest paid plan
#      ("Starter") if you need the ledger's timing to stay accurate.
#   4. Render dashboard -> Disks -> Add Disk, mount path "/data", 1GB (the
#      smallest size) is far more than a SQLite ledger needs.
#   5. Render sets $PORT automatically; no other env vars required.
#   6. Your public URL is shown on the service's dashboard page — put that
#      into the Flutter app's ForecastApiSource base URL.
#
# --- Either platform: verify after deploying -----------------------------
#   curl https://<your-deployed-url>/health
#   curl -X POST https://<your-deployed-url>/forecast \
#     -H "Content-Type: application/json" \
#     -d '{"symbol":"BTCUSDT","interval":"1m","steps":15}'
