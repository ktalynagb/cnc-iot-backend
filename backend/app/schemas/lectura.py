from typing import Optional
from datetime import datetime
from pydantic import BaseModel, Field


class LecturaEntrada(BaseModel):
    """JSON que envía el ESP32."""
    temperatura: float = Field(..., ge=-40, le=80, description="°C — DHT22")
    accel_x: float = Field(..., description="m/s² eje X — MPU-6050")
    accel_y: float = Field(..., description="m/s² eje Y — MPU-6050")
    accel_z: float = Field(..., description="m/s² eje Z — MPU-6050")

    model_config = {
        "json_schema_extra": {
            "example": {
                "temperatura": 28.5,
                "accel_x": 0.12,
                "accel_y": -0.03,
                "accel_z": 9.81,
            }
        }
    }


class LecturaSalida(BaseModel):
    """Respuesta completa con datos calculados por el servidor."""
    id: int
    timestamp: datetime
    temperatura: float
    humedad: float
    accel_x: float
    accel_y: float
    accel_z: float
    vibracion_total: float
    alerta: bool
    motivo_alerta: Optional[str]

    model_config = {"from_attributes": True}


class AlertaSalida(BaseModel):
    """Solo lecturas con alerta activa."""
    id: int
    timestamp: datetime
    temperatura: float
    humedad: float
    vibracion_total: float
    motivo_alerta: str

    model_config = {"from_attributes": True}
