#!/usr/bin/env bash
set -euo pipefail

VM_BACK_IP="${1:?ERROR: falta el argumento 1 (IP privada de vm-iot-back)}"
INFLUX_TOKEN="${2:-flux-cnc-iot-admin-token-2024}"

INFLUX_ORG="flux"
INFLUX_BUCKET="flux_cnc"
MQTT_USER="flux_user"
MQTT_PASS="flux_pass"
WORK_DIR="/opt/iot/front"

echo "================================================================"
echo " [FRONT] Provisionando vm-iot-front (Mosquitto + Grafana)"
echo " vm-iot-back IP : ${VM_BACK_IP}"
echo "================================================================"

echo "[1/6] Instalando Docker y Docker Compose..."
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends docker.io docker-compose
systemctl enable docker
systemctl start docker

until docker info > /dev/null 2>&1; do
  echo "  Esperando que Docker arranque..."
  sleep 2
done
echo "  -> Docker listo."

echo "[2/6] Preparando estructura de directorios..."
mkdir -p "${WORK_DIR}/mosquitto/config"
mkdir -p "${WORK_DIR}/mosquitto/data"
mkdir -p "${WORK_DIR}/mosquitto/log"
mkdir -p "${WORK_DIR}/grafana/provisioning/datasources"
mkdir -p "${WORK_DIR}/grafana/provisioning/dashboards"

echo "[3/6] Configurando Mosquitto..."
cat > "${WORK_DIR}/mosquitto/config/mosquitto.conf" << 'EOF'
listener 1883
allow_anonymous false
password_file /mosquitto/config/passwd
persistence true
persistence_location /mosquitto/data/
log_dest stdout
log_dest file /mosquitto/log/mosquitto.log
EOF

rm -f "${WORK_DIR}/mosquitto/config/passwd"
touch "${WORK_DIR}/mosquitto/config/passwd"

docker run --rm \
  -v "${WORK_DIR}/mosquitto/config:/mosquitto/config" \
  eclipse-mosquitto:2 \
  sh -c "mosquitto_passwd -b /mosquitto/config/passwd '${MQTT_USER}' '${MQTT_PASS}'"

chmod 644 "${WORK_DIR}/mosquitto/config/passwd"
echo "  -> Credenciales Mosquitto generadas: usuario=${MQTT_USER}"

echo "[4/6] Configurando Grafana datasource..."
cat > "${WORK_DIR}/grafana/provisioning/datasources/influxdb.yaml" << EOF
apiVersion: 1

datasources:
  - name: InfluxDB-CNC
    type: influxdb
    access: proxy
    url: http://${VM_BACK_IP}:8086
    jsonData:
      version: Flux
      organization: ${INFLUX_ORG}
      defaultBucket: ${INFLUX_BUCKET}
    secureJsonData:
      token: ${INFLUX_TOKEN}
    isDefault: true
    editable: true
EOF

cat > "${WORK_DIR}/grafana/provisioning/dashboards/dashboards.yaml" << 'EOF'
apiVersion: 1

providers:
  - name: CNC-Dashboards
    folder: CNC IoT
    type: file
    disableDeletion: false
    options:
      path: /var/lib/grafana/dashboards
EOF

echo "[5/6] Creando docker-compose.yml..."
cat > "${WORK_DIR}/docker-compose.yml" << 'EOF'
version: "3.8"

services:
  mosquitto:
    image: eclipse-mosquitto:2
    container_name: mosquitto
    restart: unless-stopped
    ports:
      - "1883:1883"
    volumes:
      - ./mosquitto/config:/mosquitto/config:ro
      - ./mosquitto/data:/mosquitto/data
      - ./mosquitto/log:/mosquitto/log

  grafana:
    image: grafana/grafana:10.4.0
    container_name: grafana
    restart: unless-stopped
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=admin123
    volumes:
      - ./grafana/provisioning:/etc/grafana/provisioning
      - grafana_data:/var/lib/grafana

