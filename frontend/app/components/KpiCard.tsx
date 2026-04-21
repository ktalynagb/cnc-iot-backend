import type { LucideIcon } from "lucide-react";

interface KpiCardProps {
  label: string;
  value: string | number;
  unit: string;
  Icon: LucideIcon;
  alert?: boolean;
}

export function KpiCard({ label, value, unit, Icon, alert }: KpiCardProps) {
  return (
    <div
      className={`rounded-2xl p-5 flex items-center gap-4 shadow-sm border ${
        alert
          ? "bg-red-50 border-red-300 text-red-700"
          : "bg-white border-slate-200 text-slate-700"
      }`}
    >
      <div
        className={`rounded-xl p-3 ${
          alert ? "bg-red-100" : "bg-indigo-50"
        }`}
      >
        <Icon
          className={`w-7 h-7 ${alert ? "text-red-500" : "text-indigo-500"}`}
        />
      </div>
      <div>
        <p className="text-xs font-medium uppercase tracking-wide opacity-60">
          {label}
        </p>
        <p className="text-3xl font-bold leading-tight">
          {value}
          <span className="text-base font-normal ml-1 opacity-70">{unit}</span>
        </p>
      </div>
    </div>
  );
}
