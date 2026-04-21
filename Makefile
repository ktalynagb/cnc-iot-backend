# ============================================================
#  CNC IoT Backend — Makefile
#  Uso: make <comando>
# ============================================================

PYTHON     := python3
PIP        := pip3
UVICORN    := uvicorn
APP        := app.main:app
ENV_FILE   := .env
VENV       := .venv

ifeq ($(OS),Windows_NT)
	VENV_BIN := $(VENV)/Scripts
else
	VENV_BIN := $(VENV)/bin
endif

DB_NAME    := cnc_iot
DB_USER    := cnc_user

.PHONY: help setup venv install env db-create db-drop db-reset \
        run dev lint test clean logs

# ------------------------------------------------------------
# AYUDA
# ------------------------------------------------------------
help:
	@echo ""
	@echo "  🏭  CNC IoT Backend — comandos disponibles"
	@echo ""
	@echo "  CONFIGURACIÓN INICIAL"
	@echo "    make setup      — Todo desde cero (venv + deps + .env + BD)"
	@echo "    make venv       — Crear entorno virtual"
	@echo "    make install    — Instalar dependencias en el venv"
	@echo "    make env        — Copiar .env.example → .env"
	@echo ""
	@echo "  BASE DE DATOS"
	@echo "    make db-create  — Crear usuario y BD en PostgreSQL"
	@echo "    make db-drop    — Eliminar BD (¡cuidado!)"
	@echo "    make db-reset   — drop + create (datos frescos)"
	@echo ""
	@echo "  SERVIDOR"
	@echo "    make run        — Levantar servidor en producción (puerto 8000)"
	@echo "    make dev        — Levantar servidor con hot-reload"
	@echo ""
	@echo "  CALIDAD"
	@echo "    make lint       — Revisar estilo de código"
	@echo "    make test       — Correr tests"
	@echo ""
	@echo "  UTILIDADES"
	@echo "    make logs       — Ver las últimas 50 líneas del CSV"
	@echo "    make clean      — Borrar caché Python y CSV de pruebas"
	@echo ""

# ------------------------------------------------------------
# CONFIGURACIÓN INICIAL
# ------------------------------------------------------------
setup: venv install env db-create
	@echo ""
	@echo "  ✅  Setup completo. Edita .env con tu contraseña de BD."
	@echo "      Luego corre:  make run"

venv:
	@echo "→ Creando entorno virtual..."
	$(PYTHON) -m venv $(VENV)
	@echo "  ✓ Entorno virtual listo en $(VENV)/"

install: venv
	@echo "→ Instalando dependencias..."
	$(VENV_BIN)/pip install --upgrade pip -q
	$(VENV_BIN)/pip install -r requirements.txt -q
	@echo "  ✓ Dependencias instaladas"

env:
	@if [ ! -f $(ENV_FILE) ]; then \
		cp .env.example $(ENV_FILE); \
		echo "  ✓ .env creado — edítalo con tu contraseña"; \
	else \
		echo "  ⚠  .env ya existe, no se sobreescribe"; \
	fi

# ------------------------------------------------------------
# BASE DE DATOS
# ------------------------------------------------------------
db-create:
	@echo "→ Creando usuario '$(DB_USER)' y base de datos '$(DB_NAME)'..."
	@sudo -u postgres psql -c "CREATE USER $(DB_USER) WITH PASSWORD 'cambia_esta_password';" 2>/dev/null || true
	@sudo -u postgres psql -c "CREATE DATABASE $(DB_NAME) OWNER $(DB_USER);" 2>/dev/null || true
	@sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $(DB_NAME) TO $(DB_USER);" 2>/dev/null || true
	@echo "  ✓ BD lista. Recuerda actualizar DB_PASSWORD en .env"

db-drop:
	@echo "→ Eliminando base de datos '$(DB_NAME)'..."
	@sudo -u postgres psql -c "DROP DATABASE IF EXISTS $(DB_NAME);"
	@sudo -u postgres psql -c "DROP USER IF EXISTS $(DB_USER);"
	@echo "  ✓ BD eliminada"

db-reset: db-drop db-create
	@echo "  ✓ BD recreada desde cero"

# ------------------------------------------------------------
# SERVIDOR
# ------------------------------------------------------------
run:
	@echo "→ Iniciando servidor en http://0.0.0.0:8000 ..."
	$(VENV_BIN)/uvicorn $(APP) --host 0.0.0.0 --port 8000

dev:
	@echo "→ Iniciando servidor con hot-reload en http://localhost:8000 ..."
	@echo "   Docs: http://localhost:8000/docs"
	$(VENV_BIN)/uvicorn $(APP) --host 0.0.0.0 --port 8000 --reload

# ------------------------------------------------------------
# CALIDAD
# ------------------------------------------------------------
lint:
	@echo "→ Revisando código con ruff..."
	@$(VENV_BIN)/pip install ruff -q
	$(VENV_BIN)/ruff check app/

test:
	@echo "→ Corriendo tests..."
	@$(VENV_BIN)/pip install httpx pytest pytest-asyncio -q
	$(VENV_BIN)/pytest tests/ -v

# ------------------------------------------------------------
# UTILIDADES
# ------------------------------------------------------------
logs:
	@echo "→ Últimas 50 filas del CSV:"
	@tail -n 50 data/lecturas.csv 2>/dev/null || echo "  ⚠  CSV no encontrado aún"

clean:
	@echo "→ Limpiando caché..."
	find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	find . -name "*.pyc" -delete 2>/dev/null || true
	@echo "  ✓ Limpio"
