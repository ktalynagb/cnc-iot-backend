import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "CNC Monitor — Monitoreo en Tiempo Real",
  description: "Dashboard de monitoreo de vibración y temperatura para máquina CNC",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="es" className="h-full antialiased">
      <body className="min-h-full flex flex-col">{children}</body>
    </html>
  );
}
