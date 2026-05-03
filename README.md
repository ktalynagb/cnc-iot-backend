# 🏭 CNC IoT — Monitoreo de Máquina CNC · Entrega 2

Proyecto de la **Especialización en Inteligencia Artificial aplicada a IoT**  
Universidad Autónoma de Occidente · Práctica 2 — Broker MQTT + InfluxDB + Grafana

## Integrantes

| Rol | Persona | Responsabilidad |
|-----|---------|-----------------|
| Hardware & Firmware | Valentina | ESP32-C3 + MPU-6050 + DHT22 + MQTT |
| Backend & Bridge | Ktalyna | Bridge MQTT→InfluxDB + FastAPI + CSV |
| Infra & Visualización | David | AWS · Mosquitto · InfluxDB · Grafana |

## Caso de uso

Monitoreo en tiempo real de una **máquina CNC FLUX** para detectar condiciones anómalas:

- 🌡️ Temperatura del entorno (DHT22)
- 💧 Humedad relativa (DHT22)
- 📳 Vibración en ejes X, Y, Z (MPU-6050)
- 🚨 Alertas automáticas cuando los valores superan los umbrales configurados

## Arquitectura (Entrega 2)

```
ESP32-C3
  │  publica via MQTT (puerto 1883)
  ▼
Mosquitto (AWS EC2 Ubuntu)
  │  suscriptor
  ▼
mqtt_bridge.py  ──► alertas.py ──► evalúa umbrales
  │              └► csv_writer.py ──► lecturas.csv
  ▼
InfluxDB (bucket: flux_cnc)
  │
  ▼
Grafana (paneles + alertas + notificaciones)
  │
  ▼ (opcional)
FastAPI GET /datos/ · GET /datos/descargar/
```

> **Cambio vs Entrega 1:** se reemplazó HTTP POST → PostgreSQL por MQTT → InfluxDB.  
> El `POST /datos/` fue eliminado. Los endpoints GET se conservan para compatibilidad.

## Stack tecnológico

| Capa | Tecnología |
|------|-----------|
| Firmware | Arduino C++ · ESP32-C3 Super Mini |
| Protocolo IoT | MQTT (paho-mqtt / PubSubClient) |
| Broker | Mosquitto 2.x con autenticación usuario/contraseña |
| Bridge | Python 3.x + paho-mqtt + influxdb-client |
| Base de datos | InfluxDB 2.7 (time-series) |
| Visualización | Grafana (dashboards + alertas) |
| API REST | FastAPI (solo lectura — GET) |
| Infra | AWS EC2 Ubuntu + Docker Compose |

## Hardware

| Componente | Conexión | Función |
|------------|----------|---------|
| **ESP32-C3 Super Mini** | — | Microcontrolador WiFi. Publica lecturas por MQTT cada 2 s |
| **MPU-6050** | SDA=GPIO8, SCL=GPIO9 | Acelerómetro I²C. Mide vibración en X, Y, Z (m/s²) |
| **DHT22** | GPIO0 | Sensor de temperatura (°C) y humedad (%) |

> ⚠️ GPIO21 dañado — no usar.

## Estructura del repositorio

```
cnc-iot-backend/
├── Esp32/
│   └── cnc_iot_esp32/
│       ├── cnc_iot_esp32.ino   # Firmware: DHT22 + MPU-6050 + MQTT
│       └── credentials.h       # WiFi + MQTT (NO subir credenciales reales)
├── bridge/
│   ├── mqtt_bridge.py          # Suscriptor MQTT → InfluxDB + CSV
│   └── mqtt_bridge.service     # Servicio systemd para AWS
├── backend/
│   ├── app/
│   │   ├── main.py             # FastAPI (solo GET)
│   │   ├── database.py         # Cliente InfluxDB
│   │   ├── alertas.py          # calcular_vibracion() · evaluar_alerta()
│   │   ├── csv_writer.py       # guardar_lectura_csv() thread-safe
│   │   ├── config.py           # Variables de entorno (pydantic-settings)
│   │   ├── models/
│   │   ├── schemas/
│   │   └── routers/
│   │       ├── datos.py        # GET /datos/ · GET /datos/descargar/
│   │       └── alertas.py      # GET /alertas/
│   ├── requirements.txt
│   └── .env.example
├── docker-compose.yml
└── Makefile
```

## Topics MQTT y formato de payload

El ESP32 publica en tres topics independientes:

| Topic | Payload JSON | Ejemplo |
|-------|-------------|---------|
| `flux/cnc1/temperatura` | `{"value": <float>}` | `{"value": 28.5}` |
| `flux/cnc1/humedad` | `{"value": <float>}` | `{"value": 60.2}` |
| `flux/cnc1/vibracion` | `{"accel_x": <float>, "accel_y": <float>, "accel_z": <float>}` | `{"accel_x": 0.12, "accel_y": -0.03, "accel_z": 9.81}` |

El bridge acumula los tres mensajes y cuando tiene el conjunto completo escribe un punto en InfluxDB.

## Lógica de alertas y umbrales

La vibración total se calcula como magnitud euclidiana:

```
vibracion_total = √(accel_x² + accel_y² + accel_z²)
```

| Variable | Mínimo | Máximo |
|----------|--------|--------|
| Temperatura (°C) | 15.0 | 45.0 |
| Humedad (%) | 20.0 | 80.0 |
| Vibración total (m/s²) | — | 2.0 |

Umbrales configurables en `backend/.env` mediante `TEMP_MIN`, `TEMP_MAX`, `HUM_MIN`, `HUM_MAX`, `ACCEL_MAX`.

## Variables de entorno (backend/.env)

Copia `backend/.env.example` a `backend/.env` y completa los valores:

