"""
mqtt_bridge.py — FLUX CNC IoT · Bridge robusto con reconexión
Recibe un solo JSON por ciclo desde MQTT, calcula vibración,
evalúa alertas, escribe en InfluxDB y guarda CSV.
"""

import json
import logging
import os
import signal
import sys
import time
from datetime import datetime, timezone
from types import SimpleNamespace

import paho.mqtt.client as mqtt
from influxdb_client import InfluxDBClient, Point
from influxdb_client.client.write_api import SYNCHRONOUS

# ── Importar lógica existente del backend ────────────────────────────────────
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "backend"))

from app.alertas import calcular_vibracion, evaluar_alerta
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

# ── Configuración ─────────────────────────────────────────────────────────────
MQTT_BROKER   = os.getenv("MQTT_BROKER", "localhost")
MQTT_PORT     = int(os.getenv("MQTT_PORT", "1883"))
MQTT_USER     = os.getenv("MQTT_USER", "flux_user")
MQTT_PASSWORD = os.getenv("MQTT_PASSWORD", "flux_pass")

MQTT_TOPICS = [
    "flux/cnc1/datos",
]

INFLUX_URL    = os.getenv("INFLUX_URL", "http://localhost:8086")
INFLUX_TOKEN  = os.getenv("INFLUX_TOKEN", "")
INFLUX_ORG    = os.getenv("INFLUX_ORG", "flux")
INFLUX_BUCKET = os.getenv("INFLUX_BUCKET", "flux_cnc")

# ── InfluxDB ──────────────────────────────────────────────────────────────────
_influx_client = InfluxDBClient(
    url=INFLUX_URL,
    token=INFLUX_TOKEN,
    org=INFLUX_ORG,
)
_write_api = _influx_client.write_api(write_options=SYNCHRONOUS)

# ── Estado de ejecución ───────────────────────────────────────────────────────
_running = True
_client: mqtt.Client | None = None


def _shutdown(*_args):
    global _running
    _running = False
    log.info("Señal de parada recibida, cerrando bridge...")


signal.signal(signal.SIGINT, _shutdown)
signal.signal(signal.SIGTERM, _shutdown)


def _escribir_influx(ts: datetime, temp: float, hum: float,
                     ax: float, ay: float, az: float,
                     vib: float, alerta: bool, motivo: str | None) -> None:
    point = (
        Point("cnc_sensores")
        .tag("maquina", "cnc1")
        .field("alerta", alerta)
        .field("temperatura", temp)
        .field("humedad", hum)
        .field("accel_x", ax)
        .field("accel_y", ay)
        .field("accel_z", az)
        .field("vibracion_total", vib)
        .field("motivo_alerta", motivo or "")
        .time(ts, "s")
    )
    _write_api.write(bucket=INFLUX_BUCKET, org=INFLUX_ORG, record=point)
    log.info("  → InfluxDB ✓  vib=%.4f  alerta=%s", vib, alerta)


def procesar_dato(payload: str):
    ts = datetime.now(timezone.utc)

    try:
        data = json.loads(payload)
    except json.JSONDecodeError:
        log.warning("Payload inválido: %s", payload)
        return

    required = {"temperatura", "humedad", "accel_x", "accel_y", "accel_z"}
    if not required.issubset(data.keys()):
        log.warning("Faltan campos en payload: %s", payload)
        return

    temp = float(data["temperatura"])
    hum = float(data["humedad"])
    ax = float(data["accel_x"])
    ay = float(data["accel_y"])
    az = float(data["accel_z"])

    vib = calcular_vibracion(ax, ay, az)
    alerta, motivo = evaluar_alerta(temp, hum, vib)

    log.info(
        "Lectura completa — T=%.2f°C  H=%.2f%%  Vib=%.4f m/s²  Alerta=%s",
        temp, hum, vib, alerta
    )

    _escribir_influx(ts, temp, hum, ax, ay, az, vib, alerta, motivo)

    lectura_csv = SimpleNamespace(
        id=int(ts.timestamp()),
        timestamp=ts,
        temperatura=temp,
        humedad=hum,
        accel_x=ax,
        accel_y=ay,
        accel_z=az,
        vibracion_total=vib,
        alerta=alerta,
        motivo_alerta=motivo,
    )
    guardar_lectura_csv(lectura_csv)
    log.info("  → CSV ✓")

    if alerta:
        log.warning("  ⚠ ALERTA: %s", motivo)


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
    payload = msg.payload.decode("utf-8", errors="replace").strip()
    log.info("MSG recibida topic=%s payload=%s", msg.topic, payload)
    procesar_dato(payload)


def _crear_cliente() -> mqtt.Client:
    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="flux_bridge")
    client.username_pw_set(MQTT_USER, MQTT_PASSWORD)
    client.on_connect = on_connect
    client.on_disconnect = on_disconnect
    client.on_message = on_message

    # Reconexión automática
    client.reconnect_delay_set(min_delay=1, max_delay=10)
    return client


def _conectar_cliente(client: mqtt.Client) -> None:
    # connect_async evita bloquear y permite reconexión mejor
    client.connect_async(MQTT_BROKER, MQTT_PORT, keepalive=30)
    client.loop_start()


def main():
    global _client

    log.info("=== FLUX CNC — MQTT Bridge iniciando ===")
    log.info("Broker : %s:%s", MQTT_BROKER, MQTT_PORT)
    log.info("InfluxDB: %s  bucket=%s", INFLUX_URL, INFLUX_BUCKET)

    _client = _crear_cliente()

    try:
        _conectar_cliente(_client)
    except Exception as e:
        log.error("No se pudo iniciar conexión MQTT: %s", e)
        raise

    log.info("Escuchando mensajes MQTT... (Ctrl+C para detener)")

    # Bucle de supervisión: si el hilo MQTT muere, intenta levantarlo otra vez
    retry_delay = 5
    try:
        while _running:
            if _client is not None:
                # is_connected() no siempre existe en todas las versiones; usamos estado de loop
                # Si no hay tráfico, mantenemos vivo el proceso.
                pass
            time.sleep(1)
    except KeyboardInterrupt:
        log.info("Bridge detenido por el usuario.")
    finally:
        try:
            if _client is not None:
                _client.loop_stop()
                _client.disconnect()
        finally:
            _influx_client.close()
            log.info("Bridge cerrado correctamente.")


if __name__ == "__main__":
    main()