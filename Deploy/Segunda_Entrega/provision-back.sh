#!/usr/bin/env bash
# provision-back.sh — VM Privada: InfluxDB 2.x (INF-3/INF-4) + Telegraf (Bridge)
# =================================================================================
# Ejecutado por az vm run-command invoke como root.
#
# Parámetros posicionales inyectados desde fase4.ps1:
#   $1 = IP privada de vm-iot-front  (broker Mosquitto)
#
# Servicios instalados:
#   - InfluxDB 2.x en el puerto 8086, inicializado con org=flux, bucket=flux_cnc
#     y token predefinido (INF-3 / INF-4)
#   - Telegraf: suscrito a Mosquitto en vm-iot-front, escribe en InfluxDB local
#     (Bridge MQTT → InfluxDB)
# =================================================================================
set -euo pipefail

VM_FRONT_IP="${1:?ERROR: falta el argumento 1 (IP privada de vm-iot-front)}"

# ── Credenciales e identificadores ──────────────────────────────────────────────
# [INF-4] Token predecible para compartir con el equipo de Backend.
# Puede cambiarse post-despliegue desde la UI de InfluxDB o via CLI.
INFLUX_TOKEN="flux-cnc-iot-admin-token-2024"
INFLUX_ORG="flux"
INFLUX_BUCKET="flux_cnc"
INFLUX_USER="admin"
INFLUX_PASS="admin12345"

MQTT_USER="flux_user"
MQTT_PASS="flux_pass"

WORK_DIR="/opt/iot/back"

echo "================================================================"
echo " [BACK] Provisionando vm-iot-back (InfluxDB + Telegraf)"
echo " vm-iot-front IP (Mosquitto): ${VM_FRONT_IP}"
echo "================================================================"

# ── 1. Instalar Docker y Docker Compose ─────────────────────────────
echo "[1/5] Instalando Docker y Docker Compose..."
apt-get update -qq
apt-get install -y --no-install-recommends docker.io docker-compose
systemctl enable docker
systemctl start docker
usermod -aG docker ubuntu

# Esperar a que el daemon de Docker esté listo
until docker info > /dev/null 2>&1; do
    echo "  Esperando que Docker arranque..."
    sleep 2
done
echo "  -> Docker listo."

# ── 2. Crear estructura de directorios ──────────────────────────────
echo "[2/5] Creando estructura de directorios en ${WORK_DIR}..."
mkdir -p "${WORK_DIR}/influxdb/config"
mkdir -p "${WORK_DIR}/telegraf"

# ── 3. Telegraf: configuración MQTT Consumer → InfluxDB v2 ──────────
echo "[3/5] Creando configuración de Telegraf..."
# Suscripción a los topics del ESP32 en el broker Mosquitto de vm-iot-front.
# Escritura en InfluxDB local (via nombre de servicio Docker 'influxdb').

cat > "${WORK_DIR}/telegraf/telegraf.conf" << EOF
[global_tags]
  env = "azure-iot"

[agent]
  interval         = "10s"
  round_interval   = true
  metric_batch_size  = 1000
  metric_buffer_limit = 10000
  collection_jitter  = "0s"
  flush_interval   = "10s"
  flush_jitter     = "0s"
  precision        = ""
  hostname         = "vm-iot-back"
  omit_hostname    = false

# ── INPUT: MQTT Consumer ──────────────────────────────────────────────────────
# Se suscribe al broker Mosquitto de vm-iot-front usando la IP interna de la VNet.
# Topicos esperados del ESP32 (publicados por mqtt_bridge.py o directamente):
#   flux/cnc1/temperatura  → {"value": 28.5}
#   flux/cnc1/humedad      → {"value": 60.2}
#   flux/cnc1/vibracion    → {"accel_x": 0.12, "accel_y": -0.03, "accel_z": 9.81}
[[inputs.mqtt_consumer]]
  servers             = ["tcp://${VM_FRONT_IP}:1883"]
  topics              = [
    "flux/cnc1/temperatura",
    "flux/cnc1/humedad",
    "flux/cnc1/vibracion"
  ]
  username            = "${MQTT_USER}"
  password            = "${MQTT_PASS}"
  qos                 = 1
  connection_timeout  = "30s"
  persistent_session  = false
  client_id           = "telegraf-bridge"
  data_format         = "json"
  json_time_key       = ""
  json_time_format    = ""
  tag_keys            = []