```env
# Servidor FastAPI
APP_HOST=0.0.0.0
APP_PORT=8000

# CSV
CSV_PATH=data/lecturas.csv

# Alertas
TEMP_MIN=15.0
TEMP_MAX=45.0
HUM_MIN=20.0
HUM_MAX=80.0
ACCEL_MAX=2.0

# InfluxDB
INFLUX_URL=http://localhost:8086
INFLUX_TOKEN=tu_token_aqui
INFLUX_ORG=flux
INFLUX_BUCKET=flux_cnc

# MQTT
MQTT_BROKER=ip_publica_aws
MQTT_PORT=1883
MQTT_USER=flux_user
MQTT_PASSWORD=flux_pass
```

## Inicio rápido — prueba local

### Requisitos
- Docker Desktop
- Python 3.10+

### 1. Levantar InfluxDB y Mosquitto con Docker

```powershell
# InfluxDB
docker run -d --name influxdb -p 8086:8086 influxdb:2.7

# Mosquitto (sin auth para pruebas locales)
mkdir mosquitto-config
echo "listener 1883`nallow_anonymous true" | Out-File -Encoding ASCII mosquitto-config/mosquitto.conf
docker run -d --name mosquitto -p 1883:1883 `
  -v ${PWD}/mosquitto-config/mosquitto.conf:/mosquitto/config/mosquitto.conf `
  eclipse-mosquitto
```

### 2. Configurar InfluxDB

Abre `http://localhost:8086`, crea usuario/org `flux` y bucket `flux_cnc`.  
Copia el token generado al `.env`.

### 3. Instalar dependencias

```powershell
pip install fastapi uvicorn pydantic pydantic-settings python-dotenv influxdb-client paho-mqtt
```

### 4. Arrancar el bridge

```powershell
python bridge/mqtt_bridge.py
```

### 5. Simular el ESP32

```powershell
python -c "
import paho.mqtt.client as mqtt, json, time
c = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
c.connect('localhost', 1883)
time.sleep(1)
c.publish('flux/cnc1/temperatura', json.dumps({'value': 28.5}))
c.publish('flux/cnc1/humedad', json.dumps({'value': 60.0}))
c.publish('flux/cnc1/vibracion', json.dumps({'accel_x': 0.1, 'accel_y': 0.2, 'accel_z': 0.9}))
c.disconnect()
"
```

Deberías ver en la consola del bridge:
```
Lectura completa — T=28.50°C  H=60.00%  Vib=0.9327 m/s²  Alerta=False
  → InfluxDB ✓
  → CSV ✓
```

## Deploy en AWS (producción)

### Puertos requeridos en Security Group

| Puerto | Protocolo | Servicio |
|--------|-----------|---------|
| 22 | TCP | SSH |
| 1883 | TCP | Mosquitto MQTT |
| 8086 | TCP | InfluxDB |
| 3000 | TCP | Grafana |
| 8000 | TCP | FastAPI (opcional) |

### 1. Clonar el repo en la VM

```bash
ssh -i tu_llave.pem ubuntu@IP_PUBLICA
git clone https://github.com/ktalynagb/cnc-iot-backend.git
cd cnc-iot-backend
```

### 2. Configurar .env

```bash
cp backend/.env.example backend/.env
nano backend/.env
# Completar INFLUX_TOKEN, MQTT_BROKER=localhost, etc.
```

### 3. Instalar UV (gestor de entornos Python)

```bash
curl -LsSf https://astral.sh/uv/install.sh | UV_INSTALL_DIR=/usr/local/bin sh
```

### 4. Instalar el bridge como servicio systemd con UV

El bridge usa UV para gestionar sus dependencias. No necesita `uv.lock` previo; UV lo genera
automáticamente la primera vez que arranca el servicio.

```bash
sudo cp bridge/mqtt_bridge.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable mqtt_bridge
sudo systemctl start mqtt_bridge

# Verificar
sudo systemctl status mqtt_bridge
sudo journalctl -u mqtt_bridge -f
```

> El provisioning automatizado (`provision-front.sh`) realiza todos estos pasos sin intervención manual.

## Descarga del CSV desde la nube

El CSV de todas las lecturas se puede descargar directamente desde el endpoint del backend:

```
GET http://<IP_PUBLICA>:8000/datos/descargar/
```

El archivo se descarga con nombre `lecturas_cnc_<timestamp>.csv` y contiene todas las lecturas
acumuladas por el bridge desde el inicio del servicio.

El CSV se escribe en `/home/ubuntu/cnc-iot-backend/backend/data/lecturas.csv` en la VM pública.

## Endpoints API REST (solo lectura)

| Método | Ruta | Descripción |
|--------|------|-------------|
| `GET` | `/datos/` | Últimas N lecturas desde InfluxDB (parámetro `limit`) |
| `GET` | `/datos/descargar/` | **Descarga el CSV completo** como archivo adjunto |
| `GET` | `/datos/alertas/` | Lecturas con `alerta = true` desde InfluxDB |

> El `POST /datos/` fue eliminado en esta entrega — los datos llegan por MQTT.

## Criterios de evaluación (rúbrica Práctica 2)

| Criterio | Cómo verificarlo |
|----------|-----------------|
| ✅ Funcionalidad | Datos del ESP32 visibles en InfluxDB Data Explorer → bucket `flux_cnc` |
| ✅ Comunicación MQTT | Log de Mosquitto mostrando mensajes continuos del ESP32 |
| ✅ Broker MQTT | `mosquitto_sub -h IP -u flux_user -P flux_pass -t "flux/#"` recibe datos |
| ✅ Visualización Grafana | Dashboard con paneles de temperatura, humedad y vibración + alertas activas |
| ✅ Descarga CSV | `curl http://<IP>:8000/datos/descargar/ -o lecturas.csv` descarga todas las lecturas |