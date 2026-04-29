# ── Stage: runtime ──────────────────────────────────────────
FROM python:3.12-slim

# Install uv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

WORKDIR /app

# Copy dependency manifests first for layer caching.
# uv.lock is included when present to guarantee reproducible installs.
COPY pyproject.toml uv.lock* ./

# Sync dependencies (no dev extras) into the project virtual env
# Force uv to use the container's Python 3.12 interpreter (matches uv.lock wheels).
RUN uv sync --no-dev --python /usr/local/bin/python3.12

# Copy application source
COPY app/ ./app/

EXPOSE 8000

CMD ["uv", "run", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
