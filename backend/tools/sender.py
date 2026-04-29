import customtkinter as ctk
import requests
import json
import random
import threading
import time
from datetime import datetime

# Configuración de apariencia moderna
ctk.set_appearance_mode("Dark")  # Opciones: "System", "Dark", "Light"
ctk.set_default_color_theme("blue")

class CNCSimulator(ctk.CTk):
    def __init__(self):
        super().__init__()

        self.title("CNC IoT - Simulador de Sensores")
        self.geometry("450x700")
        self.resizable(False, False)

        self.is_auto_sending = False
        
        # --- Variables de control ---
        self.mode_var = ctk.StringVar(value="constante")
        
        self.build_ui()

    def build_ui(self):
        # --- Sección URL ---
        self.frame_url = ctk.CTkFrame(self)
        self.frame_url.pack(pady=10, padx=20, fill="x")
        
        ctk.CTkLabel(self.frame_url, text="Backend URL:", font=ctk.CTkFont(weight="bold")).pack(anchor="w", padx=10, pady=(10,0))
        self.entry_url = ctk.CTkEntry(self.frame_url)
        self.entry_url.insert(0, "http://104.43.141.110/datos/")
        self.entry_url.pack(padx=10, pady=10, fill="x")

        # --- Sección de Modo ---
        self.frame_mode = ctk.CTkFrame(self)
        self.frame_mode.pack(pady=10, padx=20, fill="x")
        
        ctk.CTkLabel(self.frame_mode, text="Modo de Envío:", font=ctk.CTkFont(weight="bold")).pack(anchor="w", padx=10, pady=(10,0))
        
        self.radio_const = ctk.CTkRadioButton(self.frame_mode, text="Valores Constantes", variable=self.mode_var, value="constante", command=self.toggle_inputs)
        self.radio_const.pack(side="left", padx=20, pady=10)
        
        self.radio_rand = ctk.CTkRadioButton(self.frame_mode, text="Valores Aleatorios", variable=self.mode_var, value="aleatorio", command=self.toggle_inputs)
        self.radio_rand.pack(side="left", padx=20, pady=10)

        # --- Sección de Sensores ---
        self.frame_sensors = ctk.CTkFrame(self)
        self.frame_sensors.pack(pady=10, padx=20, fill="x")
        
        self.entries = {}
        defaults = {"temperatura": "28.5", "humedad": "50.0", "accel_x": "0.12", "accel_y": "-0.03", "accel_z": "9.81"}
        
        for key, val in defaults.items():
            row = ctk.CTkFrame(self.frame_sensors, fg_color="transparent")
            row.pack(fill="x", padx=10, pady=5)
            ctk.CTkLabel(row, text=f"{key.capitalize()}:", width=100, anchor="w").pack(side="left")
            entry = ctk.CTkEntry(row)
            entry.insert(0, val)
            entry.pack(side="right", fill="x", expand=True)
            self.entries[key] = entry

        # --- Botones de Acción ---
        self.frame_buttons = ctk.CTkFrame(self, fg_color="transparent")
        self.frame_buttons.pack(pady=10, padx=20, fill="x")

        self.btn_send_once = ctk.CTkButton(self.frame_buttons, text="Enviar Una Vez", command=self.send_data_thread)
        self.btn_send_once.pack(side="left", expand=True, padx=5)

        self.btn_auto = ctk.CTkButton(self.frame_buttons, text="Iniciar Auto-Envío (2s)", fg_color="green", hover_color="darkgreen", command=self.toggle_auto_send)
        self.btn_auto.pack(side="right", expand=True, padx=5)

        # --- Consola de Log ---
        ctk.CTkLabel(self, text="Registro de Eventos:", font=ctk.CTkFont(weight="bold")).pack(anchor="w", padx=20)
        self.textbox_log = ctk.CTkTextbox(self, height=150)
        self.textbox_log.pack(padx=20, pady=(0,20), fill="both", expand=True)

    def log(self, message):
        timestamp = datetime.now().strftime("%H:%M:%S")
        self.textbox_log.insert("end", f"[{timestamp}] {message}\n")
        self.textbox_log.see("end")

    def toggle_inputs(self):
        state = "normal" if self.mode_var.get() == "constante" else "disabled"
        for entry in self.entries.values():
            entry.configure(state=state)

    def get_payload(self):
        if self.mode_var.get() == "constante":
            try:
                return {k: float(v.get()) for k, v in self.entries.items()}
            except ValueError:
                self.log("⚠️ Error: Todos los campos deben ser números válidos.")
                return None
        else:
            # Generar datos aleatorios realistas
            return {
                "temperatura": round(random.uniform(25.0, 45.0), 2),
                "humedad": round(random.uniform(40.0, 70.0), 2),
                "accel_x": round(random.uniform(-2.0, 2.0), 4),
                "accel_y": round(random.uniform(-2.0, 2.0), 4),
                "accel_z": round(random.uniform(-2.0, 2.0), 4) # Gravedad +- vibración
            }

    def send_data(self):
        payload = self.get_payload()
        if not payload: return

        url = self.entry_url.get().strip()
        try:
            res = requests.post(url, json=payload, timeout=3)
            if res.status_code in (200, 201):
                self.log(f"✅ Enviado: T:{payload['temperatura']} | Hum:{payload['humedad']} | Ax:{payload['accel_x']}")
            else:
                self.log(f"❌ Error HTTP {res.status_code}: {res.text}")
        except Exception as e:
            self.log(f"🚨 Error de conexión: {str(e)}")

    def send_data_thread(self):
        # Ejecutar en hilo para no congelar la UI
        threading.Thread(target=self.send_data, daemon=True).start()

    def toggle_auto_send(self):
        if self.is_auto_sending:
            self.is_auto_sending = False
            self.btn_auto.configure(text="Iniciar Auto-Envío (2s)", fg_color="green", hover_color="darkgreen")
            self.btn_send_once.configure(state="normal")
            self.log("⏸️ Auto-envío detenido.")
        else:
            self.is_auto_sending = True
            self.btn_auto.configure(text="Detener Auto-Envío", fg_color="red", hover_color="darkred")
            self.btn_send_once.configure(state="disabled")
            self.log("▶️ Auto-envío iniciado...")
            threading.Thread(target=self.auto_send_loop, daemon=True).start()

    def auto_send_loop(self):
        while self.is_auto_sending:
            self.send_data()
            time.sleep(2) # Envia datos cada 2 segundos

if __name__ == "__main__":
    app = CNCSimulator()
    app.mainloop()