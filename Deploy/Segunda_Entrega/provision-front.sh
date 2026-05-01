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
apt-get install -y --no-install-recommends docker.io docker-compose
systemctl enable docker
systemctl start docker

until docker info > /dev/null 2>&1; do
    echo "  Esperando que Docker arranque..."
    sleep 2
done
echo "  -> Docker listo."

echo "[2/6] Creando estructura de directorios en ${WORK_DIR}..."
mkdir -p "${WORK_DIR}/mosquitto/config"
mkdir -p "${WORK_DIR}/mosquitto/data"
mkdir -p "${WORK_DIR}/mosquitto/log"
mkdir -p "${WORK_DIR}/grafana/provisioning/datasources"
mkdir -p "${WORK_DIR}/grafana/provisioning/dashboards"

echo "[3/6] Configurando Mosquitto con autenticación usuario/contraseña..."
cat > "${WORK_DIR}/mosquitto/config/mosquitto.conf" << 'EOF'
listener 1883
allow_anonymous false
password_file /mosquitto/config/passwd
persistence true
persistence_location /mosquitto/data/
log_dest stdout
log_dest file /mosquitto/log/mosquitto.log
EOF

touch "${WORK_DIR}/mosquitto/config/passwd"

docker run --rm \
  -v "${WORK_DIR}/mosquitto/config:/mosquitto/config" \
  eclipse-mosquitto:2 \
  sh -c "mosquitto_passwd -b /mosquitto/config/passwd '${MQTT_USER}' '${MQTT_PASS}'"

chmod 644 "${WORK_DIR}/mosquitto/config/passwd"
echo "  -> Credenciales Mosquitto generadas: usuario=${MQTT_USER}"

echo "[4/6] Creando provisioning de datasource de Grafana → InfluxDB @ ${VM_BACK_IP}:8086..."
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

echo "  -> Datasource apuntando a http://${VM_BACK_IP}:8086 (org=${INFLUX_ORG}, bucket=${INFLUX_BUCKET})."

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

echo "[6/6] Levantando servicios con docker-compose..."
cd "${WORK_DIR}"
docker-compose up -d

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
echo "================================================================"