"""
config.py  —  FLUX CNC IoT · Entrega 2
========================================
CAMBIOS vs entrega anterior:
  ✗  DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD  →  ELIMINADOS (no hay Postgres)
  ✓  Umbrales de alerta, CSV_PATH, APP_*              →  Conservados
  ✨  INFLUX_*, MQTT_*                                →  Nuevos
"""

from pydantic import ConfigDict
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    # Evitar que claves extras en .env (p.ej. DB_... heredadas) rompan la carga de Settings
    model_config = ConfigDict(extra="ignore", env_file=".env")

    # ── Servidor FastAPI (sin cambios) ────────────────────────────────────────
    APP_HOST: str = "0.0.0.0"
    APP_PORT: int = 8000

    # ── CSV (sin cambios) ─────────────────────────────────────────────────────
    CSV_PATH: str = "data/lecturas.csv"

    # ── Umbrales de alerta (sin cambios) ─────────────────────────────────────
    TEMP_MIN:   float = 15.0
    TEMP_MAX:   float = 45.0
    HUM_MIN:    float = 20.0
    HUM_MAX:    float = 80.0
    ACCEL_MAX:  float = 2.0

    # ── InfluxDB (nuevo) ──────────────────────────────────────────────────────
    INFLUX_URL:    str = "http://influxdb:8086"   # nombre del servicio en docker-compose
    INFLUX_TOKEN:  str = ""                        # generado por David en el setup
    INFLUX_ORG:    str = "flux"
    INFLUX_BUCKET: str = "flux_cnc"

    # ── MQTT (nuevo, usado por el bridge) ─────────────────────────────────────
    MQTT_BROKER:   str = "localhost"               # IP pública AWS cuando está en la nube
    MQTT_PORT:     int = 1883
    MQTT_USER:     str = "flux_user"
    MQTT_PASSWORD: str = "flux_pass"

settings = Settings()
