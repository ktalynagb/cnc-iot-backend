"use client";

import { AlertTriangle } from "lucide-react";
import type { AlertaSalida } from "../types";

interface AlertsPanelProps {
  alertas: AlertaSalida[];
}

function formatTs(ts: string) {
  return new Date(ts).toLocaleString([], {
    month: "short",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  });
}

export function AlertsPanel({ alertas }: AlertsPanelProps) {
  return (
    <div className="bg-white rounded-2xl border border-slate-200 shadow-sm p-5 flex flex-col gap-3">
      <h3 className="text-sm font-semibold text-slate-600 uppercase tracking-wide flex items-center gap-2">
        <AlertTriangle className="w-4 h-4 text-amber-500" />
        Alertas recientes
      </h3>

      {alertas.length === 0 ? (
        <p className="text-slate-400 text-sm">Sin alertas activas ✅</p>
      ) : (
        <ul className="flex flex-col gap-2 max-h-64 overflow-y-auto">
          {alertas.map((a) => (
            <li
              key={a.id}
              className="rounded-xl border border-red-200 bg-red-50 px-4 py-2 text-sm"
            >
              <p className="font-semibold text-red-700">{a.motivo_alerta}</p>
              <p className="text-red-400 text-xs mt-0.5">
                {formatTs(a.timestamp)} · T:{a.temperatura.toFixed(1)}°C ·
                Hum:{a.humedad.toFixed(0)}% · Vib:{a.vibracion_total.toFixed(2)} m/s²
              </p>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
