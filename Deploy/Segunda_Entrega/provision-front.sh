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
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends docker.io docker-compose curl ca-certificates git
systemctl enable docker
systemctl start docker

until docker info > /dev/null 2>&1; do
  echo "  Esperando que Docker arranque..."
  sleep 2
done
echo "  -> Docker listo."

echo "[2/7] Preparando estructura de directorios..."
mkdir -p "${WORK_DIR}/mosquitto/config"
mkdir -p "${WORK_DIR}/mosquitto/data"
mkdir -p "${WORK_DIR}/mosquitto/log"
mkdir -p "${WORK_DIR}/grafana/provisioning/datasources"
mkdir -p "${WORK_DIR}/grafana/provisioning/dashboards"
mkdir -p "${WORK_DIR}/grafana/dashboards"
# Ensure ownership matches Grafana container user (uid 472)
chown -R 472:472 "${WORK_DIR}/grafana/dashboards" || true

# ---------------------------
# Garantizar propiedad/permisos
# ---------------------------
# Asegurar que WORK_DIR es accesible por el usuario ubuntu (idempotente).
chown -R ubuntu:ubuntu "${WORK_DIR}" || true
chmod -R u+rwX "${WORK_DIR}" || true

echo "[3/7] Configurando Mosquitto..."
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

# Permisos estrictos para evitar la advertencia de mosquitto (y por seguridad)
chmod 0700 "${WORK_DIR}/mosquitto/config/passwd" || true
chown ubuntu:ubuntu "${WORK_DIR}/mosquitto/config/passwd" || true
echo "  -> Credenciales Mosquitto generadas: usuario=${MQTT_USER}"

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

echo "[5/7] Creando docker-compose.yml..."
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
docker-compose up -d

echo "[7/7] Instalando y activando backend FastAPI con UV..."
# --- Clonar / actualizar el repo COMO usuario 'ubuntu' para evitar problemas de permisos
if [ ! -d "${REPO_DIR}" ]; then
  echo "[FRONT] Clonando repo como ubuntu..."
  sudo -u ubuntu git clone --branch "${BRANCH}" "${REPO_URL}" "${REPO_DIR}"
else
  echo "[FRONT] Actualizando repo como ubuntu..."
  sudo -u ubuntu bash -lc "cd '${REPO_DIR}' && git fetch --all && git reset --hard origin/${BRANCH}"
fi

# Asegurar propiedad y permisos correctos (idempotente)
chown -R ubuntu:ubuntu "${REPO_DIR}" || true
chmod -R u+rwX "${REPO_DIR}" || true

if [ ! -x "${UV_BIN}" ]; then
  echo "  -> UV no existe en ${UV_BIN}; instalando..."
  curl -LsSf https://astral.sh/uv/install.sh | UV_INSTALL_DIR=/usr/local/bin sh
fi

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

# Eliminar variables PostgreSQL heredadas de entregas anteriores (DB_HOST, DB_PORT, etc.)
# que pydantic v2 rechaza con ValidationError si Settings no las declara.
sed -i '/^DB_/d' "${BACKEND_DIR}/.env"

# Generar .venv en backend como usuario ubuntu (crea cache de UV en /home/ubuntu/.local/share/uv)
echo "  -> Ejecutando uv sync como ubuntu..."
# Ejecutar dentro del backend como ubuntu para crear .venv con el propietario correcto
sudo -u ubuntu /bin/bash -lc "cd '${BACKEND_DIR}' && ${UV_BIN} sync" || {
  echo "  !! uv sync falló, reintentando una vez..."
  sleep 2
  sudo -u ubuntu /bin/bash -lc "cd '${BACKEND_DIR}' && ${UV_BIN} sync" || {
    echo "  !! uv sync falló definitivamente. Comprueba /home/ubuntu/cnc-iot-backend/backend/.venv y permisos."
  }
}
# Asegurar propiedad final por si algo quedó de root
chown -R ubuntu:ubuntu "${BACKEND_DIR}" || true

# Preparar directorio de datos y fichero CSV
mkdir -p "${BACKEND_DIR}/data"
touch "${BACKEND_DIR}/data/lecturas.csv"
chown -R ubuntu:ubuntu "${BACKEND_DIR}/data"
chmod 664 "${BACKEND_DIR}/data/lecturas.csv"

# Instalar y activar mqtt_bridge.service
chown -R ubuntu:ubuntu "${WORK_DIR}" "${REPO_DIR}" || true
cp "${REPO_DIR}/bridge/mqtt_bridge.service" /etc/systemd/system/mqtt_bridge.service
systemctl daemon-reload
systemctl enable mqtt_bridge
systemctl restart mqtt_bridge

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
systemctl enable cnc_backend
systemctl restart cnc_backend

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