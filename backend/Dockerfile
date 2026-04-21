# ── Stage: runtime ──────────────────────────────────────────
FROM python:3.11-slim

# Install uv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

WORKDIR /app

# Copy dependency manifests first for layer caching.
# uv.lock is included when present to guarantee reproducible installs.
COPY pyproject.toml uv.lock* ./

# Sync dependencies (no dev extras) into the project virtual env
RUN uv sync --no-dev

# Copy application source
COPY app/ ./app/

EXPOSE 8000

CMD ["uv", "run", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
