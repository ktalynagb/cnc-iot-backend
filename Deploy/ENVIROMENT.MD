Instrucciones de despliegue y gestión de secretos
================================================

Resumen
-------
Los scripts PowerShell permiten:
- deploy.ps1: crear RG, VNet (public + private), desplegar ACI (frontend, backend, db) en la private-subnet y crear Application Gateway en public-subnet para exponer frontend públicamente.
- down.ps1: eliminar el resource group (hard restart / cleanup).

Preparación (local)
-------------------
1) Clona/coloca la carpeta `deploy` en tu máquina.
2) Copia `.env.example` a `.env` y rellena los valores:
   - No pongas contraseñas/secretos reales en `.env` si vas a subirlo. Usar Azure Key Vault es más seguro.
3) Instala Azure CLI y loguea:
   - az login
   - az account set --subscription <id>

Ejecutar deploy
---------------
Desde PowerShell:
```
  ./deploy.ps1
```

Esto leerá .env, creará recursos y te devolverá la IP pública del Application Gateway cuando esté listo (puede tardar).

Eliminar / hard restart
-----------------------
Para destruir todo:
```
  ./down.ps1
```
Te pedirá confirmar escribiendo DELETE.

Manejo de secretos (recomendado)
--------------------------------
Nunca guardar contraseñas reales en `.env` en repositorios. Opciones:

1) Usar Azure Key Vault (recomendado)
   - Crear Key Vault:
   ```
     az keyvault create -n myVault -g <RG> -l <LOCATION>
   ```
   - Guardar secret:
   ```
     az keyvault secret set --vault-name myVault --name DB_PASSWORD --value "SuperSecreto!"
   ```
   - En PowerShell puedes obtenerlo en tiempo de ejecución:
   ```
     $dbPass = az keyvault secret show --vault-name myVault --name DB_PASSWORD --query value -o tsv
   ```
   Ejemplo simple en PowerShell antes de lanzar deploy.ps1:
   ```
     $env:DB_PASSWORD = $(az keyvault secret show --vault-name myVault --name DB_PASSWORD --query value -o tsv)
     ./deploy.ps1
   ```

2) Exportar variables de entorno en PowerShell (temporal, no persistente)
   En PowerShell:
   ```
     $env:DB_PASSWORD = "SuperSecreto!"
     $env:AZ_SUBSCRIPTION_ID = "xxxx-xxxx-..."
     ./deploy.ps1
   ```

3) Usar Azure CLI para pasar variables (ej. inyectar desde script CI/CD) — preferible para pipelines.

Cómo sacar secrets desde terminal (ejemplos)
--------------------------------------------
- PowerShell (temporal en sesión):
  ```
  $env:DB_PASSWORD = Read-Host -AsSecureString "DB password" | ConvertFrom-SecureString
  # Nota: ConvertFrom-SecureString guarda en formato cifrado de usuario local; mejor usar Key Vault.
  ```

- Obtener secret desde Key Vault y exportar:
  ```
  $env:DB_PASSWORD = az keyvault secret show --vault-name myVault --name DB_PASSWORD --query value -o tsv
  ```

Notas finales
-------------
- El aprovisionamiento de App Gateway puede tardar 10-15 minutos.
- Verifica quotas de tu suscripción (Application Gateway y ACI).
- Si quieres que frontend esté directamente en la public-subnet con IP pública, la alternativa es usar una VM o un LB; ACI en subnet no admite IP pública directa, por eso se usa Application Gateway para exponer el servicio.
- Puedo adaptar el script para AKS (más apropiado para producción), o para usar Azure Container Apps si prefieres una experiencia serverless.