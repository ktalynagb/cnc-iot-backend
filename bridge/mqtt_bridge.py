"""
mqtt_bridge.py  —  FLUX CNC IoT · Entrega 2
============================================
Suscribe los topics MQTT del ESP32, calcula vibración,
evalúa alertas, escribe en InfluxDB y actualiza el CSV.

Topics esperados (publicados por el ESP32):
  flux/cnc1/temperatura   → {"value": 28.5}
  flux/cnc1/humedad       → {"value": 60.2}
  flux/cnc1/vibracion     → {"accel_x": 0.12, "accel_y": -0.03, "accel_z": 9.81}

Ejecución:
  python bridge/mqtt_bridge.py

Como servicio systemd, ver: bridge/mqtt_bridge.service
"""

import json
import logging
import os
import time
from datetime import datetime, timezone
from threading import Event
from types import SimpleNamespace

import paho.mqtt.client as mqtt
from influxdb_client import InfluxDBClient, Point, WritePrecision
from influxdb_client.client.write_api import SYNCHRONOUS

# ── Importar lógica existente del backend ────────────────────────────────────
import sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "backend"))

from app.alertas import calcular_vibracion, evaluar_alerta
from app.config import settings
from dotenv import load_dotenv
load_dotenv(os.path.join(os.path.dirname(__file__), "..", "backend", ".env"))
from app.csv_writer import guardar_lectura_csv

# ── Logging ───────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger("mqtt_bridge")

# ── Configuración MQTT e InfluxDB (desde variables de entorno o .env) ─────────
MQTT_BROKER   = os.getenv("MQTT_BROKER",   "localhost")
MQTT_PORT     = int(os.getenv("MQTT_PORT", "1883"))
MQTT_USER     = os.getenv("MQTT_USER",     "flux_user")
MQTT_PASSWORD = os.getenv("MQTT_PASSWORD", "flux_pass")
MQTT_TOPICS   = [
    "flux/cnc1/temperatura",
    "flux/cnc1/humedad",
    "flux/cnc1/vibracion",
]

INFLUX_URL    = os.getenv("INFLUX_URL",    "http://localhost:8086")
INFLUX_TOKEN  = os.getenv("INFLUX_TOKEN",  "")          # generado por David
INFLUX_ORG    = os.getenv("INFLUX_ORG",    "flux")
INFLUX_BUCKET = os.getenv("INFLUX_BUCKET", "flux_cnc")

# ── Estado compartido entre callbacks ─────────────────────────────────────────
# Acumulamos lecturas parciales hasta tener temperatura + humedad + vibracion
_buffer: dict = {}
_CAMPOS_REQUERIDOS = {"temperatura", "humedad", "accel_x", "accel_y", "accel_z"}

# ── InfluxDB ──────────────────────────────────────────────────────────────────
_influx_client = InfluxDBClient(
    url=INFLUX_URL,
    token=INFLUX_TOKEN,
    org=INFLUX_ORG,
)
_write_api = _influx_client.write_api(write_options=SYNCHRONOUS)


def _escribir_influx(ts: datetime, temp: float, hum: float,
                     ax: float, ay: float, az: float,
                     vib: float, alerta: bool, motivo: str | None) -> None:
    """Escribe un punto de medición en InfluxDB."""
    point = (
        Point("cnc_sensores")
        .tag("maquina", "cnc1")
        .tag("alerta", str(alerta))
        .field("temperatura",    temp)
        .field("humedad",        hum)
        .field("accel_x",        ax)
        .field("accel_y",        ay)
        .field("accel_z",        az)
        .field("vibracion_total", vib)
        .field("motivo_alerta",  motivo or "")
        .time(ts, "s")
    )
    _write_api.write(bucket=INFLUX_BUCKET, org=INFLUX_ORG, record=point)
    log.info("  → InfluxDB ✓  vib=%.4f  alerta=%s", vib, alerta)


