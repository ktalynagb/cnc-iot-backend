# ============================================================
#  CNC IoT — Makefile
#  Uso: make <comando>
# ============================================================

# ── Rutas ───────────────────────────────────────────────────
BACKEND_DIR  := backend
FRONTEND_DIR := frontend

# ── Backend (uv) ────────────────────────────────────────────
UV           := uv
VENV         := $(BACKEND_DIR)/.venv
APP          := app.main:app

ifeq ($(OS),Windows_NT)
VENV_BIN := $(VENV)/Scripts
else
VENV_BIN := $(VENV)/bin
endif

DB_NAME    := cnc_iot
DB_USER    := cnc_user

# ── Frontend ─────────────────────────────────────────────────
NPM        := npm

.PHONY: help \
        setup venv install env \
        db-create db-drop db-reset \
        run dev lint test clean logs \
        frontend-install frontend-dev frontend-test

# ------------------------------------------------------------
# AYUDA
# ------------------------------------------------------------
help:
@echo ""
@echo "  🏭  CNC IoT — comandos disponibles"
@echo ""
@echo "  ── BACKEND ─────────────────────────────────────────"
@echo "  CONFIGURACIÓN INICIAL"
@echo "    make setup           — Todo desde cero (venv + deps + .env + BD)"
@echo "    make venv            — Crear entorno virtual con uv"
@echo "    make install         — Instalar dependencias Python con uv"
@echo "    make env             — Copiar backend/.env.example → backend/.env"
@echo ""
@echo "  BASE DE DATOS"
@echo "    make db-create       — Crear usuario y BD en PostgreSQL"
@echo "    make db-drop         — Eliminar BD (¡cuidado!)"
@echo "    make db-reset        — drop + create (datos frescos)"
@echo ""
@echo "  SERVIDOR BACKEND"
@echo "    make run             — Levantar servidor en producción (puerto 8000)"
@echo "    make dev             — Levantar servidor con hot-reload"
@echo ""
@echo "  CALIDAD BACKEND"
@echo "    make lint            — Revisar estilo de código Python"
@echo "    make test            — Correr tests del backend"
@echo ""
@echo "  UTILIDADES"
@echo "    make logs            — Ver las últimas 50 líneas del CSV"
@echo "    make clean           — Borrar caché Python y CSV de pruebas"
@echo ""
@echo "  ── FRONTEND ────────────────────────────────────────"
@echo "    make frontend-install — Instalar dependencias npm del frontend"
@echo "    make frontend-dev     — Levantar servidor de desarrollo Next.js"
@echo "    make frontend-test    — Ejecutar suite de pruebas del frontend"
@echo ""

# ------------------------------------------------------------
# BACKEND — CONFIGURACIÓN INICIAL
# ------------------------------------------------------------
setup: venv install env db-create
@echo ""
@echo "  ✅  Setup completo. Edita $(BACKEND_DIR)/.env con tu contraseña de BD."
@echo "      Luego corre:  make run"

venv:
@echo "→ Creando entorno virtual con uv..."
$(UV) venv $(VENV)
@echo "  ✓ Entorno virtual listo en $(VENV)/"

install: venv
@echo "→ Instalando dependencias Python con uv..."
$(UV) pip install -r $(BACKEND_DIR)/requirements.txt --python $(VENV_BIN)/python
@echo "  ✓ Dependencias instaladas"

env:
@if [ ! -f $(BACKEND_DIR)/.env ]; then \
cp $(BACKEND_DIR)/.env.example $(BACKEND_DIR)/.env; \
echo "  ✓ $(BACKEND_DIR)/.env creado — edítalo con tu contraseña"; \
else \
echo "  ⚠  $(BACKEND_DIR)/.env ya existe, no se sobreescribe"; \
fi

# ------------------------------------------------------------
# BACKEND — BASE DE DATOS
# ------------------------------------------------------------
db-create:
@echo "→ Creando usuario '$(DB_USER)' y base de datos '$(DB_NAME)'..."
@sudo -u postgres psql -c "CREATE USER $(DB_USER) WITH PASSWORD 'cambia_esta_password';" 2>/dev/null || true
@sudo -u postgres psql -c "CREATE DATABASE $(DB_NAME) OWNER $(DB_USER);" 2>/dev/null || true
@sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $(DB_NAME) TO $(DB_USER);" 2>/dev/null || true
@echo "  ✓ BD lista. Recuerda actualizar DB_PASSWORD en $(BACKEND_DIR)/.env"

db-drop:
@echo "→ Eliminando base de datos '$(DB_NAME)'..."
@sudo -u postgres psql -c "DROP DATABASE IF EXISTS $(DB_NAME);"
@sudo -u postgres psql -c "DROP USER IF EXISTS $(DB_USER);"
@echo "  ✓ BD eliminada"

db-reset: db-drop db-create
@echo "  ✓ BD recreada desde cero"

# ------------------------------------------------------------
# BACKEND — SERVIDOR
# ------------------------------------------------------------
run:
@echo "→ Iniciando servidor en http://0.0.0.0:8000 ..."
cd $(BACKEND_DIR) && ../$(VENV_BIN)/uvicorn $(APP) --host 0.0.0.0 --port 8000

dev:
@echo "→ Iniciando servidor con hot-reload en http://localhost:8000 ..."
@echo "   Docs: http://localhost:8000/docs"
cd $(BACKEND_DIR) && ../$(VENV_BIN)/uvicorn $(APP) --host 0.0.0.0 --port 8000 --reload

# ------------------------------------------------------------
# BACKEND — CALIDAD
# ------------------------------------------------------------
lint:
@echo "→ Revisando código con ruff..."
$(UV) pip install ruff -q --python $(VENV_BIN)/python
$(VENV_BIN)/ruff check $(BACKEND_DIR)/app/

test:
@echo "→ Corriendo tests del backend..."
$(UV) pip install httpx pytest pytest-asyncio -q --python $(VENV_BIN)/python
cd $(BACKEND_DIR) && ../$(VENV_BIN)/pytest tests/ -v

# ------------------------------------------------------------
# BACKEND — UTILIDADES
# ------------------------------------------------------------
logs:
@echo "→ Últimas 50 filas del CSV:"
@tail -n 50 $(BACKEND_DIR)/data/lecturas.csv 2>/dev/null || echo "  ⚠  CSV no encontrado aún"

clean:
@echo "→ Limpiando caché..."
find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find . -name "*.pyc" -delete 2>/dev/null || true
@echo "  ✓ Limpio"

# ------------------------------------------------------------
# FRONTEND
# ------------------------------------------------------------
frontend-install:
@echo "→ Instalando dependencias del frontend..."
cd $(FRONTEND_DIR) && $(NPM) install
@echo "  ✓ Dependencias del frontend instaladas"

frontend-dev:
@echo "→ Levantando servidor de desarrollo Next.js en http://localhost:3000 ..."
cd $(FRONTEND_DIR) && $(NPM) run dev

frontend-test:
@echo "→ Ejecutando suite de pruebas del frontend..."
cd $(FRONTEND_DIR) && $(NPM) test
