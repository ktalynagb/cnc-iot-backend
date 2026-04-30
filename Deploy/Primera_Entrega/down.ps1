<#
down.ps1 elimina los recursos creados por deploy.ps1.
ADVERTENCIA: Esto borrará el resource group completo y todos los recursos dentro.
#>

param(
    [string]$EnvFile = ".\.env",
    [switch]$ConfirmDeletion
)

function Load-EnvFile($path) {
    if (Test-Path $path) {
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
    } else {
        Write-Warning "$path no encontrado. Procederé a preguntar por RG."
    }
}

Load-EnvFile -path $EnvFile
$rg = $env:RG_NAME

if (-not $rg) {
    $rg = Read-Host "Ingresa el nombre del resource group a borrar"
}

if (-not $ConfirmDeletion) {
    $ok = Read-Host "Vas a borrar el resource group '$rg' y TODO su contenido. Escribe 'DELETE' para confirmar"
    if ($ok -ne "DELETE") {
        Write-Host "Cancelado."
        exit 0
    }
}

Write-Host "Borrando resource group $rg (esto puede tardar)..."
az group delete --name $rg --yes --no-wait
Write-Host "Solicitud de borrado enviada."