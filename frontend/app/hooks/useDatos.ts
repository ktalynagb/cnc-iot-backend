"use client";

import { useEffect, useState } from "react";
import type { LecturaSalida } from "../types";

const API_BASE = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:8000";
const MAX_CHART_READINGS = 60; // keep the last 60 readings for the chart

export function useDatos() {
  const [data, setData] = useState<LecturaSalida[]>([]);
  const [latest, setLatest] = useState<LecturaSalida | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;

    const fetchData = async () => {
      try {
        const res = await fetch(`${API_BASE}/datos?limit=${MAX_CHART_READINGS}`);
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const json: LecturaSalida[] = await res.json();
        if (cancelled) return;
        // API returns newest-first; reverse so charts show time left→right
        const sorted = [...json].reverse();
        setData(sorted);
        setLatest(sorted[sorted.length - 1] ?? null);
        setError(null);
      } catch (err) {
        if (!cancelled) setError((err as Error).message);
      }
    };

    fetchData();
    const id = setInterval(fetchData, 1000);
    return () => {
      cancelled = true;
      clearInterval(id);
    };
  }, []);

  return { data, latest, error };
}
