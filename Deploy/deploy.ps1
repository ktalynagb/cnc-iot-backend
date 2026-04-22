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
$required = @(
    "AZ_SUBSCRIPTION_ID","AZ_LOCATION","RG_NAME","VNET_NAME",
    "PUBLIC_SUBNET_NAME","PRIVATE_SUBNET_NAME","VNET_PREFIX",
    "PUBLIC_SUBNET_PREFIX","PRIVATE_SUBNET_PREFIX",
    "FRONTEND_IMAGE","BACKEND_IMAGE","DB_IMAGE",
    "ACI_FRONTEND_NAME","ACI_BACKEND_NAME","ACI_DB_NAME",
    "DB_NAME","DB_USER","DB_PASSWORD","APPGW_NAME","PUBLIC_IP_NAME"
)
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
# Configurar AppGW path-based routing (robusto)
# -----------------------

# Nombres de recursos AppGW que usaremos explícitamente
$frontendIpNameCfg = "AppGwFrontendIP"
$frontendPortNameCfg = "AppGwFrontendPort"
$frontendListenerName = "AppGwFrontListener"
$frontendPoolNameExplicit = "FrontendPoolExplicit"
$pathMapName = "UrlPathMap"
$datosRuleName = "DatosRule"
$requestRoutingRuleName = "RequestRule-PathBased"
$priorityValue = 100

Write-Host "Verificando si AppGW $appgw existe..."
$appgwExists = az network application-gateway show --resource-group $rg --name $appgw -o json 2>$null | ConvertFrom-Json
if (-not $appgwExists) {
    Write-Error "App Gateway $appgw no encontrado. Revisa logs anteriores."
    exit 1
}

# Si existe alguna regla por defecto sin priority, eliminarla para evitar errores de plantilla
Write-Host "Comprobando reglas existentes en AppGW..."
$allRules = az network application-gateway rule list --gateway-name $appgw --resource-group $rg -o json | ConvertFrom-Json
if ($allRules) {
    foreach ($r in $allRules) {
        # r.priority puede ser $null si no existe, o 0/valor
        if (-not $r.priority) {
            Write-Warning "Regla $($r.name) sin priority detectada. La eliminaré para reemplazar con reglas con priority."
            az network application-gateway rule delete --gateway-name $appgw --resource-group $rg --name $r.name | Out-Null
        }
    }
}

# Crear Frontend IP config (apunta a la Public IP creada anteriormente)
Write-Host "Creando Frontend IP config ($frontendIpNameCfg)..."
az network application-gateway frontend-ip create `
  --gateway-name $appgw `
  --resource-group $rg `
  --name $frontendIpNameCfg `
  --public-ip-address $publicIpName | Out-Null

# Crear frontend port
Write-Host "Creando Frontend Port ($frontendPortNameCfg) en puerto $frontendPort..."
az network application-gateway frontend-port create `
  --gateway-name $appgw `
  --resource-group $rg `
  --name $frontendPortNameCfg `
  --port $frontendPort | Out-Null

# Crear frontend listener
Write-Host "Creando HTTP Listener ($frontendListenerName)..."
az network application-gateway http-listener create `
  --gateway-name $appgw `
  --resource-group $rg `
  --name $frontendListenerName `
  --frontend-port $frontendPortNameCfg `
  --frontend-ip $frontendIpNameCfg `
  --protocol Http | Out-Null

# Crear frontend address pool apuntando al frontend privado (si no existe)
Write-Host "Creando Frontend address pool ($frontendPoolNameExplicit) apuntando a $frontendPrivateIp..."
$existsFrontendPool = az network application-gateway address-pool show --gateway-name $appgw --resource-group $rg --name $frontendPoolNameExplicit -o json 2>$null
if (-not $existsFrontendPool) {
    az network application-gateway address-pool create `
      --gateway-name $appgw `
      --resource-group $rg `
      --name $frontendPoolNameExplicit `
      --addresses $frontendPrivateIp | Out-Null
} else {
    # Si ya existe, actualizar direcciones (sobrescribir)
    az network application-gateway address-pool update `
      --gateway-name $appgw `
      --resource-group $rg `
      --name $frontendPoolNameExplicit `
      --add backendAddresses "{""ipAddress"":""$frontendPrivateIp""}" | Out-Null
}

