# ============================================================
#  CNC IoT — Makefile  (Windows-native / PowerShell)
#  Uso: make <comando>
# ============================================================

SHELL := powershell.exe
.SHELLFLAGS := -NoProfile -Command

BACKEND_DIR  := backend
FRONTEND_DIR := frontend
NPM          := npm

.PHONY: help \
        setup install env \
        run test \
        clean \
        frontend-install frontend-dev frontend-test \
        docker-up docker-down docker-logs

# ------------------------------------------------------------
# AYUDA
# ------------------------------------------------------------
help:
	@Write-Host ""
	@Write-Host "   CNC IoT — comandos disponibles"
	@Write-Host ""
	@Write-Host "  BACKEND (local con uv)"
	@Write-Host "    make setup           — Sincroniza dependencias y prepara .env"
	@Write-Host "    make install         — cd backend && uv sync"
	@Write-Host "    make run             — cd backend && uv run uvicorn app.main:app"
	@Write-Host "    make test            — cd backend && uv run pytest"
	@Write-Host "    make clean           — Borrar carpetas __pycache__"
	@Write-Host ""
	@Write-Host "  FRONTEND (local con npm)"
	@Write-Host "    make frontend-install — npm install en /frontend"
	@Write-Host "    make frontend-dev     — npm run dev  (puerto 3000)"
	@Write-Host "    make frontend-test    — npm test"
	@Write-Host ""
	@Write-Host "  DOCKER"
	@Write-Host "    make docker-up       — Construye e inicia todos los servicios"
	@Write-Host "    make docker-down     — Detiene y elimina contenedores"
	@Write-Host "    make docker-logs     — Muestra logs en tiempo real"
	@Write-Host ""

# ------------------------------------------------------------
# BACKEND — local con uv
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
		Write-Host "$(BACKEND_DIR)\.env creado — edítalo con tus valores."; \
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
# FRONTEND — local con npm
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