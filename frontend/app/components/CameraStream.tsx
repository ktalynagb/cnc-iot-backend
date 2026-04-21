"use client";

import { useState } from "react";
import { Video, VideoOff } from "lucide-react";

const DEFAULT_STREAM_URL = process.env.NEXT_PUBLIC_CAM_URL ?? "http://192.168.1.100/stream";

export function CameraStream() {
  const [url, setUrl] = useState(DEFAULT_STREAM_URL);
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState(url);
  const [hasError, setHasError] = useState(false);

  const handleSave = () => {
    // Only allow http/https URLs to prevent javascript: URI injection
    try {
      const parsed = new URL(draft);
      if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
        return;
      }
    } catch {
      return;
    }
    setUrl(draft);
    setHasError(false);
    setEditing(false);
  };

  return (
    <div className="bg-white rounded-2xl border border-slate-200 shadow-sm p-5 flex flex-col gap-3">
      <div className="flex items-center justify-between">
        <h3 className="text-sm font-semibold text-slate-600 uppercase tracking-wide flex items-center gap-2">
          <Video className="w-4 h-4 text-indigo-500" />
          Cámara ESP32-CAM
        </h3>
        <button
          onClick={() => setEditing((v) => !v)}
          className="text-xs text-indigo-500 hover:underline"
        >
          {editing ? "Cancelar" : "Cambiar URL"}
        </button>
      </div>

      {editing && (
        <div className="flex gap-2">
          <input
            type="text"
            value={draft}
            onChange={(e) => setDraft(e.target.value)}
            className="flex-1 rounded-lg border border-slate-300 px-3 py-1.5 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400"
            placeholder="http://192.168.x.x/stream"
          />
          <button
            onClick={handleSave}
            className="rounded-lg bg-indigo-500 text-white px-3 py-1.5 text-sm hover:bg-indigo-600"
          >
            OK
          </button>
        </div>
      )}

      <div className="relative aspect-video bg-slate-100 rounded-xl overflow-hidden">
        {hasError ? (
          <div className="absolute inset-0 flex flex-col items-center justify-center gap-2 text-slate-400">
            <VideoOff className="w-10 h-10" />
            <span className="text-sm">Stream no disponible</span>
            <span className="text-xs break-all px-4 text-center">{url}</span>
          </div>
        ) : (
          // eslint-disable-next-line @next/next/no-img-element
          <img
            src={url}
            alt="MJPEG stream ESP32-CAM"
            className="w-full h-full object-cover"
            onError={() => setHasError(true)}
          />
        )}
      </div>
    </div>
  );
}
