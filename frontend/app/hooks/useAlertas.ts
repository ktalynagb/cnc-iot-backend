"use client";

import { useEffect, useState } from "react";
import type { AlertaSalida } from "../types";

// In production the App Gateway proxies /datos/* to the backend, so relative
// paths work out of the box. Override with NEXT_PUBLIC_API_URL for local dev
// (e.g. http://localhost:8000).
const API_BASE = process.env.NEXT_PUBLIC_API_URL ?? "";

export function useAlertas() {
  const [alertas, setAlertas] = useState<AlertaSalida[]>([]);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;

    const fetchAlertas = async () => {
      try {
        const res = await fetch(`${API_BASE}/datos/alertas/?limit=20`);
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const json: AlertaSalida[] = await res.json();
        if (!cancelled) {
          setAlertas(json);
          setError(null);
        }
      } catch (err) {
        if (!cancelled) setError((err as Error).message);
      }
    };

    fetchAlertas();
    const id = setInterval(fetchAlertas, 1000);
    return () => {
      cancelled = true;
      clearInterval(id);
    };
  }, []);

  return { alertas, error };
}
