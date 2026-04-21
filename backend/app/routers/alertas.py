from typing import List

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.lectura import Lectura
from app.schemas.lectura import AlertaSalida

router = APIRouter(prefix="/alertas", tags=["Alertas"])


@router.get("/", response_model=List[AlertaSalida])
def obtener_alertas(
    limit: int = Query(50, ge=1, le=500, description="Número máximo de alertas"),
    db: Session = Depends(get_db),
):
    """
    **BE-3** — Retorna solo las lecturas con alerta activa, más recientes primero.
    """
    alertas = (
        db.query(Lectura)
        .filter(Lectura.alerta == True)
        .order_by(Lectura.timestamp.desc())
        .limit(limit)
        .all()
    )
    return alertas