# Crear http-settings para frontend
$frontendHttpSettings = "FrontendHttpSettings"
$existsFrontendHttpSettings = az network application-gateway http-settings show --gateway-name $appgw --resource-group $rg --name $frontendHttpSettings -o json 2>$null
if (-not $existsFrontendHttpSettings) {
    Write-Host "Creando Frontend Http Settings ($frontendHttpSettings)..."
    az network application-gateway http-settings create `
      --gateway-name $appgw `
      --resource-group $rg `
      --name $frontendHttpSettings `
      --port $frontendPort `
      --protocol Http `
      --cookie-based-affinity Disabled | Out-Null
}

# Crear BackendPool apuntando a backendPrivateIp (si no existe)
Write-Host "Verificando/creando BackendPool..."
$existsBackendPool = az network application-gateway address-pool show --gateway-name $appgw --resource-group $rg --name BackendPool -o json 2>$null
if (-not $existsBackendPool) {
    az network application-gateway address-pool create `
      --gateway-name $appgw `
      --resource-group $rg `
      --name BackendPool `
      --addresses $backendPrivateIp | Out-Null
} else {
    az network application-gateway address-pool update `
      --gateway-name $appgw `
      --resource-group $rg `
      --name BackendPool `
      --add backendAddresses "{""ipAddress"":""$backendPrivateIp""}" | Out-Null
}

# Crear BackendHttpSettings (si no existe)
$existsBackendSettings = az network application-gateway http-settings show --gateway-name $appgw --resource-group $rg --name BackendHttpSettings -o json 2>$null
if (-not $existsBackendSettings) {
    Write-Host "Creando Backend Http Settings..."
    az network application-gateway http-settings create `
      --gateway-name $appgw `
      --resource-group $rg `
      --name BackendHttpSettings `
      --port $backendPort `
      --protocol Http `
      --cookie-based-affinity Disabled | Out-Null
}

# Crear UrlPathMap con default -> frontendPoolExplicit
Write-Host "Creando UrlPathMap ($pathMapName) con default -> $frontendPoolNameExplicit..."
$existsPathMap = az network application-gateway url-path-map show --gateway-name $appgw --resource-group $rg --name $pathMapName -o json 2>$null
if (-not $existsPathMap) {
    az network application-gateway url-path-map create `
      --gateway-name $appgw `
      --resource-group $rg `
      --name $pathMapName `
      --default-address-pool $frontendPoolNameExplicit `
      --default-http-settings $frontendHttpSettings | Out-Null
} else {
    Write-Host "UrlPathMap $pathMapName ya existe."
}

# Añadir regla path-based para /datos/* apuntando a BackendPool y BackendHttpSettings
Write-Host "Creando regla path-based '$datosRuleName' para /datos/* -> BackendPool..."
$existsDatosRule = az network application-gateway url-path-map rule show --gateway-name $appgw --resource-group $rg --path-map-name $pathMapName --name $datosRuleName -o json 2>$null
if (-not $existsDatosRule) {
    az network application-gateway url-path-map rule create `
      --gateway-name $appgw `
      --resource-group $rg `
      --name $datosRuleName `
      --path-map-name $pathMapName `
      --paths /datos/* `
      --address-pool BackendPool `
      --http-settings BackendHttpSettings | Out-Null
} else {
    Write-Host "UrlPathMap rule $datosRuleName ya existe."
}

# Finalmente crear la Request Routing Rule PathBased con PRIORITY explícita
Write-Host "Creando Request Routing Rule ($requestRoutingRuleName) asociada al listener $frontendListenerName con prioridad $priorityValue..."
$existsRequestRule = az network application-gateway rule show --gateway-name $appgw --resource-group $rg --name $requestRoutingRuleName -o json 2>$null
if (-not $existsRequestRule) {
    az network application-gateway rule create `
      --gateway-name $appgw `
      --resource-group $rg `
      --name $requestRoutingRuleName `
      --rule-type PathBasedRouting `
      --http-listener $frontendListenerName `
      --url-path-map $pathMapName `
      --priority $priorityValue | Out-Null
} else {
    Write-Host "Request routing rule $requestRoutingRuleName ya existe."
}

Write-Host "Reglas path-based y prioridad configuradas correctamente. Revisa el AppGW en el portal para confirmar reglas y estado."

Write-Host "`nDeploy finalizado (o en proceso). Frontend público en: http://${publicIp}:${frontendPort} (cuando AppGW esté listo)."
Write-Host "El endpoint /datos será en: http://${publicIp}:${frontendPort}/datos (redirigido al backend privado)."