#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Deploy script para Azure - Segunda Entrega (bash)
# Arquitectura:
# - VNet con subred pública y privada
# - VM pública: Mosquitto + Grafana
# - VM privada: InfluxDB + Telegraf
# ============================================================

RG_NAME="rg-cnc-iot"
LOCATION="centralus"

VNET_NAME="vnet-iot"
VNET_PREFIX="10.0.0.0/16"
PUBLIC_SUBNET_NAME="snet-public"
PUBLIC_SUBNET_PREFIX="10.0.1.0/24"
PRIVATE_SUBNET_NAME="snet-private"
PRIVATE_SUBNET_PREFIX="10.0.2.0/24"

NSG_PUBLIC_NAME="nsg-public"
NSG_PRIVATE_NAME="nsg-private"

VM_PUBLIC_NAME="vm-iot-front"
VM_PRIVATE_NAME="vm-iot-back"
VM_IMAGE="Ubuntu2204"
VM_SIZE="Standard_D2s_v3"
ADMIN_USER="ubuntu"
DNS_LABEL="cnc-iot-david"

INFLUX_TOKEN="flux-cnc-iot-admin-token-2024"
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "============================================================"
echo " FASE 1: Variables Globales y Grupo de Recursos"
echo "============================================================"

MY_PUBLIC_IP="$(curl -s http://ipinfo.io/ip | tr -d '[:space:]')"
echo "Obteniendo IP publica local..."
echo "  -> IP local detectada: ${MY_PUBLIC_IP}"

echo "Creando Resource Group '${RG_NAME}' en '${LOCATION}'..."
az group create \
  --name "$RG_NAME" \
  --location "$LOCATION" \
  --output none
echo "  -> Resource Group creado."

echo ""
echo "============================================================"
echo " FASE 2: Red Virtual (VNet) y Subredes"
echo "============================================================"

echo "Creando VNet '${VNET_NAME}' (${VNET_PREFIX})..."
az network vnet create \
  --resource-group "$RG_NAME" \
  --name "$VNET_NAME" \
  --address-prefix "$VNET_PREFIX" \
  --location "$LOCATION" \
  --output none
echo "  -> VNet creada."

echo "Creando subred publica '${PUBLIC_SUBNET_NAME}' (${PUBLIC_SUBNET_PREFIX})..."
az network vnet subnet create \
  --resource-group "$RG_NAME" \
  --vnet-name "$VNET_NAME" \
  --name "$PUBLIC_SUBNET_NAME" \
  --address-prefix "$PUBLIC_SUBNET_PREFIX" \
  --output none
echo "  -> Subred publica creada."

echo "Creando subred privada '${PRIVATE_SUBNET_NAME}' (${PRIVATE_SUBNET_PREFIX})..."
az network vnet subnet create \
  --resource-group "$RG_NAME" \
  --vnet-name "$VNET_NAME" \
  --name "$PRIVATE_SUBNET_NAME" \
  --address-prefix "$PRIVATE_SUBNET_PREFIX" \
  --output none
echo "  -> Subred privada creada."

echo ""
echo "============================================================"
echo " FASE 3: Seguridad (NSG)"
echo "============================================================"

echo "Creando NSG publico '${NSG_PUBLIC_NAME}'..."
az network nsg create \
  --resource-group "$RG_NAME" \
  --name "$NSG_PUBLIC_NAME" \
  --location "$LOCATION" \
  --output none
echo "  -> NSG publico creado."

echo "Agregando regla SSH (puerto 22, solo desde IP del operador: ${MY_PUBLIC_IP})..."
az network nsg rule create \
  --resource-group "$RG_NAME" \
  --nsg-name "$NSG_PUBLIC_NAME" \
  --name "Allow-SSH" \
  --priority 100 \
  --protocol Tcp \
  --direction Inbound \
  --source-address-prefixes "${MY_PUBLIC_IP}/32" \
  --source-port-ranges "*" \
  --destination-address-prefixes "*" \
  --destination-port-ranges 22 \
  --access Allow \
  --output none

echo "Agregando regla MQTT (puerto 1883)..."
az network nsg rule create \
  --resource-group "$RG_NAME" \
  --nsg-name "$NSG_PUBLIC_NAME" \
  --name "Allow-MQTT" \
  --priority 110 \
  --protocol Tcp \
  --direction Inbound \
  --source-address-prefixes "*" \
  --source-port-ranges "*" \
  --destination-address-prefixes "*" \
  --destination-port-ranges 1883 \
  --access Allow \
  --output none

