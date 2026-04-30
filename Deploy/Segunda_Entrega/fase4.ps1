<#
fase4.ps1 — Segunda Entrega (Fase 4 reescrita)
=================================================
NUEVO ENFOQUE: Sin cloud-init. Abandona --custom-data para evitar el bug de
Base64 de Windows PowerShell ("number of data characters cannot be 1 more
than a multiple of 4").

Las VMs se crean "limpias" y luego se aprovisionan post-creación mediante
  az vm run-command invoke  (agente de Azure, sin SSH, sin Bastion).

Servicios desplegados via Docker:
  vm-iot-front (publica) : Eclipse Mosquitto 2.x (1883) + Grafana 10.x (3000)
  vm-iot-back  (privada) : InfluxDB 2.x (8086) + Telegraf (bridge MQTT->InfluxDB)

Scripts de bash referenciados (en el mismo directorio que este .ps1):
  provision-front.sh  — instala y configura vm-iot-front
  provision-back.sh   — instala y configura vm-iot-back
#>

# =====================================================================
# --- Variables Globales ---
# =====================================================================

$RG_NAME              = "rg-cnc-iot"
$LOCATION             = "centralus"

$VNET_NAME            = "vnet-iot"
$PUBLIC_SUBNET_NAME   = "snet-public"
$PUBLIC_SUBNET_PREFIX = "10.0.1.0/24"
$PRIVATE_SUBNET_NAME  = "snet-private"
$PRIVATE_SUBNET_PREFIX= "10.0.2.0/24"

$NSG_PUBLIC_NAME      = "nsg-public"
$NSG_PRIVATE_NAME     = "nsg-private"

$VM_PUBLIC_NAME       = "vm-iot-front"
$VM_PRIVATE_NAME      = "vm-iot-back"
$VM_IMAGE             = "Ubuntu2204"
$VM_SIZE              = "Standard_B1s"
$ADMIN_USER           = "ubuntu"
$DNS_LABEL            = "cnc-iot-david"

# [INF-4] Token predecible de InfluxDB — compartir con equipo de Backend
$INFLUX_TOKEN         = "flux-cnc-iot-admin-token-2024"

# Directorio de los scripts de bash (mismo directorio que este .ps1)
$SCRIPTS_DIR          = $PSScriptRoot

# =====================================================================
# --- FASE 4: Creacion de VMs (limpias, sin cloud-init) ---
# =====================================================================

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " FASE 4: Creacion de VMs (sin cloud-init)" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# --- VM Publica ---
Write-Host "Desplegando VM publica '$VM_PUBLIC_NAME' en subred '$PUBLIC_SUBNET_NAME'..." -ForegroundColor Yellow
az vm create `
    --resource-group             $RG_NAME `
    --name                       $VM_PUBLIC_NAME `
    --image                      $VM_IMAGE `
    --size                       $VM_SIZE `
    --admin-username             $ADMIN_USER `
    --generate-ssh-keys `
    --vnet-name                  $VNET_NAME `
    --subnet                     $PUBLIC_SUBNET_NAME `
    --nsg                        $NSG_PUBLIC_NAME `
    --public-ip-sku              Standard `
    --public-ip-address-dns-name $DNS_LABEL `
    --output                     none
Write-Host "  -> VM publica '$VM_PUBLIC_NAME' creada (limpia, sin cloud-init)." -ForegroundColor Green

# --- VM Privada (sin IP publica) ---
Write-Host "Desplegando VM privada '$VM_PRIVATE_NAME' en subred '$PRIVATE_SUBNET_NAME' (sin IP publica)..." -ForegroundColor Yellow
az vm create `
    --resource-group    $RG_NAME `
    --name              $VM_PRIVATE_NAME `
    --image             $VM_IMAGE `
    --size              $VM_SIZE `
    --admin-username    $ADMIN_USER `
    --generate-ssh-keys `
    --vnet-name         $VNET_NAME `
    --subnet            $PRIVATE_SUBNET_NAME `
    --nsg               $NSG_PRIVATE_NAME `
    --public-ip-address '""' `
    --output            none
Write-Host "  -> VM privada '$VM_PRIVATE_NAME' creada (sin IP publica)." -ForegroundColor Green

# =====================================================================
# --- Obtener IPs para el provisioning cruzado ---
# =====================================================================

Write-Host ""
Write-Host "Obteniendo IPs de las VMs para provisioning cruzado..." -ForegroundColor Yellow

$VM_PUBLIC_IP = (az vm show `
    --resource-group $RG_NAME `
    --name           $VM_PUBLIC_NAME `
    --show-details `
    --query          "publicIps" `
    --output         tsv).Trim()

$VM_FRONT_PRIVATE_IP = (az vm show `
    --resource-group $RG_NAME `
    --name           $VM_PUBLIC_NAME `
    --show-details `
    --query          "privateIps" `
    --output         tsv).Trim()

$VM_BACK_PRIVATE_IP = (az vm show `
    --resource-group $RG_NAME `
    --name           $VM_PRIVATE_NAME `
    --show-details `
    --query          "privateIps" `
    --output         tsv).Trim()

Write-Host "  -> IP publica  de $VM_PUBLIC_NAME  : $VM_PUBLIC_IP" -ForegroundColor Green
Write-Host "  -> IP privada  de $VM_PUBLIC_NAME  : $VM_FRONT_PRIVATE_IP" -ForegroundColor Green
Write-Host "  -> IP privada  de $VM_PRIVATE_NAME : $VM_BACK_PRIVATE_IP" -ForegroundColor Green

