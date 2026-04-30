<#
Deploy script maestro para Azure (Version Final - A Prueba de Fallos):
- Crea RG, VNet (public + private).
- Despliega AppGW via CLI en puerto dummy (8080) temporalmente.
- Despliega ACI superando Rate Limits con Autenticacion explicita de Docker Hub.
- Frontend usa el puerto 3000 (Next.js nativo), Backend usa el puerto 8000.
- Configura proxy inverso con rutas tolerantes: "/datos" y "/datos/*" -> Backend.
#>

param(
    [string]$EnvFile = ".\.env",
    [int]$AppGwWaitTimeoutMins = 20
)

function Load-EnvFile($path) {
    if (!(Test-Path $path)) {
        Write-Error "No se encontro $path. Crea .env basado en .env.example"
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

# 1. Cargar variables
Load-EnvFile -path $EnvFile

# Validar variables minimas incluyendo credenciales Docker
$required = @(
    "AZ_SUBSCRIPTION_ID","AZ_LOCATION","RG_NAME","VNET_NAME",
    "PUBLIC_SUBNET_NAME","PRIVATE_SUBNET_NAME","VNET_PREFIX",
    "PUBLIC_SUBNET_PREFIX","PRIVATE_SUBNET_PREFIX",
    "FRONTEND_IMAGE","BACKEND_IMAGE","DB_IMAGE",
    "ACI_FRONTEND_NAME","ACI_BACKEND_NAME","ACI_DB_NAME",
    "DB_NAME","DB_USER","DB_PASSWORD","APPGW_NAME","PUBLIC_IP_NAME",
    "DOCKER_USERNAME","DOCKER_PASSWORD"
)
foreach ($r in $required) {
    if (-not (Test-Path "env:$r")) {
        Write-Error "Falta la variable $r en $EnvFile"
        exit 1
    }
}

# Variables locales
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
$publicFrontendPort = if ($env:FRONTEND_PORT) { [int]$env:FRONTEND_PORT } else { 80 }
$containerFrontendPort = 3000
$backendPort = if ($env:BACKEND_PORT) { [int]$env:BACKEND_PORT } else { 8000 }
$dbPort = if ($env:DB_PORT) { [int]$env:DB_PORT } else { 5432 }
$appgwSku = if ($env:APPGW_SKU) { $env:APPGW_SKU } else { "Standard_v2" }
$appgwCapacity = if ($env:APPGW_CAPACITY) { [int]$env:APPGW_CAPACITY } else { 1 }

# 2. Setup Base
Write-Host "Seleccionando suscripcion $subId..."
az account set --subscription $subId

Write-Host "Creando resource group $rg ..."
az group create --name $rg --location $location | Out-Null

Write-Host "Creando VNet y Subnets..."
az network vnet create --resource-group $rg --name $vnet --address-prefix $vnetPrefix --subnet-name $pubSubnet --subnet-prefix $pubPrefix --location $location | Out-Null
az network vnet subnet create --resource-group $rg --vnet-name $vnet --name $privSubnet --address-prefix $privPrefix | Out-Null

$pubSubnetId = az network vnet subnet show --resource-group $rg --vnet-name $vnet --name $pubSubnet --query id -o tsv
$privSubnetId = az network vnet subnet show --resource-group $rg --vnet-name $vnet --name $privSubnet --query id -o tsv

Write-Host "Creando IP publica $publicIpName..."
az network public-ip create --resource-group $rg --name $publicIpName --sku Standard --allocation-method Static | Out-Null
$publicIp = az network public-ip show --resource-group $rg --name $publicIpName --query "ipAddress" -o tsv

# 3. Despliegue del Application Gateway
Write-Host "Desplegando Application Gateway ($appgw) en puerto seguro (8080)..."
az network application-gateway create --resource-group $rg --name $appgw --location $location --sku $appgwSku --capacity $appgwCapacity --vnet-name $vnet --subnet $pubSubnet --public-ip-address $publicIpName --frontend-port 8080 --priority 1000 | Out-Null

# 4. Despliegue de Contenedores ACI
Write-Host "Desplegando base de datos (Autenticada)..."
az container create --resource-group $rg --name $dbName --image $dbImage --os-type Linux --cpu 1.0 --memory 1.5 --subnet $privSubnetId --ports $dbPort --environment-variables POSTGRES_DB=$dbDatabase POSTGRES_USER=$dbUser POSTGRES_PASSWORD=$dbPass --ip-address Private --restart-policy OnFailure --registry-login-server index.docker.io --registry-username $env:DOCKER_USERNAME --registry-password $env:DOCKER_PASSWORD | Out-Null
Start-Sleep -Seconds 15
$dbPrivateIp = (az container show --resource-group $rg --name $dbName -o json | ConvertFrom-Json).ipAddress.ip

Write-Host "Desplegando backend..."
az container create --resource-group $rg --name $backendName --image $backendImage --os-type Linux --cpu 1.0 --memory 1.5 --subnet $privSubnetId --ports $backendPort --environment-variables DB_HOST=$dbPrivateIp DB_PORT=$dbPort DB_NAME=$dbDatabase DB_USER=$dbUser DB_PASSWORD=$dbPass --ip-address Private --restart-policy OnFailure --registry-login-server index.docker.io --registry-username $env:DOCKER_USERNAME --registry-password $env:DOCKER_PASSWORD | Out-Null
Start-Sleep -Seconds 10
$backendPrivateIp = (az container show --resource-group $rg --name $backendName -o json | ConvertFrom-Json).ipAddress.ip

Write-Host "Desplegando frontend (Puerto $containerFrontendPort)..."
az container create --resource-group $rg --name $frontendName --image $frontendImage --os-type Linux --cpu 1.0 --memory 1.5 --subnet $privSubnetId --ports $containerFrontendPort --environment-variables BACKEND_URL="http://$($backendPrivateIp):$($backendPort)" --ip-address Private --restart-policy OnFailure --registry-login-server index.docker.io --registry-username $env:DOCKER_USERNAME --registry-password $env:DOCKER_PASSWORD | Out-Null
Start-Sleep -Seconds 10
$frontendPrivateIp = (az container show --resource-group $rg --name $frontendName -o json | ConvertFrom-Json).ipAddress.ip

# 5. Configuracion de Enrutamiento (Proxy Inverso)
Write-Host "Configurando el Proxy Inverso (Rutas e IPs)..."
az network application-gateway frontend-port create --gateway-name $appgw --resource-group $rg --name PortPublico --port $publicFrontendPort | Out-Null

az network application-gateway address-pool create --gateway-name $appgw --resource-group $rg --name FrontendPoolExplicit --servers $frontendPrivateIp | Out-Null
az network application-gateway address-pool create --gateway-name $appgw --resource-group $rg --name BackendPool --servers $backendPrivateIp | Out-Null

az network application-gateway http-settings create --gateway-name $appgw --resource-group $rg --name FrontendHttpSettings --port $containerFrontendPort --protocol Http --cookie-based-affinity Disabled | Out-Null
az network application-gateway http-settings create --gateway-name $appgw --resource-group $rg --name BackendHttpSettings --port $backendPort --protocol Http --cookie-based-affinity Disabled | Out-Null

az network application-gateway http-listener create --gateway-name $appgw --resource-group $rg --name AppGwFrontListener --frontend-port PortPublico --frontend-ip appGatewayFrontendIP | Out-Null

az network application-gateway url-path-map create --gateway-name $appgw --resource-group $rg --name UrlPathMap --rule-name DatosRule --paths "/datos" "/datos/*" --address-pool BackendPool --http-settings BackendHttpSettings --default-address-pool FrontendPoolExplicit --default-http-settings FrontendHttpSettings | Out-Null

az network application-gateway rule create --gateway-name $appgw --resource-group $rg --name RequestRule-PathBased --rule-type PathBasedRouting --http-listener AppGwFrontListener --url-path-map UrlPathMap --address-pool FrontendPoolExplicit --http-settings FrontendHttpSettings --priority 100 | Out-Null

# 6. Limpieza de Puertos Bloqueados
Write-Host "Limpiando reglas temporales del AppGW..."
az network application-gateway rule delete --gateway-name $appgw --resource-group $rg --name rule1 | Out-Null
az network application-gateway http-listener delete --gateway-name $appgw --resource-group $rg --name appGatewayHttpListener | Out-Null
az network application-gateway frontend-port delete --gateway-name $appgw --resource-group $rg --name appGatewayFrontendPort | Out-Null

Write-Host ""
Write-Host "DONE: Infraestructura Desplegada Exitosamente"
Write-Host ("Acceso al Dashboard: http://" + $publicIp + ":" + $publicFrontendPort)
Write-Host ("Endpoint para Microcontroladores: http://" + $publicIp + ":" + $publicFrontendPort + "/datos")