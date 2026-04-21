from datetime import datetime, timezone
from typing import List

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.lectura import Lectura
from app.schemas.lectura import LecturaEntrada, LecturaSalida
from app.alertas import calcular_vibracion, evaluar_alerta
from app.csv_writer import guardar_lectura_csv

router = APIRouter(prefix="/datos", tags=["Datos"])


@router.post("/", response_model=LecturaSalida, status_code=201)
def recibir_datos(payload: LecturaEntrada, db: Session = Depends(get_db)):
    """
    **BE-2** — Recibe lectura del ESP32, la evalúa y la almacena en BD y CSV.
    """
    vibracion = calcular_vibracion(payload.accel_x, payload.accel_y, payload.accel_z)
    alerta, motivo = evaluar_alerta(payload.temperatura, payload.humedad, vibracion)

    lectura = Lectura(
        timestamp=datetime.now(timezone.utc),
        temperatura=payload.temperatura,
        accel_x=payload.accel_x,
        accel_y=payload.accel_y,
        accel_z=payload.accel_z,
        vibracion_total=vibracion,
        alerta=alerta,
        motivo_alerta=motivo,
    )
    db.add(lectura)
    db.commit()
    db.refresh(lectura)

    # BE-4 — Guardar en CSV
    guardar_lectura_csv(lectura)

    return lectura


@router.get("/", response_model=List[LecturaSalida])
def obtener_datos(
    limit: int = Query(100, ge=1, le=1000, description="Número máximo de registros"),
    db: Session = Depends(get_db),
):
    """
    **BE-3** — Retorna las últimas `limit` lecturas, más recientes primero.
    """
    lecturas = (
        db.query(Lectura)
        .order_by(Lectura.timestamp.desc())
        .limit(limit)
        .all()
    )
    return lecturas
