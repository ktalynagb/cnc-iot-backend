#!/usr/bin/env bash
set -euo pipefail

VM_BACK_IP="${1:?ERROR: falta el argumento 1 (IP privada de vm-iot-back)}"
INFLUX_TOKEN="${2:-flux-cnc-iot-admin-token-2024}"

INFLUX_ORG="flux"
INFLUX_BUCKET="flux_cnc"
MQTT_USER="flux_user"
MQTT_PASS="flux_pass"
WORK_DIR="/opt/iot/front"

# Repo/backend
REPO_DIR="/home/ubuntu/cnc-iot-backend"
BACKEND_DIR="${REPO_DIR}/backend"
UV_BIN="/usr/local/bin/uv"
REPO_URL="https://github.com/ktalynagb/cnc-iot-backend.git"
BRANCH="master"

echo "================================================================"
echo " [FRONT] Provisionando vm-iot-front (Mosquitto + Grafana + Backend)"
echo " vm-iot-back IP : ${VM_BACK_IP}"
echo "================================================================"

echo "[1/7] Instalando Docker y Docker Compose..."
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends docker.io docker-compose curl ca-certificates git || true
systemctl enable docker || true
systemctl start docker || true

until docker info > /dev/null 2>&1; do
  echo "  Esperando que Docker arranque..."
  sleep 2
done
echo "  -> Docker listo."

echo "[2/7] Preparando estructura de directorios (idempotente)..."
mkdir -p "${WORK_DIR}/mosquitto/config" "${WORK_DIR}/mosquitto/data" "${WORK_DIR}/mosquitto/log"
mkdir -p "${WORK_DIR}/grafana/provisioning/datasources" "${WORK_DIR}/grafana/provisioning/dashboards" "${WORK_DIR}/grafana/dashboards"
# Ensure ownership matches Grafana container user (uid 472) for dashboards dir
chown -R 472:472 "${WORK_DIR}/grafana/dashboards" || true

# Install test utilities (idempotent) to allow validation during provisioning
echo "[2b/7] Instalando utilidades de test (mosquitto-clients, pip)..."
apt-get update -qq || true
apt-get install -y --no-install-recommends mosquitto-clients python3-pip || true
# Install paho for ubuntu user to enable python tests without touching system site-packages
sudo -u ubuntu /bin/bash -lc "python3 -m pip install --user paho-mqtt" || true

echo "[3/7] Configurando Mosquitto (archivo de configuración)..."
cat > "${WORK_DIR}/mosquitto/config/mosquitto.conf" << 'EOF'
listener 1883
allow_anonymous false
password_file /mosquitto/config/passwd
persistence true
persistence_location /mosquitto/data/
log_dest stdout
log_dest file /mosquitto/log/mosquitto.log
EOF

# Ensure passwd exists (create using the image's mosquitto_passwd) and logfile file exists.
echo "[3b/7] Asegurando passwd y logfile (idempotente)..."
# create empty passwd file if missing (the docker run below will fill it)
touch "${WORK_DIR}/mosquitto/config/passwd" || true
touch "${WORK_DIR}/mosquitto/log/mosquitto.log" || true

# Create passwd with mosquitto_passwd via the image (works even if image needs pulling)
docker run --rm -v "${WORK_DIR}/mosquitto/config:/mosquitto/config" eclipse-mosquitto:2 \
  sh -c "mosquitto_passwd -b /mosquitto/config/passwd '${MQTT_USER}' '${MQTT_PASS}'" || {
    echo "WARNING: mosquitto_passwd command failed (continuando para aplicar ownership/perm)."
}

# Determine internal mosquitto UID:GID and apply ownership so the process inside container can read files.
MOS_UID=$(docker run --rm eclipse-mosquitto:2 id -u mosquitto)
MOS_GID=$(docker run --rm eclipse-mosquitto:2 id -g mosquitto)
echo "  -> mosquitto uid:gid = ${MOS_UID}:${MOS_GID}"

# chown/chmod mounted tree so mosquitto inside container can access passwd and logfile
chown -R "${MOS_UID}:${MOS_GID}" "${WORK_DIR}/mosquitto" || true
find "${WORK_DIR}/mosquitto" -type d -exec chmod 0750 {} \; || true
[ -f "${WORK_DIR}/mosquitto/config/passwd" ] && chmod 0600 "${WORK_DIR}/mosquitto/config/passwd" || true
[ -f "${WORK_DIR}/mosquitto/log/mosquitto.log" ] && chmod 0600 "${WORK_DIR}/mosquitto/log/mosquitto.log" || true
echo "  -> Credenciales y logs asegurados (uid:gid ${MOS_UID}:${MOS_GID})."

echo "[4/7] Configurando Grafana datasource..."
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

echo "[5/7] Creando docker-compose.yml (Mosquitto + Grafana)..."
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
      - ./grafana/dashboards:/var/lib/grafana/dashboards
      - grafana_data:/var/lib/grafana

volumes:
  grafana_data:
EOF

echo "[6/7] Levantando servicios..."
cd "${WORK_DIR}"
# Use docker-compose if present, otherwise try 'docker compose'
if command -v docker-compose >/dev/null 2>&1; then
  docker-compose up -d
else
  docker compose up -d
fi

# Health wait for mosquitto
echo "[6b/7] Esperando a que mosquitto arranque (timeout 60s)..."
START=0
TIMEOUT=60
SUCCESS=0
while [ $START -lt $TIMEOUT ]; do
  if docker logs mosquitto 2>&1 | grep -q "mosquitto version .* running"; then
    SUCCESS=1
    break
  fi
  sleep 1
  START=$((START+1))
done

if [ "$SUCCESS" -ne 1 ]; then
  echo "ERROR: mosquitto no arrancó correctamente. Últimos logs:"
  docker logs mosquitto --tail 200 || true
  exit 1
fi
echo "  -> mosquitto arrancado correctamente."

echo "[7/7] Instalando y activando backend FastAPI con UV..."
# Clone/update repo as ubuntu to avoid root-owned files
if [ ! -d "${REPO_DIR}" ]; then
  sudo -u ubuntu git clone --branch "${BRANCH}" "${REPO_URL}" "${REPO_DIR}"
else
  sudo -u ubuntu bash -lc "cd '${REPO_DIR}' && git fetch --all && git reset --hard origin/${BRANCH}"
fi

# Ensure ownership
chown -R ubuntu:ubuntu "${REPO_DIR}" || true
chmod -R u+rwX "${REPO_DIR}" || true

cd "${BACKEND_DIR}"

if [ ! -f ".env" ]; then
  cp .env.example .env
fi

# Ajustar variables necesarias para la VM pública
grep -q '^INFLUX_URL=' .env && sed -i "s|^INFLUX_URL=.*|INFLUX_URL=http://${VM_BACK_IP}:8086|" .env || echo "INFLUX_URL=http://${VM_BACK_IP}:8086" >> .env
grep -q '^INFLUX_TOKEN=' .env && sed -i "s|^INFLUX_TOKEN=.*|INFLUX_TOKEN=${INFLUX_TOKEN}|" .env || echo "INFLUX_TOKEN=${INFLUX_TOKEN}" >> .env
grep -q '^INFLUX_ORG=' .env && sed -i "s|^INFLUX_ORG=.*|INFLUX_ORG=${INFLUX_ORG}|" .env || echo "INFLUX_ORG=${INFLUX_ORG}" >> .env
grep -q '^INFLUX_BUCKET=' .env && sed -i "s|^INFLUX_BUCKET=.*|INFLUX_BUCKET=${INFLUX_BUCKET}|" .env || echo "INFLUX_BUCKET=${INFLUX_BUCKET}" >> .env
grep -q '^MQTT_BROKER=' .env && sed -i "s|^MQTT_BROKER=.*|MQTT_BROKER=localhost|" .env || echo "MQTT_BROKER=localhost" >> .env

# Remove old DB_ vars that pydantic may reject
sed -i '/^DB_/d' "${BACKEND_DIR}/.env" || true

# Run uv sync as ubuntu; retry once if it fails
if [ -x "${UV_BIN}" ]; then
  if ! sudo -u ubuntu /bin/bash -lc "cd ${BACKEND_DIR} && ${UV_BIN} sync"; then
    echo "  !! uv sync falló; reintentando una vez..."
    sleep 2
    sudo -u ubuntu /bin/bash -lc "cd ${BACKEND_DIR} && ${UV_BIN} sync" || echo "  !! uv sync falló definitivamente; revisar manualmente."
  fi
else
  echo "  -> UV no encontrado en ${UV_BIN}; instala uv en el host antes de sync."
fi

# Prepare data dir
mkdir -p "${BACKEND_DIR}/data"
touch "${BACKEND_DIR}/data/lecturas.csv"
chown -R ubuntu:ubuntu "${BACKEND_DIR}/data"
chmod 664 "${BACKEND_DIR}/data/lecturas.csv"

# Install and enable services
cp "${REPO_DIR}/bridge/mqtt_bridge.service" /etc/systemd/system/mqtt_bridge.service
systemctl daemon-reload
systemctl enable mqtt_bridge || true
systemctl restart mqtt_bridge || true

cat > /etc/systemd/system/cnc_backend.service << 'EOF'
[Unit]
Description=FLUX CNC -- Backend FastAPI (GET /datos/ / GET /datos/descargar/)
After=network.target mqtt_bridge.service
Wants=mqtt_bridge.service

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/ubuntu/cnc-iot-backend/backend
EnvironmentFile=/home/ubuntu/cnc-iot-backend/backend/.env
ExecStart=/usr/local/bin/uv run uvicorn app.main:app --host 0.0.0.0 --port 8000
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable cnc_backend || true
systemctl restart cnc_backend || true

echo "  -> Backend FastAPI activado."

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
echo "  Backend   : http://0.0.0.0:8000"
echo "    GET /datos/"
echo "    GET /datos/descargar/"
echo "================================================================"