# ── OUTPUT: InfluxDB v2 (local, mismo host Docker) ───────────────────────────
[[outputs.influxdb_v2]]
  urls         = ["http://influxdb:8086"]
  token        = "${INFLUX_TOKEN}"
  organization = "${INFLUX_ORG}"
  bucket       = "${INFLUX_BUCKET}"
  timeout      = "5s"
EOF

echo "  -> telegraf.conf creado (broker: tcp://${VM_FRONT_IP}:1883)."

# ── 4. docker-compose.yml ───────────────────────────────────────────
echo "[4/5] Creando docker-compose.yml..."

cat > "${WORK_DIR}/docker-compose.yml" << COMPOSE_EOF
version: "3.8"

services:
  # ── InfluxDB 2.x ────────────────────────────────────────────────────────────
  # Se auto-inicializa con DOCKER_INFLUXDB_INIT_MODE=setup creando:
  #   org=${INFLUX_ORG}  bucket=${INFLUX_BUCKET}  token=${INFLUX_TOKEN}
  influxdb:
    image: influxdb:2.7
    container_name: influxdb
    restart: unless-stopped
    ports:
      - "8086:8086"
    environment:
      - DOCKER_INFLUXDB_INIT_MODE=setup
      - DOCKER_INFLUXDB_INIT_USERNAME=${INFLUX_USER}
      - DOCKER_INFLUXDB_INIT_PASSWORD=${INFLUX_PASS}
      - DOCKER_INFLUXDB_INIT_ORG=${INFLUX_ORG}
      - DOCKER_INFLUXDB_INIT_BUCKET=${INFLUX_BUCKET}
      - DOCKER_INFLUXDB_INIT_ADMIN_TOKEN=${INFLUX_TOKEN}
    volumes:
      - influxdb_data:/var/lib/influxdb2
      - ./influxdb/config:/etc/influxdb2

  # ── Telegraf (Bridge MQTT → InfluxDB) ────────────────────────────────────────
  # Se suscribe a Mosquitto en vm-iot-front y escribe en InfluxDB local.
  telegraf:
    image: telegraf:1.30
    container_name: telegraf
    restart: unless-stopped
    depends_on:
      - influxdb
    volumes:
      - ./telegraf/telegraf.conf:/etc/telegraf/telegraf.conf:ro

volumes:
  influxdb_data:
COMPOSE_EOF

echo "  -> docker-compose.yml creado."

# ── 5. Levantar servicios ────────────────────────────────────────────
echo "[5/5] Levantando servicios con docker-compose..."
cd "${WORK_DIR}"
docker-compose up -d

# Dar tiempo a InfluxDB para su inicialización inicial antes de reportar
sleep 10

echo ""
echo "================================================================"
echo " [BACK] PROVISIONAMIENTO COMPLETADO"
echo "================================================================"
echo "  InfluxDB  : http://0.0.0.0:8086"
echo "    Org     : ${INFLUX_ORG}"
echo "    Bucket  : ${INFLUX_BUCKET}"
echo "    Usuario : ${INFLUX_USER}"
echo "    Password: ${INFLUX_PASS}"
echo ""
echo "  Telegraf  : suscrito a tcp://${VM_FRONT_IP}:1883"
echo "    Topics  : flux/cnc1/temperatura, flux/cnc1/humedad, flux/cnc1/vibracion"
echo "    Output  : http://influxdb:8086  bucket=${INFLUX_BUCKET}"
echo ""
echo "  =============================================================="
echo "  [INF-4] TOKEN INFLUXDB — compartir con equipo de Backend:"
echo "  INFLUX_TOKEN=${INFLUX_TOKEN}"
echo "  INFLUX_URL=http://$(hostname -I | awk '{print $1}'):8086"
echo "  INFLUX_ORG=${INFLUX_ORG}"
echo "  INFLUX_BUCKET=${INFLUX_BUCKET}"
echo "  =============================================================="
echo "================================================================"
