import csv
import os
import threading
from datetime import datetime
from pathlib import Path

from app.config import settings

_lock = threading.Lock()
_CSV_HEADERS = [
    "id", "timestamp", "temperatura",
    "accel_x", "accel_y", "accel_z", "vibracion_total",
    "alerta", "motivo_alerta",
]


def _ensure_file(path: Path) -> None:
    """Crea el archivo CSV con encabezados si no existe."""
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists():
        with open(path, "w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=_CSV_HEADERS)
            writer.writeheader()


def guardar_lectura_csv(lectura) -> None:
    """
    Escribe una fila en el CSV de forma thread-safe.
    `lectura` es una instancia del modelo SQLAlchemy Lectura.
    """
    path = Path(settings.CSV_PATH)
    row = {
        "id": lectura.id,
        "timestamp": lectura.timestamp.isoformat(),
        "temperatura": lectura.temperatura,
        "accel_x": lectura.accel_x,
        "accel_y": lectura.accel_y,
        "accel_z": lectura.accel_z,
        "vibracion_total": lectura.vibracion_total,
        "alerta": lectura.alerta,
        "motivo_alerta": lectura.motivo_alerta or "",
    }
    with _lock:
        _ensure_file(path)
        with open(path, "a", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=_CSV_HEADERS)
            writer.writerow(row)
