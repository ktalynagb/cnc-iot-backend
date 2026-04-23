# 🏭 CNC IoT Backend — Monitoreo de Máquina CNC

Proyecto de la **Especialización en Inteligencia Artificial aplicada a IoT**  
Universidad Autónoma de Occidente · Práctica 1

## Integrantes
| Rol | Persona | Responsabilidad |
|-----|---------|-----------------|
| Hardware & Firmware | Valentina | ESP32-CAM + MPU-6050 + DHT11 |
| Backend & BD | Katalyna | FastAPI + PostgreSQL + CSV |
| Dashboard + Azure | David | Frontend + despliegue en nube |

## Caso de uso
Monitoreo en tiempo real de una **máquina CNC** para detectar:
- 🌡️ Temperatura del entorno (DHT11)
- 📳 Vibración en ejes X, Y, Z (MPU-6050)
- 🚨 Alertas cuando los valores salen de rangos normales

## Stack tecnológico
- **Firmware:** Arduino C++ en ESP32-CAM
- **Backend:** Python 3.11 + FastAPI + SQLAlchemy
- **Base de datos:** PostgreSQL 15
- **Frontend:** Next.js 16 (App Router) + Tailwind CSS + Recharts
- **Almacenamiento adicional:** CSV con timestamp
- **Nube:** Azure (ACI + Application Gateway)

## Estructura del repositorio
```
cnc-iot-backend/
├── backend/
│   ├── app/
│   │   ├── main.py           # Entrada FastAPI
│   │   ├── database.py       # Conexión PostgreSQL
│   │   ├── csv_writer.py     # Escritura en CSV
│   │   ├── models/           # Modelos SQLAlchemy
│   │   ├── schemas/          # Schemas Pydantic
│   │   └── routers/          # Endpoints (/datos/ /alertas/)
│   └── tests/
├── frontend/
│   ├── app/
│   │   ├── page.tsx          # Dashboard principal
│   │   ├── hooks/            # useDatos, useAlertas (polling cada 1 s)
│   │   ├── components/       # KpiCard, MetricChart, AlertsPanel…
│   │   └── types/            # Interfaces TypeScript
│   ├── Dockerfile            # Imagen de producción (next build + next start)
│   └── next.config.ts
├── Deploy/
│   ├── deploy.ps1            # Crea toda la infra en Azure
│   ├── down.ps1              # Destruye el resource group
│   └── .env.example          # Variables requeridas
├── docker-compose.yml
└── Makefile
```

## JSON que envía el ESP32
```json
{
  "temperatura": 28.5,
  "humedad": 65.2,
  "accel_x": 0.12,
  "accel_y": -0.03,
  "accel_z": 9.81
}
```
> El timestamp y la vibración total los agrega el servidor automáticamente.

## Umbrales de alerta
| Variable | Mínimo | Máximo |
|----------|--------|--------|
| Temperatura (°C) | 15 | 45 |
| Humedad (%) | 20 | 80 |
| Vibración \|accel\| (m/s²) | — | 2.0 |

## Inicio rápido (desarrollo local)

```bash
# 1. Preparar backend (Python + uv)
make setup
make run         # → http://localhost:8000

# 2. Preparar frontend (npm)
make frontend-install
# Crea frontend/.env.local con las variables de entorno locales:
#   cp frontend/.env.local.example frontend/.env.local
make frontend-dev    # → http://localhost:3000

# 3. Todo en Docker (recomendado)
make docker-up
make docker-logs

# Ver todos los comandos
make help
```

## Despliegue en Azure

### Pre-requisitos
- [Azure CLI](https://learn.microsoft.com/es-es/cli/azure/install-azure-cli) instalado y autenticado (`az login`)
- PowerShell 5+ (Windows) o PowerShell Core (Linux/Mac)
- Imágenes de Docker publicadas en Docker Hub (ver variables `FRONTEND_IMAGE`, `BACKEND_IMAGE`)

### Pasos

```powershell
# 1. Configurar variables
Copy-Item Deploy\.env.example Deploy\.env
# Editar Deploy\.env con tus valores reales

# 2. Desplegar toda la infraestructura en Azure
make deploy
#   Equivale a: powershell -File Deploy\deploy.ps1

# 3. Acceder al dashboard
#   La URL pública se imprime al final del script:
#   http://<IP_PUBLICA>:<FRONTEND_PORT>

# 4. Destruir recursos cuando ya no se necesiten
make down
#   Equivale a: powershell -File Deploy\down.ps1
```

### Variables de entorno (Deploy/.env)
Copia `Deploy/.env.example` a `Deploy/.env` y rellena los valores:

| Variable | Descripción |
|----------|-------------|
| `AZ_SUBSCRIPTION_ID` | ID de suscripción Azure |
| `AZ_LOCATION` | Región (ej. `centralus`) |
| `RG_NAME` | Nombre del resource group |
| `FRONTEND_IMAGE` | Imagen Docker del frontend (ej. `user/frontend:latest`) |
| `BACKEND_IMAGE` | Imagen Docker del backend |
| `DB_*` | Credenciales de PostgreSQL |
| `DOCKER_USERNAME` / `DOCKER_PASSWORD` | Credenciales Docker Hub para ACI |

### Arquitectura en Azure
```
Internet → Application Gateway (IP pública)
              ├── /datos/*  → Backend ACI  (puerto 8000)  [subnet privada]
              └── /*        → Frontend ACI (puerto 3000)  [subnet privada]
                                   └── PostgreSQL ACI     [subnet privada]
```

> **Nota:** El frontend usa rutas relativas para llamar a la API (`/datos/`, `/alertas/`),
> de modo que el Application Gateway enruta las peticiones correctamente sin necesidad
> de configurar `NEXT_PUBLIC_API_URL` en producción.
