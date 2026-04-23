# ============================================================
#  CNC IoT - Makefile  (Windows-native / PowerShell)
#  Uso: make <comando>
# ============================================================

SHELL := powershell.exe
.SHELLFLAGS := -NoProfile -Command

BACKEND_DIR  := backend
FRONTEND_DIR := frontend
NPM          := npm

# Variables fijas 
DOCKER_USERNAME := davids117
FRONTEND_IMAGE  := davids117/cnc-iot-backend-frontend:latest
BACKEND_IMAGE   := davids117/cnc-iot-backend-backend:latest

# El archivo .env solo se usará para la contraseña en el login 
DEPLOY_ENV   := Deploy\.env

.PHONY: help \
        setup install env \
        run test \
        clean \
        frontend-install frontend-dev frontend-test \
        docker-up docker-down docker-logs \
        build-frontend build-backend \
        push-frontend push-backend \
        release \
        deploy down

# ------------------------------------------------------------
# AYUDA
# ------------------------------------------------------------
help:
	@Write-Host ""
	@Write-Host "   CNC IoT - comandos disponibles"
	@Write-Host ""
	@Write-Host "  BACKEND (local con uv)"
	@Write-Host "    make setup           - Sincroniza dependencias y prepara .env"
	@Write-Host "    make install         - cd backend && uv sync"
	@Write-Host "    make run             - cd backend && uv run uvicorn app.main:app"
	@Write-Host "    make test            - cd backend && uv run pytest"
	@Write-Host "    make clean           - Borrar carpetas __pycache__"
	@Write-Host ""
	@Write-Host "  FRONTEND (local con npm)"
	@Write-Host "    make frontend-install - npm install en /frontend"
	@Write-Host "    make frontend-dev     - npm run dev  (puerto 3000)"
	@Write-Host "    make frontend-test    - npm test"
	@Write-Host ""
	@Write-Host "  DOCKER"
	@Write-Host "    make docker-up       - Construye e inicia todos los servicios"
	@Write-Host "    make docker-down     - Detiene y elimina contenedores"
	@Write-Host "    make docker-logs     - Muestra logs en tiempo real"
	@Write-Host ""
	@Write-Host "  DOCKER HUB (Variables fijas configuradas)"
	@Write-Host "    make build-frontend  - Construye la imagen Docker del frontend"
	@Write-Host "    make build-backend   - Construye la imagen Docker del backend"
	@Write-Host "    make push-frontend   - Login (vía .env) y push de la imagen del frontend"
	@Write-Host "    make push-backend    - Login (vía .env) y push de la imagen del backend"
	@Write-Host "    make release         - Build + push de frontend y backend en un paso"
	@Write-Host ""
	@Write-Host "  AZURE DEPLOY [cite: 33]"
	@Write-Host "    make deploy          - Ejecuta Deploy\deploy.ps1"
	@Write-Host "    make down            - Ejecuta Deploy\down.ps1"
	@Write-Host ""

# ------------------------------------------------------------
# BACKEND - local con uv
# ------------------------------------------------------------
setup: install env
	@Write-Host "Setup completo. Edita $(BACKEND_DIR)\.env y ejecuta: make run"

install:
	@Write-Host "Instalando dependencias con uv sync..."
	cd $(BACKEND_DIR); uv sync
	@Write-Host "Dependencias instaladas."

env:
	@if (-Not (Test-Path "$(BACKEND_DIR)\.env")) { \
		Copy-Item "$(BACKEND_DIR)\.env.example" "$(BACKEND_DIR)\.env"; \
		Write-Host "$(BACKEND_DIR)\.env creado - edítalo con tus valores."; \
	} else { \
		Write-Host "$(BACKEND_DIR)\.env ya existe, no se sobreescribe."; \
	}

run:
	@Write-Host "Iniciando servidor en http://0.0.0.0:8000 ..."
	cd $(BACKEND_DIR); uv run uvicorn app.main:app --host 0.0.0.0 --port 8000

