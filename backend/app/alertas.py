from typing import Optional, Tuple
import math
from app.config import settings


def calcular_vibracion(ax: float, ay: float, az: float) -> float:
    """Magnitud del vector de aceleración en m/s²."""
    return round(math.sqrt(ax**2 + ay**2 + az**2), 4)


def evaluar_alerta(temperatura: float, humedad: float, vibracion: float) -> Tuple[bool, Optional[str]]:
    """
    Evalúa si los valores están fuera de los umbrales configurados.
    Retorna (hay_alerta, motivo).
    """
    motivos = []

    if temperatura < settings.TEMP_MIN:
        motivos.append(f"Temperatura baja ({temperatura}°C < {settings.TEMP_MIN}°C)")
    elif temperatura > settings.TEMP_MAX:
        motivos.append(f"Temperatura alta ({temperatura}°C > {settings.TEMP_MAX}°C)")

    if humedad < settings.HUM_MIN:
        motivos.append(f"Humedad baja ({humedad}% < {settings.HUM_MIN}%)")
    elif humedad > settings.HUM_MAX:
        motivos.append(f"Humedad alta ({humedad}% > {settings.HUM_MAX}%)")

    if vibracion > settings.ACCEL_MAX:
        motivos.append(f"Vibración alta ({vibracion} m/s² > {settings.ACCEL_MAX} m/s²)")

    if motivos:
        return True, " | ".join(motivos)
    return False, None