volumes:
  grafana_data:
EOF

echo "[6/7] Levantando servicios Docker..."
cd "${WORK_DIR}"
docker-compose up -d

echo "[7/7] Instalando bridge MQTT como servicio systemd (UV)..."

# Instalar dependencias base
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends curl ca-certificates git

# Instalar UV system-wide
curl -LsSf https://astral.sh/uv/install.sh | UV_INSTALL_DIR=/usr/local/bin sh
echo "  -> UV instalado en /usr/local/bin/uv"

# Clonar repositorio si no existe
REPO_DIR="/home/ubuntu/cnc-iot-backend"
if [ ! -d "${REPO_DIR}/.git" ]; then
    git clone https://github.com/ktalynagb/cnc-iot-backend.git "${REPO_DIR}"
    chown -R ubuntu:ubuntu "${REPO_DIR}"
    echo "  -> Repositorio clonado en ${REPO_DIR}"
else
    cd "${REPO_DIR}"
    git pull --ff-only || true
    chown -R ubuntu:ubuntu "${REPO_DIR}"
    echo "  -> Repositorio actualizado en ${REPO_DIR}"
fi

# Crear directorio de datos para el CSV
mkdir -p "${REPO_DIR}/backend/data"
chown -R ubuntu:ubuntu "${REPO_DIR}/backend/data"

# Crear .env del backend con los valores de esta VM
cat > "${REPO_DIR}/backend/.env" << ENV_EOF
# Servidor FastAPI
APP_HOST=0.0.0.0
APP_PORT=8000

# CSV
CSV_PATH=/home/ubuntu/cnc-iot-backend/backend/data/lecturas.csv

# Alertas (umbrales)
TEMP_MIN=15.0
TEMP_MAX=45.0
HUM_MIN=20.0
HUM_MAX=80.0
ACCEL_MAX=2.0

# InfluxDB (vm-iot-back)
INFLUX_URL=http://${VM_BACK_IP}:8086
INFLUX_TOKEN=${INFLUX_TOKEN}
INFLUX_ORG=${INFLUX_ORG}
INFLUX_BUCKET=${INFLUX_BUCKET}

# MQTT (Mosquitto local en esta VM)
MQTT_BROKER=localhost
MQTT_PORT=1883
MQTT_USER=${MQTT_USER}
MQTT_PASSWORD=${MQTT_PASS}
ENV_EOF

chown ubuntu:ubuntu "${REPO_DIR}/backend/.env"
echo "  -> backend/.env generado con IP de InfluxDB: ${VM_BACK_IP}"

# Instalar y activar el servicio systemd
cp "${REPO_DIR}/bridge/mqtt_bridge.service" /etc/systemd/system/mqtt_bridge.service
systemctl daemon-reload
systemctl enable mqtt_bridge
systemctl start mqtt_bridge
echo "  -> Servicio mqtt_bridge instalado, habilitado e iniciado."

echo ""
echo "================================================================"
echo " [FRONT] PROVISIONAMIENTO COMPLETADO"
echo "================================================================"
echo "  Mosquitto : 0.0.0.0:1883"
echo "    Usuario : ${MQTT_USER}"
echo "    Password: ${MQTT_PASS}"
echo "  Grafana   : http://0.0.0.0:3000"
echo "    Usuario : admin"
echo "    Password: admin123"
echo "    Datasource: InfluxDB @ http://${VM_BACK_IP}:8086"
echo "      Org   : ${INFLUX_ORG}"
echo "      Bucket: ${INFLUX_BUCKET}"
echo "  Bridge    : mqtt_bridge.service (UV)"
echo "    Repo    : ${REPO_DIR}"
echo "    Logs    : journalctl -u mqtt_bridge -f"
echo "    CSV     : ${REPO_DIR}/backend/data/lecturas.csv"
echo "================================================================"