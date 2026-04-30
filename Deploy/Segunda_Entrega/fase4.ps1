<#
Deploy script para Azure - Segunda Entrega (Migracion IoT desde AWS):
- Arquitectura de dos niveles: Subred Publica y Subred Privada.
- VM Publica (vm-iot-front): acceso SSH/MQTT/Grafana con IP publica y DNS.
- VM Privada (vm-iot-back): InfluxDB aislado, sin IP publica.
- Ambas VMs aprovisionadas con Docker via cloud-init.
- Seguridad por NSGs diferenciados por nivel.
#>

# =====================================================================
# --- FASE 1: Variables Globales y Grupo de Recursos ---
# =====================================================================

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " FASE 1: Variables Globales y Grupo de Recursos" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# --- Variables Globales ---
$RG_NAME       = "rg-cnc-iot"
$LOCATION      = "centralus"

# Redes
$VNET_NAME            = "vnet-iot"
$VNET_PREFIX          = "10.0.0.0/16"
$PUBLIC_SUBNET_NAME   = "snet-public"
$PUBLIC_SUBNET_PREFIX = "10.0.1.0/24"
$PRIVATE_SUBNET_NAME  = "snet-private"
$PRIVATE_SUBNET_PREFIX= "10.0.2.0/24"

# Seguridad
$NSG_PUBLIC_NAME  = "nsg-public"
$NSG_PRIVATE_NAME = "nsg-private"

# Maquinas Virtuales
$VM_PUBLIC_NAME   = "vm-iot-front"
$VM_PRIVATE_NAME  = "vm-iot-back"
$VM_IMAGE         = "Ubuntu2204"
$VM_SIZE          = "Standard_B1s"
$ADMIN_USER       = "ubuntu"
$DNS_LABEL        = "cnc-iot-david"

# IP local del operador (para restriccion SSH)
Write-Host "Obteniendo IP publica local..." -ForegroundColor Yellow
$MY_PUBLIC_IP = (Invoke-RestMethod http://ipinfo.io/ip).Trim()
Write-Host "  -> IP local detectada: $MY_PUBLIC_IP" -ForegroundColor White


# =====================================================================
# --- FASE 4: Maquinas Virtuales e Instalacion de Docker ---
# =====================================================================

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " FASE 4: Maquinas Virtuales e Instalacion de Docker" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# -----------------------------------------------------------------------
# FIX: Codificamos el cloud-init directamente en memoria (en Base64),
# usando UTF-8 SIN BOM y normalizando los saltos de linea a LF.
# Esto evita por completo los problemas de CRLF y BOM de Windows que
# corrompian la cadena base64 que Azure CLI intentaba generar.
# -----------------------------------------------------------------------

Write-Host "Generando y codificando cloud-init en Base64 (UTF-8 sin BOM, LF)..." -ForegroundColor Yellow

# Definimos el contenido con here-string (PowerShell agrega CRLF)
$cloudInitRaw = @"
#cloud-config
package_update: true
package_upgrade: true
packages:
  - docker.io
  - docker-compose
runcmd:
  - systemctl enable docker
  - systemctl start docker
  - usermod -aG docker ubuntu
"@

# 1. Normalizamos CRLF -> LF para que Linux lo interprete correctamente
$cloudInitLF = $cloudInitRaw -replace "`r`n", "`n"

# 2. Convertimos a bytes con UTF-8 SIN BOM
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$cloudInitBytes = $utf8NoBom.GetBytes($cloudInitLF)

# 3. Codificamos a Base64
$cloudInitB64 = [Convert]::ToBase64String($cloudInitBytes)

Write-Host "  -> cloud-init codificado correctamente (longitud base64: $($cloudInitB64.Length))." -ForegroundColor Green

# --- VM Publica ---
Write-Host "Desplegando VM publica '$VM_PUBLIC_NAME' en subred '$PUBLIC_SUBNET_NAME'..." -ForegroundColor Yellow
az vm create `
    --resource-group        $RG_NAME `
    --name                  $VM_PUBLIC_NAME `
    --image                 $VM_IMAGE `
    --size                  $VM_SIZE `
    --admin-username        $ADMIN_USER `
    --generate-ssh-keys `
    --vnet-name             $VNET_NAME `
    --subnet                $PUBLIC_SUBNET_NAME `
    --nsg                   $NSG_PUBLIC_NAME `
    --public-ip-sku         Standard `
    --public-ip-address-dns-name $DNS_LABEL `
    --custom-data           $cloudInitB64 `
    --output                none
Write-Host "  -> VM publica '$VM_PUBLIC_NAME' desplegada." -ForegroundColor Green

# --- VM Privada ---
Write-Host "Desplegando VM privada '$VM_PRIVATE_NAME' en subred '$PRIVATE_SUBNET_NAME' (sin IP publica)..." -ForegroundColor Yellow
az vm create `
    --resource-group        $RG_NAME `
    --name                  $VM_PRIVATE_NAME `
    --image                 $VM_IMAGE `
    --size                  $VM_SIZE `
    --admin-username        $ADMIN_USER `
    --generate-ssh-keys `
    --vnet-name             $VNET_NAME `
    --subnet                $PRIVATE_SUBNET_NAME `
    --nsg                   $NSG_PRIVATE_NAME `
    --public-ip-address     "" `
    --custom-data           $cloudInitB64 `
    --output                none
Write-Host "  -> VM privada '$VM_PRIVATE_NAME' desplegada (sin IP publica)." -ForegroundColor Green

# =====================================================================
# --- FASE 5: Resumen de Conectividad ---
# =====================================================================

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " FASE 5: Resumen de Conectividad" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

Write-Host "Obteniendo IP publica de '$VM_PUBLIC_NAME'..." -ForegroundColor Yellow
$VM_PUBLIC_IP = az vm show `
    --resource-group   $RG_NAME `
    --name             $VM_PUBLIC_NAME `
    --show-details `
    --query            "publicIps" `
    --output           tsv

Write-Host "Obteniendo IP privada de '$VM_PRIVATE_NAME'..." -ForegroundColor Yellow
$VM_PRIVATE_IP = az vm show `
    --resource-group   $RG_NAME `
    --name             $VM_PRIVATE_NAME `
    --show-details `
    --query            "privateIps" `
    --output           tsv

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host " DESPLIEGUE FINALIZADO EXITOSAMENTE" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  VM Publica  ($VM_PUBLIC_NAME):" -ForegroundColor Green
Write-Host "    IP Publica : $VM_PUBLIC_IP" -ForegroundColor Green
Write-Host "    DNS        : $DNS_LABEL.$LOCATION.cloudapp.azure.com" -ForegroundColor Green
Write-Host "    SSH        : ssh $ADMIN_USER@$VM_PUBLIC_IP" -ForegroundColor Green
Write-Host "    MQTT       : $VM_PUBLIC_IP:1883" -ForegroundColor Green
Write-Host "    Grafana    : http://$VM_PUBLIC_IP:3000" -ForegroundColor Green
Write-Host ""
Write-Host "  VM Privada  ($VM_PRIVATE_NAME):" -ForegroundColor Green
Write-Host "    IP Privada : $VM_PRIVATE_IP" -ForegroundColor Green
Write-Host "    InfluxDB   : $VM_PRIVATE_IP:8086 (accesible solo desde $PUBLIC_SUBNET_PREFIX)" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
