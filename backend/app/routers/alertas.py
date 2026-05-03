from typing import List

from fastapi import APIRouter, HTTPException, Query

from app.database import get_query_api, fila_a_lectura, INFLUX_BUCKET, INFLUX_ORG
from app.schemas.lectura import LecturaSalida

router = APIRouter(prefix="/datos/alertas", tags=["Alertas"])


@router.get("/", response_model=List[LecturaSalida])
def obtener_alertas(
    limit: int = Query(50, ge=1, le=500, description="Número máximo de alertas"),
):
    """
    **BE-5** — Retorna solo las lecturas con alerta activa, más recientes primero.
    """
    query_api = get_query_api()

    flux_query = f"""
        from(bucket: "{INFLUX_BUCKET}")
          |> range(start: -7d)
          |> filter(fn: (r) => r._measurement == "cnc_sensores")
          |> pivot(
               rowKey: ["_time"],
               columnKey: ["_field"],
               valueColumn: "_value"
             )
          |> filter(fn: (r) => r.alerta == true)
          |> sort(columns: ["_time"], desc: true)
          |> limit(n: {limit})
    """

    try:
        tablas = query_api.query(flux_query, org=INFLUX_ORG)
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"Error consultando InfluxDB: {e}")

    alertas = []
    for tabla in tablas:
        for record in tabla.records:
            alertas.append(fila_a_lectura(record))

    return alertas