echo "Agregando regla Grafana (puerto 3000)..."
az network nsg rule create \
  --resource-group "$RG_NAME" \
  --nsg-name "$NSG_PUBLIC_NAME" \
  --name "Allow-Grafana" \
  --priority 120 \
  --protocol Tcp \
  --direction Inbound \
  --source-address-prefixes "*" \
  --source-port-ranges "*" \
  --destination-address-prefixes "*" \
  --destination-port-ranges 3000 \
  --access Allow \
  --output none

echo "Agregando regla Backend FastAPI (puerto 8000)..."
az network nsg rule create \
  --resource-group "$RG_NAME" \
  --nsg-name "$NSG_PUBLIC_NAME" \
  --name "Allow-Backend" \
  --priority 130 \
  --protocol Tcp \
  --direction Inbound \
  --source-address-prefixes "*" \
  --source-port-ranges "*" \
  --destination-address-prefixes "*" \
  --destination-port-ranges 8000 \
  --access Allow \
  --output none
echo "  -> Reglas del NSG publico configuradas."

echo "Asociando NSG publico a la subred '${PUBLIC_SUBNET_NAME}'..."
az network vnet subnet update \
  --resource-group "$RG_NAME" \
  --vnet-name "$VNET_NAME" \
  --name "$PUBLIC_SUBNET_NAME" \
  --network-security-group "$NSG_PUBLIC_NAME" \
  --output none
echo "  -> NSG publico asociado."

echo "Creando NSG privado '${NSG_PRIVATE_NAME}' (aislamiento total de internet)..."
az network nsg create \
  --resource-group "$RG_NAME" \
  --name "$NSG_PRIVATE_NAME" \
  --location "$LOCATION" \
  --output none
echo "  -> NSG privado creado."

echo "Agregando regla InfluxDB (puerto 8086) solo desde subred publica..."
az network nsg rule create \
  --resource-group "$RG_NAME" \
  --nsg-name "$NSG_PRIVATE_NAME" \
  --name "Allow-InfluxDB-FromPublicSubnet" \
  --priority 100 \
  --protocol Tcp \
  --direction Inbound \
  --source-address-prefixes "$PUBLIC_SUBNET_PREFIX" \
  --source-port-ranges "*" \
  --destination-address-prefixes "*" \
  --destination-port-ranges 8086 \
  --access Allow \
  --output none
echo "  -> Regla InfluxDB configurada."

echo "Asociando NSG privado a la subred '${PRIVATE_SUBNET_NAME}'..."
az network vnet subnet update \
  --resource-group "$RG_NAME" \
  --vnet-name "$VNET_NAME" \
  --name "$PRIVATE_SUBNET_NAME" \
  --network-security-group "$NSG_PRIVATE_NAME" \
  --output none
echo "  -> NSG privado asociado."

echo ""
echo "============================================================"
echo " FASE 4: Creacion de VMs (sin cloud-init)"
echo "============================================================"

echo "Desplegando VM publica '${VM_PUBLIC_NAME}' en subred '${PUBLIC_SUBNET_NAME}'..."
az vm create \
  --resource-group "$RG_NAME" \
  --name "$VM_PUBLIC_NAME" \
  --image "$VM_IMAGE" \
  --size "$VM_SIZE" \
  --admin-username "$ADMIN_USER" \
  --generate-ssh-keys \
  --vnet-name "$VNET_NAME" \
  --subnet "$PUBLIC_SUBNET_NAME" \
  --nsg "$NSG_PUBLIC_NAME" \
  --public-ip-sku Standard \
  --public-ip-address-dns-name "$DNS_LABEL" \
  --output none
echo "  -> VM publica '${VM_PUBLIC_NAME}' creada."

echo "Desplegando VM privada '${VM_PRIVATE_NAME}' en subred '${PRIVATE_SUBNET_NAME}' (sin IP publica)..."
az vm create \
  --resource-group "$RG_NAME" \
  --name "$VM_PRIVATE_NAME" \
  --image "$VM_IMAGE" \
  --size "$VM_SIZE" \
  --admin-username "$ADMIN_USER" \
  --generate-ssh-keys \
  --vnet-name "$VNET_NAME" \
  --subnet "$PRIVATE_SUBNET_NAME" \
  --nsg "$NSG_PRIVATE_NAME" \
  --public-ip-address "" \
  --output none
echo "  -> VM privada '${VM_PRIVATE_NAME}' creada."

echo ""
echo "Obteniendo IPs de las VMs para provisioning cruzado..."
VM_PUBLIC_IP="$(az vm show --resource-group "$RG_NAME" --name "$VM_PUBLIC_NAME" --show-details --query publicIps --output tsv | tr -d '[:space:]')"
VM_FRONT_PRIVATE_IP="$(az vm show --resource-group "$RG_NAME" --name "$VM_PUBLIC_NAME" --show-details --query privateIps --output tsv | tr -d '[:space:]')"
VM_BACK_PRIVATE_IP="$(az vm show --resource-group "$RG_NAME" --name "$VM_PRIVATE_NAME" --show-details --query privateIps --output tsv | tr -d '[:space:]')"