# =====================================================================
# --- FASE 4b: Aprovisionamiento via az vm run-command invoke ---
# Evita cloud-init y SSH; el agente de Azure ejecuta los scripts bash
# directamente dentro de cada VM con privilegios de root.
# =====================================================================

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " FASE 4b: Aprovisionamiento via az vm run-command invoke" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# --- Aprovisionar VM Publica: Mosquitto (INF-2) + Grafana (INF-5) ---
Write-Host ""
Write-Host "Aprovisionando '$VM_PUBLIC_NAME' (Mosquitto + Grafana)..." -ForegroundColor Yellow
Write-Host "  Script    : provision-front.sh" -ForegroundColor Gray
Write-Host "  Parametros: VM_BACK_IP=$VM_BACK_PRIVATE_IP" -ForegroundColor Gray

$frontResult = az vm run-command invoke `
    --resource-group $RG_NAME `
    --name           $VM_PUBLIC_NAME `
    --command-id     RunShellScript `
    --scripts        "@$SCRIPTS_DIR\provision-front.sh" `
    --parameters     $VM_BACK_PRIVATE_IP $INFLUX_TOKEN `
    --output         json | ConvertFrom-Json

foreach ($item in $frontResult.value) {
    if ($item.message) { Write-Host $item.message }
}
Write-Host "  -> Aprovisionamiento de '$VM_PUBLIC_NAME' completado." -ForegroundColor Green

# --- Aprovisionar VM Privada: InfluxDB (INF-3/INF-4) + Telegraf (Bridge) ---
Write-Host ""
Write-Host "Aprovisionando '$VM_PRIVATE_NAME' (InfluxDB + Telegraf)..." -ForegroundColor Yellow
Write-Host "  Script    : provision-back.sh" -ForegroundColor Gray
Write-Host "  Parametros: VM_FRONT_IP=$VM_FRONT_PRIVATE_IP" -ForegroundColor Gray

$backResult = az vm run-command invoke `
    --resource-group $RG_NAME `
    --name           $VM_PRIVATE_NAME `
    --command-id     RunShellScript `
    --scripts        "@$SCRIPTS_DIR\provision-back.sh" `
    --parameters     $VM_FRONT_PRIVATE_IP `
    --output         json | ConvertFrom-Json

foreach ($item in $backResult.value) {
    if ($item.message) { Write-Host $item.message }
}
Write-Host "  -> Aprovisionamiento de '$VM_PRIVATE_NAME' completado." -ForegroundColor Green

# =====================================================================
# --- FASE 5: Resumen de Conectividad ---
# =====================================================================

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host " DESPLIEGUE FINALIZADO EXITOSAMENTE" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  VM Publica  ($VM_PUBLIC_NAME):" -ForegroundColor Green
Write-Host "    IP Publica  : $VM_PUBLIC_IP" -ForegroundColor Green
Write-Host "    IP Privada  : $VM_FRONT_PRIVATE_IP" -ForegroundColor Green
Write-Host "    DNS         : $DNS_LABEL.$LOCATION.cloudapp.azure.com" -ForegroundColor Green
Write-Host "    SSH         : ssh $ADMIN_USER@$VM_PUBLIC_IP" -ForegroundColor Green
Write-Host "    MQTT        : $VM_PUBLIC_IP:1883  (flux_user / flux_pass)" -ForegroundColor Green
Write-Host "    Grafana     : http://$VM_PUBLIC_IP:3000  (admin / admin123)" -ForegroundColor Green
Write-Host ""
Write-Host "  VM Privada  ($VM_PRIVATE_NAME):" -ForegroundColor Green
Write-Host "    IP Privada  : $VM_BACK_PRIVATE_IP" -ForegroundColor Green
Write-Host "    InfluxDB    : http://$VM_BACK_PRIVATE_IP:8086  (accesible solo desde $PUBLIC_SUBNET_PREFIX)" -ForegroundColor Green
Write-Host "    Org/Bucket  : flux / flux_cnc" -ForegroundColor Green
Write-Host ""
Write-Host "  [INF-4] Token InfluxDB — compartir con equipo de Backend:" -ForegroundColor Yellow
Write-Host "    INFLUX_TOKEN  = $INFLUX_TOKEN" -ForegroundColor Yellow
Write-Host "    INFLUX_URL    = http://$VM_BACK_PRIVATE_IP:8086" -ForegroundColor Yellow
Write-Host "    INFLUX_ORG    = flux" -ForegroundColor Yellow
Write-Host "    INFLUX_BUCKET = flux_cnc" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Flujo de red:" -ForegroundColor Cyan
Write-Host "    ESP32       --> Mosquitto  ($VM_PUBLIC_IP:1883)" -ForegroundColor Cyan
Write-Host "    Telegraf    --> Mosquitto  ($VM_FRONT_PRIVATE_IP:1883)  [VNet interna]" -ForegroundColor Cyan
Write-Host "    Telegraf    --> InfluxDB   (influxdb:8086)              [Docker interno]" -ForegroundColor Cyan
Write-Host "    Grafana     --> InfluxDB   ($VM_BACK_PRIVATE_IP:8086)  [VNet interna]" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Green
