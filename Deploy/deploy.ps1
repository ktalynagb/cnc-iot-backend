<#
Deploy script para Azure: crea RG, VNet (public+private), ACI (frontend, backend, db), Application Gateway en public-subnet,
y configura path-based routing: /datos/* -> backend privado.

Uso:
  - Copia .env.example -> .env y completa valores.
  - az login
  - ./deploy.ps1
#>

param(
    [string]$EnvFile = ".\.env",
    [int]$AppGwWaitTimeoutMins = 20
)

function Load-EnvFile($path) {
    if (!(Test-Path $path)) {
        Write-Error "No se encontró $path. Crea .env basado en .env.example"
        exit 1
    }
    Get-Content $path | ForEach-Object {
        if ($_ -match '^\s*#') { return }
        if ($_ -match '^\s*$') { return }
        $parts = $_ -split '=', 2
        if ($parts.Count -eq 2) {
            $k = $parts[0].Trim()
            $v = $parts[1].Trim()
            Set-Item -Path "env:$k" -Value $v
        }
    }
}

# Cargar variables
Load-EnvFile -path $EnvFile

# Validar variables mínimas
$required = @("AZ_SUBSCRIPTION_ID","AZ_LOCATION","RG_NAME","VNET_NAME","PUBLIC_SUBNET_NAME","PRIVATE_SUBNET_NAME","VNET_PREFIX","PUBLIC_SUBNET_PREFIX","PRIVATE_SUBNET_PREFIX","FRONTEND_IMAGE","BACKEND_IMAGE","DB_IMAGE","ACI_FRONTEND_NAME","ACI_BACKEND_NAME","ACI_DB_NAME","DB_NAME","DB_USER","DB_PASSWORD","APPGW_NAME","PUBLIC_IP_NAME")
foreach ($r in $required) {
    if (-not (Test-Path "env:$r")) {
        Write-Error "Falta la variable $r en $EnvFile"
        exit 1
    }
}

# Variables locales (casteo)
$subId = $env:AZ_SUBSCRIPTION_ID
$location = $env:AZ_LOCATION
$rg = $env:RG_NAME
$vnet = $env:VNET_NAME
$pubSubnet = $env:PUBLIC_SUBNET_NAME
$privSubnet = $env:PRIVATE_SUBNET_NAME
$vnetPrefix = $env:VNET_PREFIX
$pubPrefix = $env:PUBLIC_SUBNET_PREFIX
$privPrefix = $env:PRIVATE_SUBNET_PREFIX
$appgw = $env:APPGW_NAME
$publicIpName = $env:PUBLIC_IP_NAME
$frontendName = $env:ACI_FRONTEND_NAME
$backendName = $env:ACI_BACKEND_NAME
$dbName = $env:ACI_DB_NAME
$frontendImage = $env:FRONTEND_IMAGE
$backendImage = $env:BACKEND_IMAGE
$dbImage = $env:DB_IMAGE
$dbUser = $env:DB_USER
$dbPass = $env:DB_PASSWORD
$dbDatabase = $env:DB_NAME
$frontendPort = if ($env:FRONTEND_PORT) { [int]$env:FRONTEND_PORT } else { 80 }
$backendPort = if ($env:BACKEND_PORT) { [int]$env:BACKEND_PORT } else { 8000 }
$dbPort = if ($env:DB_PORT) { [int]$env:DB_PORT } else { 5432 }
$appgwSku = if ($env:APPGW_SKU) { $env:APPGW_SKU } else { "Standard_v2" }
$appgwCapacity = if ($env:APPGW_CAPACITY) { [int]$env:APPGW_CAPACITY } else { 1 }

# Set subscription
Write-Host "Seleccionando suscripción $subId..."
az account set --subscription $subId

# Crear resource group
Write-Host "Creando resource group $rg ..."
az group create --name $rg --location $location | Out-Null

# Crear VNet con subnets
Write-Host "Creando VNet $vnet con subnets $pubSubnet y $privSubnet..."
az network vnet create `
  --resource-group $rg `
  --name $vnet `
  --address-prefix $vnetPrefix `
  --subnet-name $pubSubnet `
  --subnet-prefix $pubPrefix `
  --location $location | Out-Null

# Añadir la segunda subnet (private)
az network vnet subnet create `
  --resource-group $rg `
  --vnet-name $vnet `
  --name $privSubnet `
  --address-prefix $privPrefix | Out-Null

# Obtener IDs de subnets
$pubSubnetId = az network vnet subnet show --resource-group $rg --vnet-name $vnet --name $pubSubnet --query id -o tsv
$privSubnetId = az network vnet subnet show --resource-group $rg --vnet-name $vnet --name $privSubnet --query id -o tsv

Write-Host "public subnet id: $pubSubnetId"
Write-Host "private subnet id: $privSubnetId"

# Crear IP pública para AppGW
Write-Host "Creando IP pública $publicIpName..."
az network public-ip create --resource-group $rg --name $publicIpName --sku Standard --allocation-method Static | Out-Null
$publicIp = az network public-ip show --resource-group $rg --name $publicIpName --query ipAddress -o tsv
Write-Host "Public IP creada: $publicIp"

# Crear Application Gateway en public subnet (sin backend addresses específicos)
Write-Host "Creando Application Gateway ($appgw) en la public-subnet ..."
az network application-gateway create `
  --name $appgw `
  --resource-group $rg `
  --location $location `
  --sku $appgwSku `
  --capacity $appgwCapacity `
  --vnet-name $vnet `
  --subnet $pubSubnet `
  --public-ip-address $publicIpName `
  --frontend-port $frontendPort `
  --http-settings-protocol Http `
  --no-wait

Write-Host "Creación de AppGW iniciada. Esperando a que termine (puede tardar varios minutos)..."

# Esperar a que AppGW quede en provisioningState Succeeded (timeout configurable)
$timeout = (Get-Date).AddMinutes($AppGwWaitTimeoutMins)
while ($true) {
    Start-Sleep -Seconds 10
    $state = az network application-gateway show --resource-group $rg --name $appgw --query "provisioningState" -o tsv 2>$null
    if ($state) {
        Write-Host "AppGW provisioningState: $state"
    } else {
        Write-Host "AppGW aún no disponible (consulta falló), reintentando..."
    }
    if ($state -eq "Succeeded") { break }
    if ((Get-Date) -gt $timeout) {
        Write-Error "Timeout esperado para AppGW (esperado $AppGwWaitTimeoutMins mins). Revisa en el portal."
        exit 1
    }
}

# Desplegar DB container (en private subnet, IP privada)
Write-Host "Desplegando base de datos ($dbImage) como ACI en private subnet..."
az container create `
  --resource-group $rg `
  --name $dbName `
  --image $dbImage `
  --subnet $privSubnetId `
  --ports $dbPort `
  --environment-variables POSTGRES_DB=$dbDatabase POSTGRES_USER=$dbUser POSTGRES_PASSWORD=$dbPass `
  --ip-address Private `
  --restart-policy OnFailure | Out-Null

# Esperar y obtener IP privada del DB
Write-Host "Esperando a que el container DB inicialice..."
Start-Sleep -Seconds 12
$dbInfo = az container show --resource-group $rg --name $dbName -o json | ConvertFrom-Json
$dbPrivateIp = $dbInfo.ipAddress.ip
Write-Host "DB privada: $dbPrivateIp"

# Deploy backend container (en private subnet)
Write-Host "Desplegando backend ($backendImage) en private subnet..."
az container create `
  --resource-group $rg `
  --name $backendName `
  --image $backendImage `
  --subnet $privSubnetId `
  --ports $backendPort `
  --environment-variables DB_HOST=$dbPrivateIp DB_PORT=$dbPort DB_NAME=$dbDatabase DB_USER=$dbUser DB_PASSWORD=$dbPass `
  --ip-address Private `
  --restart-policy OnFailure | Out-Null

Start-Sleep -Seconds 10
$backendInfo = az container show --resource-group $rg --name $backendName -o json | ConvertFrom-Json
$backendPrivateIp = $backendInfo.ipAddress.ip
Write-Host "Backend privada: $backendPrivateIp"

# Deploy frontend container (en private subnet, IP privada) - AppGW expondrá este servicio
Write-Host "Desplegando frontend ($frontendImage) en private subnet..."
az container create `
  --resource-group $rg `
  --name $frontendName `
  --image $frontendImage `
  --subnet $privSubnetId `
  --ports $frontendPort `
  --environment-variables BACKEND_URL="http://${backendPrivateIp}:${backendPort}" `
  --ip-address Private `
  --restart-policy OnFailure | Out-Null

Start-Sleep -Seconds 10
$frontendInfo = az container show --resource-group $rg --name $frontendName -o json | ConvertFrom-Json
$frontendPrivateIp = $frontendInfo.ipAddress.ip
Write-Host "Frontend privada: $frontendPrivateIp"

# -----------------------
# Configurar AppGW path-based routing
# -----------------------

Write-Host "Configurando BackendPool en AppGW apuntando al backend privado..."
# Crear backend pool con la IP privada del backend
az network application-gateway address-pool create `
  --gateway-name $appgw `
  --resource-group $rg `
  --name BackendPool `
  --addresses $backendPrivateIp | Out-Null

Write-Host "Creando BackendHttpSettings..."
az network application-gateway http-settings create `
  --gateway-name $appgw `
  --resource-group $rg `
  --name BackendHttpSettings `
  --port $backendPort `
  --protocol Http `
  --cookie-based-affinity Disabled | Out-Null

# Detectar nombres por defecto creados para frontend pool, http-settings y listener
Write-Host "Detectando recursos por defecto en AppGW (frontend pool, http-settings, listener)..."
$existingPools = az network application-gateway address-pool list --gateway-name $appgw --resource-group $rg -o json | ConvertFrom-Json
$frontendPoolName = $null
if ($existingPools) {
    # Elegir el primer pool que no sea BackendPool (que acabamos de crear)
    foreach ($p in $existingPools) {
        if ($p.name -ne "BackendPool") {
            $frontendPoolName = $p.name
            break
        }
    }
}

$existingHttpSettings = az network application-gateway http-settings list --gateway-name $appgw --resource-group $rg -o json | ConvertFrom-Json
$frontendHttpSettingsName = $null
if ($existingHttpSettings) {
    foreach ($s in $existingHttpSettings) {
        if ($s.name -ne "BackendHttpSettings") {
            $frontendHttpSettingsName = $s.name
            break
        }
    }
}

$existingListeners = az network application-gateway http-listener list --gateway-name $appgw --resource-group $rg -o json | ConvertFrom-Json
$listenerName = $null
if ($existingListeners) {
    $listenerName = $existingListeners[0].name
}

if (-not $frontendPoolName -or -not $frontendHttpSettingsName -or -not $listenerName) {
    Write-Warning "No se pudieron detectar algunos recursos por defecto en AppGW. Listando recursos para depuración..."
    Write-Host "Pools:"
    az network application-gateway address-pool list --gateway-name $appgw --resource-group $rg -o table
    Write-Host "Http settings:"
    az network application-gateway http-settings list --gateway-name $appgw --resource-group $rg -o table
    Write-Host "Listeners:"
    az network application-gateway http-listener list --gateway-name $appgw --resource-group $rg -o table
    Write-Warning "Si no encuentra nombres por defecto, puede que la creación inicial de AppGW haya usado otros nombres; por favor actualiza los nombres manualmente en el script o crea listener y pools explícitamente."
}

Write-Host "frontendPoolName = $frontendPoolName"
Write-Host "frontendHttpSettingsName = $frontendHttpSettingsName"
Write-Host "listenerName = $listenerName"

# Crear UrlPathMap usando frontend como default
Write-Host "Creando UrlPathMap (UrlPathMap) con default -> frontend..."
az network application-gateway url-path-map create `
  --gateway-name $appgw `
  --resource-group $rg `
  --name UrlPathMap `
  --default-address-pool $frontendPoolName `
  --default-http-settings $frontendHttpSettingsName | Out-Null

# Añadir regla path-based para /datos/* apuntando a BackendPool y BackendHttpSettings
Write-Host "Creando regla path-based 'DatosRule' para /datos/* -> BackendPool..."
az network application-gateway url-path-map rule create `
  --gateway-name $appgw `
  --resource-group $rg `
  --name DatosRule `
  --path-map-name UrlPathMap `
  --paths /datos/* `
  --address-pool BackendPool `
  --http-settings BackendHttpSettings | Out-Null

# Asociar la UrlPathMap a un Request Routing Rule (PathBased) usando el listener detectado
# Creamos una regla PathBasedRouting asociada al listener y a la UrlPathMap
$pathRuleName = "PathBasedRule-Datos"
Write-Host "Creando request routing rule ($pathRuleName) que usa listener $listenerName y UrlPathMap..."
az network application-gateway rule create `
  --gateway-name $appgw `
  --resource-group $rg `
  --name $pathRuleName `
  --rule-type PathBasedRouting `
  --http-listener $listenerName `
  --url-path-map UrlPathMap | Out-Null

Write-Host "Configuración path-based completada. Revisa el AppGW en el portal para confirmar reglas y estado."

Write-Host "`nDeploy finalizado (o en proceso). Frontend público en: http://${publicIp}:${frontendPort} (cuando AppGW esté listo)."
Write-Host "El endpoint /datos será en: http://${publicIp}:${frontendPort}/datos (redirigido al backend privado)."
