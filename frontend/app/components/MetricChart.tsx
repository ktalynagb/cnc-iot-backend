"use client";

import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
} from "recharts";
import type { LecturaSalida } from "../types";

interface MetricChartProps {
  data: LecturaSalida[];
  dataKey: keyof LecturaSalida;
  label: string;
  color: string;
  unit: string;
  domain?: [number | "auto", number | "auto"];
}

function formatTime(ts: string) {
  const d = new Date(ts);
  return d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" });
}

export function MetricChart({
  data,
  dataKey,
  label,
  color,
  unit,
  domain = ["auto", "auto"],
}: MetricChartProps) {
  const chartData = data.map((d) => ({
    time: formatTime(d.timestamp),
    value: d[dataKey] as number,
  }));

  return (
    <div className="bg-white rounded-2xl border border-slate-200 shadow-sm p-5">
      <h3 className="text-sm font-semibold text-slate-600 mb-4 uppercase tracking-wide">
        {label}
      </h3>
      <ResponsiveContainer width="100%" height={200}>
        <LineChart data={chartData} margin={{ top: 4, right: 8, bottom: 4, left: 0 }}>
          <CartesianGrid strokeDasharray="3 3" stroke="#f0f0f0" />
          <XAxis
            dataKey="time"
            tick={{ fontSize: 10, fill: "#94a3b8" }}
            interval="preserveStartEnd"
            tickLine={false}
          />
          <YAxis
            domain={domain}
            tick={{ fontSize: 10, fill: "#94a3b8" }}
            tickLine={false}
            axisLine={false}
            unit={unit}
            width={48}
          />
          <Tooltip
            contentStyle={{ fontSize: 12, borderRadius: 8 }}
            formatter={(v) => [`${v} ${unit}`, label]}
          />
          <Line
            type="monotone"
            dataKey="value"
            stroke={color}
            strokeWidth={2}
            dot={false}
            isAnimationActive={false}
          />
        </LineChart>
      </ResponsiveContainer>
    </div>
  );
}
