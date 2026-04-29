# 🏭 CNC IoT Backend — Monitoreo de Máquina CNC

Proyecto de la **Especialización en Inteligencia Artificial aplicada a IoT**  
Universidad Autónoma de Occidente · Práctica 1

## Integrantes
| Rol | Persona | Responsabilidad |
|-----|---------|-----------------|
| Hardware & Firmware | Valentina | ESP32-CAM + MPU-6050 + DHT11 |
| Backend & BD | Ktalyna | FastAPI + PostgreSQL + CSV |
| Dashboard + Azure | David | Frontend + despliegue en nube |

## Caso de uso
Monitoreo en tiempo real de una **máquina CNC** para detectar:
- 🌡️ Temperatura del entorno (DHT11)
- 💧 Humedad relativa (DHT11)
- 📳 Vibración en ejes X, Y, Z (MPU-6050)
- 🚨 Alertas automáticas cuando los valores superan los umbrales configurados

## Stack tecnológico
- **Firmware:** Arduino C++ en ESP32-CAM
- **Backend:** Python 3.11 + FastAPI + SQLAlchemy + uv
- **Base de datos:** PostgreSQL 15
- **Frontend:** Next.js 16 (App Router) + Tailwind CSS + Recharts
- **Almacenamiento adicional:** CSV con timestamp por lectura
- **Nube:** Azure (ACI + Application Gateway)

## Hardware
| Componente | Función |
|------------|---------|
| **ESP32-CAM** | Microcontrolador WiFi con cámara integrada. Actúa como cliente HTTP y transmite las lecturas al backend cada segundo. |
| **MPU-6050** | IMU de 6 ejes (acelerómetro + giroscopio). Mide la vibración de la máquina en los ejes X, Y y Z (m/s²). Se conecta por I²C al ESP32. |
| **DHT11** | Sensor digital de temperatura (°C) y humedad relativa (%). Se conecta mediante un solo pin de datos al ESP32. |

## Estructura del repositorio
```
cnc-iot-backend/
├── backend/
│   ├── app/
│   │   ├── main.py           # Entrada FastAPI
│   │   ├── database.py       # Conexión PostgreSQL
│   │   ├── alertas.py        # Lógica de alertas y cálculo de vibración
│   │   ├── csv_writer.py     # Escritura thread-safe en CSV
│   │   ├── config.py         # Variables de entorno (pydantic-settings)
│   │   ├── models/           # Modelos SQLAlchemy
│   │   ├── schemas/          # Schemas Pydantic
│   │   └── routers/
│   │       ├── datos.py      # POST /datos/ · GET /datos/ · GET /datos/descargar/
│   │       └── alertas.py    # GET /alertas/
│   └── tests/
├── frontend/
│   ├── app/
│   │   ├── page.tsx          # Dashboard principal (incluye botón Descargar CSV)
│   │   ├── hooks/            # useDatos, useAlertas (polling cada 1 s)
│   │   ├── components/       # KpiCard, MetricChart, AlertsPanel, CameraStream
│   │   └── types/            # Interfaces TypeScript
│   ├── Dockerfile            # Multi-stage: next build → next start (producción)
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

## Lógica de alertas
El backend calcula la **vibración total** como la magnitud euclidiana de los tres ejes:

```
vibracion_total = √(accel_x² + accel_y² + accel_z²)
```

Cada lectura se evalúa contra los siguientes umbrales. Si alguno se supera,
el campo `alerta` se marca como `true` y `motivo_alerta` describe la causa:

| Variable | Mínimo | Máximo | Motivo en alerta |
|----------|--------|--------|------------------|
| Temperatura (°C) | 15 | 45 | `"Temperatura fuera de rango"` |
| Humedad (%) | 20 | 80 | `"Humedad fuera de rango"` |
| Vibración total (m/s²) | — | **2.0** | `"Vibración excesiva"` |

> Los umbrales son configurables mediante variables de entorno (`TEMP_MIN`, `TEMP_MAX`, `HUM_MIN`, `HUM_MAX`, `ACCEL_MAX`) en `backend/.env`.

## Endpoints principales
| Método | Ruta | Descripción |
|--------|------|-------------|
| `POST` | `/datos/` | Recibe lectura del ESP32, evalúa alertas, persiste en BD y CSV |
| `GET`  | `/datos/` | Retorna las últimas N lecturas (parámetro `limit`, máx. 1000) |
| `GET`  | `/datos/descargar/` | Descarga el archivo CSV completo como adjunto (`attachment`) |
| `GET`  | `/alertas/` | Lista las lecturas con `alerta = true` |
| `GET`  | `/` | Health-check del servicio |

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

## Publicar imágenes Docker (Docker Hub)

Antes de desplegar en Azure, las imágenes deben estar publicadas en Docker Hub.

```powershell
# 1. Configurar variables (incluye DOCKER_USERNAME y DOCKER_PASSWORD)
Copy-Item Deploy\.env.example Deploy\.env
# Editar Deploy\.env con tus valores reales

# 2. Construir ambas imágenes
make build-backend
make build-frontend

# 3. Publicar ambas imágenes (incluye docker login automático)
make push-backend
make push-frontend

# 4. O en un solo paso: build + push de todo
make release
```

## Despliegue en Azure

### Pre-requisitos
- [Azure CLI](https://learn.microsoft.com/es-es/cli/azure/install-azure-cli) instalado y autenticado (`az login`)
- PowerShell 5+ (Windows) o PowerShell Core (Linux/Mac)
- Imágenes publicadas en Docker Hub (ver `make release` arriba)

### Arquitectura de red

```
Internet
    │
    ▼
Application Gateway  (IP pública · puerto 80)
    ├── /datos/*  ──────────► Backend ACI   (puerto 8000)  ┐
    └── /*        ──────────► Frontend ACI  (puerto 3000)  ├─ subnet privada
                                    └── PostgreSQL ACI     ┘
```

El frontend usa **rutas relativas** (`/datos/`, `/alertas/`, `/datos/descargar/`) para
llamar a la API, de modo que el Application Gateway enruta las peticiones correctamente
sin necesidad de configurar `NEXT_PUBLIC_API_URL` en producción.

### Pasos

```powershell
# 1. Configurar variables
Copy-Item Deploy\.env.example Deploy\.env
# Editar Deploy\.env con tus valores reales

# 2. Publicar imágenes Docker
make release

# 3. Desplegar toda la infraestructura en Azure
make deploy
#   Equivale a: powershell -File Deploy\deploy.ps1
#   La URL pública se imprime al final del script.

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
| `FRONTEND_IMAGE` | Imagen Docker del frontend (ej. `ktalynagb/frontend:latest`) |
| `BACKEND_IMAGE` | Imagen Docker del backend (ej. `ktalynagb/backend:latest`) |
| `DB_*` | Credenciales de PostgreSQL |
| `DOCKER_USERNAME` / `DOCKER_PASSWORD` | Credenciales Docker Hub (usadas por `make push-*` y ACI) |

