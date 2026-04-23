"use client";

import { Thermometer, Droplets, Activity, Wifi, WifiOff } from "lucide-react";
import { useDatos } from "./hooks/useDatos";
import { useAlertas } from "./hooks/useAlertas";
import { KpiCard } from "./components/KpiCard";
import { MetricChart } from "./components/MetricChart";
import { AlertsPanel } from "./components/AlertsPanel";
import { CameraStream } from "./components/CameraStream";

export default function Dashboard() {
  const { data, latest, error: dataError } = useDatos();
  const { alertas, error: alertasError } = useAlertas();

  const isConnected = !dataError;

  return (
    <div className="min-h-screen bg-slate-50 text-slate-900">
      {/* ── Header ── */}
      <header className="bg-white border-b border-slate-200 px-6 py-4 flex items-center justify-between">
        <div>
          <h1 className="text-xl font-bold tracking-tight">🏭 CNC Monitor</h1>
          <p className="text-xs text-slate-400">
            Monitoreo en tiempo real · Universidad Autónoma de Occidente
          </p>
        </div>
        <div className="flex items-center gap-2 text-sm">
          {isConnected ? (
            <>
              <Wifi className="w-4 h-4 text-emerald-500" />
              <span className="text-emerald-600 font-medium">Conectado</span>
            </>
          ) : (
            <>
              <WifiOff className="w-4 h-4 text-red-400" />
              <span className="text-red-500 font-medium">Sin conexión</span>
            </>
          )}
        </div>
      </header>

      <main className="max-w-7xl mx-auto px-4 py-6 grid gap-6">
        {/* ── KPI Cards ── */}
        <section className="grid grid-cols-1 sm:grid-cols-3 gap-4">
          <KpiCard
            label="Temperatura"
            value={latest ? latest.temperatura.toFixed(1) : "—"}
            unit="°C"
            Icon={Thermometer}
            alert={!!latest?.motivo_alerta?.includes("Temperatura")}
          />
          <KpiCard
            label="Humedad"
            value={latest ? latest.humedad.toFixed(0) : "—"}
            unit="%"
            Icon={Droplets}
            alert={!!latest?.motivo_alerta?.includes("Humedad")}
          />
          <KpiCard
            label="Vibración"
            value={latest ? latest.vibracion_total.toFixed(3) : "—"}
            unit="m/s²"
            Icon={Activity}
            alert={!!latest?.motivo_alerta?.includes("Vibración")}
          />
        </section>

        {/* ── Camera + Alerts ── */}
        <section className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <CameraStream />
          <AlertsPanel alertas={alertas} />
        </section>

        {/* ── Charts ── */}
        <section className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-6">
          <MetricChart
            data={data}
            dataKey="temperatura"
            label="Temperatura"
            color="#f97316"
            unit="°C"
            domain={[10, 50]}
          />
          <MetricChart
            data={data}
            dataKey="humedad"
            label="Humedad"
            color="#0ea5e9"
            unit="%"
            domain={[0, 100]}
          />
          <MetricChart
            data={data}
            dataKey="vibracion_total"
            label="Vibración Total"
            color="#8b5cf6"
            unit=" m/s²"
          />
          <MetricChart
            data={data}
            dataKey="accel_x"
            label="Aceleración X"
            color="#10b981"
            unit=" m/s²"
          />
          <MetricChart
            data={data}
            dataKey="accel_y"
            label="Aceleración Y"
            color="#f43f5e"
            unit=" m/s²"
          />
          <MetricChart
            data={data}
            dataKey="accel_z"
            label="Aceleración Z"
            color="#eab308"
            unit=" m/s²"
          />
        </section>

        {/* ── Connection error banner ── */}
        {(dataError || alertasError) && (
          <div className="rounded-xl bg-red-50 border border-red-200 px-5 py-3 text-sm text-red-600">
            ⚠️ Error de conexión:{" "}
            {dataError ?? alertasError} — reintentando cada segundo…
          </div>
        )}
      </main>
    </div>
  );
}
