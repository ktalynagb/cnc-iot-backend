#!/usr/bin/env bash
# provision-front.sh — VM Pública: Mosquitto (INF-2) + Grafana (INF-5)
# =====================================================================
# Ejecutado por az vm run-command invoke como root.
#
# Parámetros posicionales inyectados desde fase4.ps1:
#   $1 = IP privada de vm-iot-back  (InfluxDB)
#   $2 = Token de administrador de InfluxDB
#
# Servicios instalados:
#   - Eclipse Mosquitto 2.x en el puerto 1883 con autenticación usuario/contraseña
#   - Grafana 10.x en el puerto 3000 con datasource InfluxDB pre-configurado
# =====================================================================
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

# ── 1. Instalar Docker y Docker Compose ─────────────────────────────
echo "[1/6] Instalando Docker y Docker Compose..."
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
echo "[2/6] Creando estructura de directorios en ${WORK_DIR}..."
mkdir -p "${WORK_DIR}/mosquitto/config"
mkdir -p "${WORK_DIR}/mosquitto/data"
mkdir -p "${WORK_DIR}/mosquitto/log"
mkdir -p "${WORK_DIR}/grafana/provisioning/datasources"
mkdir -p "${WORK_DIR}/grafana/provisioning/dashboards"

# ── 3. Mosquitto: configuración con autenticación ───────────────────
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

# Generar el archivo de contraseñas usando la imagen oficial de Mosquitto
# (evita instalar mosquitto-clients en el host)
docker run --rm \
    -v "${WORK_DIR}/mosquitto/config:/mosquitto/config" \
    eclipse-mosquitto:2 \
    mosquitto_passwd -b /mosquitto/config/passwd "${MQTT_USER}" "${MQTT_PASS}"

# El archivo puede quedar con permisos estrictos del contenedor; normalizar
chmod 644 "${WORK_DIR}/mosquitto/config/passwd"
echo "  -> Credenciales Mosquitto generadas: usuario=${MQTT_USER}"

# ── 4. Grafana: provisioning de datasource ──────────────────────────
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

# Directorio de dashboards vacío (placeholder para provisioning futuro)
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

# ── 5. docker-compose.yml ───────────────────────────────────────────
echo "[5/6] Creando docker-compose.yml..."

cat > "${WORK_DIR}/docker-compose.yml" << 'COMPOSE_EOF'
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
COMPOSE_EOF

# ── 6. Levantar servicios ────────────────────────────────────────────
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
