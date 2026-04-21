"""
Pruebas de integración para los endpoints de datos y alertas.
Usa una BD SQLite en memoria para no depender de PostgreSQL.

Correr con:  make test
"""
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

# Parchamos el engine ANTES de importar app para evitar conexión a PostgreSQL
import app.database as db_module

TEST_DB_URL = "sqlite:///./test_temp.db"
engine_test = create_engine(TEST_DB_URL, connect_args={"check_same_thread": False})
db_module.engine = engine_test
db_module.SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine_test)

from app.database import Base, get_db  # noqa: E402
from app.main import app  # noqa: E402

Base.metadata.create_all(bind=engine_test)


def override_get_db():
    db = db_module.SessionLocal()
    try:
        yield db
    finally:
        db.close()


app.dependency_overrides[get_db] = override_get_db
client = TestClient(app)

PAYLOAD_NORMAL = {
    "temperatura": 28.5,
    "accel_x": 0.12,
    "accel_y": -0.03,
    "accel_z": 0.05,   # vibración baja — dentro del umbral de 2.0 m/s²
}

PAYLOAD_ALERTA = {
    "temperatura": 60.0,   # fuera de rango
    "accel_x": 5.0,
    "accel_y": 5.0,
    "accel_z": 5.0,         # vibración alta
}


def test_health_check():
    r = client.get("/")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"


def test_post_datos_normal():
    r = client.post("/datos/", json=PAYLOAD_NORMAL)
    assert r.status_code == 201
    data = r.json()
    assert data["temperatura"] == 28.5
    assert data["alerta"] is False
    assert data["motivo_alerta"] is None
    assert "vibracion_total" in data
    assert "timestamp" in data


def test_post_datos_con_alerta():
    r = client.post("/datos/", json=PAYLOAD_ALERTA)
    assert r.status_code == 201
    data = r.json()
    assert data["alerta"] is True
    assert data["motivo_alerta"] is not None


def test_get_datos():
    r = client.get("/datos/")
    assert r.status_code == 200
    assert isinstance(r.json(), list)
    assert len(r.json()) >= 1


def test_get_alertas():
    r = client.get("/alertas/")
    assert r.status_code == 200
    alertas = r.json()
    assert isinstance(alertas, list)
    # Todas deben tener alerta = True (implícito por el endpoint)
    for a in alertas:
        assert a["motivo_alerta"] is not None


def test_payload_invalido():
    r = client.post("/datos/", json={"temperatura": "no_es_numero"})
    assert r.status_code == 422