def _procesar_lectura_completa(ts: datetime) -> None:
    """
    Cuando el buffer tiene todos los campos, calcula vibración,
    evalúa alertas, escribe en InfluxDB y en CSV.
    """
    b = _buffer
    ax, ay, az = b["accel_x"], b["accel_y"], b["accel_z"]

    vibracion         = calcular_vibracion(ax, ay, az)
    alerta, motivo    = evaluar_alerta(b["temperatura"], b["humedad"], vibracion)

    log.info("Lectura completa — T=%.2f°C  H=%.2f%%  Vib=%.4f m/s²  Alerta=%s",
             b["temperatura"], b["humedad"], vibracion, alerta)

    # Escribir en InfluxDB
    _escribir_influx(ts, b["temperatura"], b["humedad"],
                     ax, ay, az, vibracion, alerta, motivo)

    # Reusar csv_writer.py sin modificarlo — construimos un objeto compatible
    lectura_csv = SimpleNamespace(
        id=int(ts.timestamp()),          # ID sintético basado en timestamp
        timestamp=ts,
        temperatura=b["temperatura"],
        humedad=b["humedad"],
        accel_x=ax,
        accel_y=ay,
        accel_z=az,
        vibracion_total=vibracion,
        alerta=alerta,
        motivo_alerta=motivo,
    )
    guardar_lectura_csv(lectura_csv)
    log.info("  → CSV ✓")

    if alerta:
        log.warning("  ⚠ ALERTA: %s", motivo)

    # Limpiar buffer para la siguiente ronda
    _buffer.clear()


# ── Callbacks MQTT ────────────────────────────────────────────────────────────

def on_connect(client, userdata, flags, rc, properties=None):
    if rc == 0:
        log.info("Conectado al broker MQTT %s:%s", MQTT_BROKER, MQTT_PORT)
        for topic in MQTT_TOPICS:
            client.subscribe(topic, qos=1)
            log.info("  Suscrito a: %s", topic)
    else:
        log.error("Error de conexión MQTT, código: %s", rc)


def on_disconnect(client, userdata, disconnect_flags, rc, properties=None):
    if rc != 0:
        log.warning("Desconectado del broker (rc=%s). Reintentando...", rc)


def on_message(client, userdata, msg):
    topic   = msg.topic
    payload = msg.payload.decode("utf-8", errors="replace").strip()
    ts      = datetime.now(timezone.utc)

    log.debug("MSG  %s  →  %s", topic, payload)

    try:
        data = json.loads(payload)
    except json.JSONDecodeError:
        log.warning("Payload inválido en %s: %s", topic, payload)
        return

    # Mapear topic → campo(s) del buffer
    if topic == "flux/cnc1/temperatura":
        _buffer["temperatura"] = float(data["value"])

    elif topic == "flux/cnc1/humedad":
        _buffer["humedad"] = float(data["value"])

    elif topic == "flux/cnc1/vibracion":
        _buffer["accel_x"] = float(data["accel_x"])
        _buffer["accel_y"] = float(data["accel_y"])
        _buffer["accel_z"] = float(data["accel_z"])

    # Si ya tenemos todos los campos, procesamos
    if _CAMPOS_REQUERIDOS.issubset(_buffer.keys()):
        _procesar_lectura_completa(ts)


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    log.info("=== FLUX CNC — MQTT Bridge iniciando ===")
    log.info("Broker : %s:%s", MQTT_BROKER, MQTT_PORT)
    log.info("InfluxDB: %s  bucket=%s", INFLUX_URL, INFLUX_BUCKET)

    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="flux_bridge")
    client.username_pw_set(MQTT_USER, MQTT_PASSWORD)

    client.on_connect    = on_connect
    client.on_disconnect = on_disconnect
    client.on_message    = on_message

    # Reconexión automática
    client.reconnect_delay_set(min_delay=2, max_delay=30)

    try:
        client.connect(MQTT_BROKER, MQTT_PORT, keepalive=60)
    except Exception as e:
        log.error("No se pudo conectar al broker: %s", e)
        raise

    log.info("Escuchando mensajes MQTT... (Ctrl+C para detener)")
    try:
        client.loop_forever()
    except KeyboardInterrupt:
        log.info("Bridge detenido por el usuario.")
    finally:
        _influx_client.close()
        client.disconnect()


if __name__ == "__main__":
    main()