test:
	@Write-Host "Ejecutando tests del backend..."
	cd $(BACKEND_DIR); uv run pytest

clean:
	@Write-Host "Limpiando carpetas __pycache__..."
	Get-ChildItem -Recurse -Filter "__pycache__" -Directory | Remove-Item -Recurse -Force
	Get-ChildItem -Recurse -Filter "*.pyc" | Remove-Item -Force
	@Write-Host "Limpieza completa."

# ------------------------------------------------------------
# FRONTEND - local con npm
# ------------------------------------------------------------
frontend-install:
	@Write-Host "Instalando dependencias del frontend..."
	cd $(FRONTEND_DIR); $(NPM) install
	@Write-Host "Dependencias del frontend instaladas."

frontend-dev:
	@Write-Host "Levantando servidor de desarrollo Next.js en http://localhost:3000 ..."
	cd $(FRONTEND_DIR); $(NPM) run dev

frontend-test:
	@Write-Host "Ejecutando suite de pruebas del frontend..."
	cd $(FRONTEND_DIR); $(NPM) test

# ------------------------------------------------------------
# DOCKER
# ------------------------------------------------------------
docker-up:
	@Write-Host "Construyendo e iniciando servicios Docker..."
	docker compose up --build -d

docker-down:
	@Write-Host "Deteniendo y eliminando contenedores..."
	docker compose down

docker-logs:
	docker compose logs -f

# ------------------------------------------------------------
# DOCKER HUB — build, push y release
# Lee DOCKER_USERNAME, DOCKER_PASSWORD, FRONTEND_IMAGE y
# BACKEND_IMAGE desde Deploy\.env
# ------------------------------------------------------------

build-deploy:
	@Write-Host "Construyendo imágenes Docker para frontend y backend..."
	docker compose build
	@Write-Host "Imágenes construidas: $(FRONTEND_IMAGE) y $(BACKEND_IMAGE)."

push-frontend:
	@Write-Host "Publicando imagen del frontend en Docker Hub..."
	@$$env = Get-Content "$(DEPLOY_ENV)" | Where-Object { $$_ -match '^DOCKER_PASSWORD' } | ForEach-Object { $$k, $$v = $$_ -split '=', 2; [System.Environment]::SetEnvironmentVariable($$k.Trim(), $$v.Trim()) }; \
	$$pass = [System.Environment]::GetEnvironmentVariable("DOCKER_PASSWORD"); \
	$$pass | docker login --username $(DOCKER_USERNAME) --password-stdin; \
	docker push $(FRONTEND_IMAGE)
	@Write-Host "Frontend publicado."

push-backend:
	@Write-Host "Publicando imagen del backend en Docker Hub..."
	@$$env = Get-Content "$(DEPLOY_ENV)" | Where-Object { $$_ -match '^DOCKER_PASSWORD' } | ForEach-Object { $$k, $$v = $$_ -split '=', 2; [System.Environment]::SetEnvironmentVariable($$k.Trim(), $$v.Trim()) }; \
	$$pass = [System.Environment]::GetEnvironmentVariable("DOCKER_PASSWORD"); \
	$$pass | docker login --username $(DOCKER_USERNAME) --password-stdin; \
	docker push $(BACKEND_IMAGE)
	@Write-Host "Backend publicado."

release: push-frontend push-backend
	@Write-Host ""
	@Write-Host "Release completo — ambas imágenes publicadas en Docker Hub."
	@Write-Host "Ahora puedes ejecutar: make deploy" 
	@Write-Host ""

# ------------------------------------------------------------
# AZURE DEPLOY (PowerShell)
# ------------------------------------------------------------
deploy:
	@Write-Host "Ejecutando deploy completo en Azure..."
	powershell -NoProfile -ExecutionPolicy Bypass -File "Deploy\deploy.ps1"

down:
	@Write-Host "Eliminando recursos de Azure..."
	powershell -NoProfile -ExecutionPolicy Bypass -File "Deploy\down.ps1"