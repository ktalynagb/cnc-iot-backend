from typing import Optional
from datetime import datetime
from sqlalchemy import Float, DateTime, Boolean, Integer
from sqlalchemy.orm import Mapped, mapped_column
from app.database import Base


class Lectura(Base):
    __tablename__ = "lecturas"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    timestamp: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, index=True)

    # DHT22
    temperatura: Mapped[float] = mapped_column(Float, nullable=False)
    humedad: Mapped[float] = mapped_column(Float, nullable=False)

    # MPU-6050
    accel_x: Mapped[float] = mapped_column(Float, nullable=False)
    accel_y: Mapped[float] = mapped_column(Float, nullable=False)
    accel_z: Mapped[float] = mapped_column(Float, nullable=False)

    # Calculado en el servidor
    vibracion_total: Mapped[float] = mapped_column(Float, nullable=False)

    # Alertas
    alerta: Mapped[bool] = mapped_column(Boolean, default=False)
    motivo_alerta: Mapped[Optional[str]] = mapped_column(nullable=True)