echo "  -> IP publica  de ${VM_PUBLIC_NAME}  : ${VM_PUBLIC_IP}"
echo "  -> IP privada  de ${VM_PUBLIC_NAME}  : ${VM_FRONT_PRIVATE_IP}"
echo "  -> IP privada  de ${VM_PRIVATE_NAME} : ${VM_BACK_PRIVATE_IP}"

echo ""
echo "============================================================"
echo " FASE 4b: Aprovisionamiento via az vm run-command invoke"
echo "============================================================"

echo "Aprovisionando '${VM_PUBLIC_NAME}' (Mosquitto + Grafana)..."
az vm run-command invoke \
  --resource-group "$RG_NAME" \
  --name "$VM_PUBLIC_NAME" \
  --command-id RunShellScript \
  --scripts "@${SCRIPTS_DIR}/provision-front.sh" \
  --parameters "$VM_BACK_PRIVATE_IP" "$INFLUX_TOKEN" \
  --output json

echo "  -> Aprovisionamiento de '${VM_PUBLIC_NAME}' completado."

echo "Aplicando correcciones de ownership remotas en '${VM_PUBLIC_NAME}' (seguro e idempotente)..."
az vm run-command invoke \
  --resource-group "$RG_NAME" \
  --name "$VM_PUBLIC_NAME" \
  --command-id RunShellScript \
  --scripts "chown -R ubuntu:ubuntu /home/ubuntu/cnc-iot-backend || true; chown -R ubuntu:ubuntu /opt/iot/front || true; chmod 0700 /opt/iot/front/mosquitto/config/passwd || true" \
  --output none || echo "Advertencia: no se pudo aplicar chown remoto (ignored)"

echo "Aprovisionando '${VM_PRIVATE_NAME}' (InfluxDB + Telegraf)..."
az vm run-command invoke \
  --resource-group "$RG_NAME" \
  --name "$VM_PRIVATE_NAME" \
  --command-id RunShellScript \
  --scripts "@${SCRIPTS_DIR}/provision-back.sh" \
  --parameters "$VM_FRONT_PRIVATE_IP" \
  --output json

echo "  -> Aprovisionamiento de '${VM_PRIVATE_NAME}' completado."

echo ""
echo "============================================================"
echo " DESPLIEGUE FINALIZADO EXITOSAMENTE"
echo "============================================================"
echo "  VM Publica  (${VM_PUBLIC_NAME}):"
echo "    IP Publica  : ${VM_PUBLIC_IP}"
echo "    IP Privada  : ${VM_FRONT_PRIVATE_IP}"
echo "    DNS         : ${DNS_LABEL}.${LOCATION}.cloudapp.azure.com"
echo "    SSH         : ssh ${ADMIN_USER}@${VM_PUBLIC_IP}"
echo "    MQTT        : ${VM_PUBLIC_IP}:1883  (flux_user / flux_pass)"
echo "    Grafana     : http://${VM_PUBLIC_IP}:3000  (admin / admin123)"
echo "    Backend     : http://${VM_PUBLIC_IP}:8000"
echo "    CSV DL      : http://${VM_PUBLIC_IP}:8000/datos/descargar/"
echo "    API Docs    : http://${VM_PUBLIC_IP}:8000/docs"
echo ""
echo "  VM Privada  (${VM_PRIVATE_NAME}):"
echo "    IP Privada  : ${VM_BACK_PRIVATE_IP}"
echo "    InfluxDB    : http://${VM_BACK_PRIVATE_IP}:8086  (accesible solo desde ${PUBLIC_SUBNET_PREFIX})"
echo "    Org/Bucket  : flux / flux_cnc"
echo ""
echo "  [INF-4] Token InfluxDB:"
echo "    INFLUX_TOKEN  = ${INFLUX_TOKEN}"
echo "    INFLUX_URL    = http://${VM_BACK_PRIVATE_IP}:8086"
echo "    INFLUX_ORG    = flux"
echo "    INFLUX_BUCKET = flux_cnc"
echo ""
echo "  Flujo de red:"
echo "    ESP32       --> Mosquitto  (${VM_PUBLIC_IP}:1883)"
echo "    Telegraf    --> Mosquitto  (${VM_FRONT_PRIVATE_IP}:1883)  [VNet interna]"
echo "    Telegraf    --> InfluxDB   (influxdb:8086)              [Docker interno]"
echo "    Grafana     --> InfluxDB   (${VM_BACK_PRIVATE_IP}:8086)  [VNet interna]"
echo "============================================================"