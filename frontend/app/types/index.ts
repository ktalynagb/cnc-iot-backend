export interface LecturaSalida {
  id: number;
  timestamp: string;
  temperatura: number;
  humedad: number;
  accel_x: number;
  accel_y: number;
  accel_z: number;
  vibracion_total: number;
  alerta: boolean;
  motivo_alerta: string | null;
}

export interface AlertaSalida {
  id: number;
  timestamp: string;
  temperatura: number;
  humedad: number;
  vibracion_total: number;
  motivo_alerta: string;
}
