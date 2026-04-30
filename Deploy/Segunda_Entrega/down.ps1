<#
down.ps1 elimina todos los recursos creados por deploy.ps1 / fase4.ps1 (Segunda Entrega).
ADVERTENCIA: Esto borrará el resource group 'rg-cnc-iot' y TODOS los recursos dentro,
incluyendo VMs, VNet y NSGs.
#>

param(
    [switch]$ConfirmDeletion
)

$RG_NAME = "rg-cnc-iot"

if (-not $ConfirmDeletion) {
    $ok = Read-Host "Vas a borrar el resource group '$RG_NAME' y TODO su contenido. Escribe 'DELETE' para confirmar"
    if ($ok -ne "DELETE") {
        Write-Host "Cancelado." -ForegroundColor Yellow
        exit 0
    }
}

Write-Host "Borrando resource group '$RG_NAME' (esto puede tardar varios minutos)..." -ForegroundColor Yellow
az group delete --name $RG_NAME --yes --no-wait
Write-Host "  -> Solicitud de borrado enviada para '$RG_NAME'." -ForegroundColor Green

Write-Host ""
Write-Host "Limpieza completada." -ForegroundColor Green
