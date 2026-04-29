from datetime import datetime, timezone
from pathlib import Path
from typing import List

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.lectura import Lectura
from app.schemas.lectura import LecturaEntrada, LecturaSalida
from app.alertas import calcular_vibracion, evaluar_alerta
from app.config import settings
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
        humedad=payload.humedad,
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


@router.get("/descargar/", tags=["Datos"])
def descargar_csv():
    """
    **BE-5** — Sirve el archivo CSV de lecturas como descarga directa.
    El nombre del archivo incluye la fecha/hora de la descarga.
    """
    csv_path = Path(settings.CSV_PATH)
    if not csv_path.exists():
        raise HTTPException(status_code=404, detail="El archivo CSV no existe. Envía al menos una lectura primero.")

    timestamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    filename = f"lecturas_cnc_{timestamp}.csv"

    return FileResponse(
        path=str(csv_path),
        media_type="text/csv",
        filename=filename,
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )
