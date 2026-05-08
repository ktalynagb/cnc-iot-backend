#!/usr/bin/env python3
"""
Robust MQTT sender para pruebas.
Lectura de configuración por ENV vars:
  MQTT_BROKER, MQTT_PORT, MQTT_USER, MQTT_PASSWORD, INTERVALO
Soporta reconexión automática y backoff.
"""
import os
import json
import random
import time
import signal
import sys
import traceback

import paho.mqtt.client as mqtt

# Config desde ENV o valores por defecto
MQTT_BROKER = os.getenv("MQTT_BROKER", "132.196.59.198")
MQTT_PORT = int(os.getenv("MQTT_PORT", "1883"))
MQTT_USER = os.getenv("MQTT_USER", "flux_user")
MQTT_PASSWORD = os.getenv("MQTT_PASSWORD", "flux_pass")

TOPIC_DATA = os.getenv("TOPIC_DATA", "flux/cnc1/datos")
INTERVALO = int(os.getenv("INTERVALO", "5"))

# Reconexion/backoff
MAX_RECONNECT_ATTEMPTS = 10
BASE_BACKOFF = 2  # segundos

running = True
connected = False

def stop_handler(sig, frame):
    global running
    running = False
    print("\nDeteniendo sender...")

signal.signal(signal.SIGINT, stop_handler)
signal.signal(signal.SIGTERM, stop_handler)

def generar_datos():
    return {
        "temperatura": round(random.uniform(20.0, 45.0), 2),
        "humedad": round(random.uniform(30.0, 80.0), 2),
        "accel_x": round(random.uniform(-2.0, 2.0), 4),
        "accel_y": round(random.uniform(-2.0, 2.0), 4),
        "accel_z": round(random.uniform(-2.0, 2.0), 4),
    }

def on_connect(client, userdata, flags, rc):
    global connected
    if rc == 0:
        connected = True
        print(f"[mqtt] Conectado correctamente a {MQTT_BROKER}:{MQTT_PORT}")
    else:
        connected = False
        print(f"[mqtt] Fallo al conectar, rc={rc}")

def on_disconnect(client, userdata, rc):
    global connected
    connected = False
    print(f"[mqtt] Desconectado, rc={rc}")

def crear_cliente():
    # Evitar warning de API deprecada usando protocolo explícito
    client = mqtt.Client(protocol=mqtt.MQTTv311)
    if MQTT_USER:
        client.username_pw_set(MQTT_USER, MQTT_PASSWORD)
    client.on_connect = on_connect
    client.on_disconnect = on_disconnect
    return client

def conectar_con_backoff(client):
    attempt = 0
    while running:
        try:
            print(f"[mqtt] Intentando conectar a {MQTT_BROKER}:{MQTT_PORT} (intento {attempt+1})...")
            client.connect(MQTT_BROKER, MQTT_PORT, keepalive=60)
            client.loop_start()
            # Esperar hasta on_connect marque connected o timeout
            wait = 0
            while wait < 10 and not connected and running:
                time.sleep(0.5)
                wait += 0.5
            if connected:
                return True
            else:
                raise RuntimeError("timeout esperando on_connect")
        except Exception as e:
            attempt += 1
            print(f"[mqtt] Error al conectar: {e}")
            traceback.print_exc()
            backoff = BASE_BACKOFF * (2 ** (attempt - 1))
            backoff = min(backoff, 60)
            print(f"[mqtt] Reintentando en {backoff}s (attempt={attempt}/{MAX_RECONNECT_ATTEMPTS})")
            time.sleep(backoff)
            if attempt >= MAX_RECONNECT_ATTEMPTS:
                print("[mqtt] Max reconnect attempts alcanzado. Abandonando.")
                return False
    return False

def publicar_loop():
    client = crear_cliente()
    if not conectar_con_backoff(client):
        print("[mqtt] No se pudo conectar al broker. Saliendo.")
        return

    try:
        while running:
            if not connected:
                print("[mqtt] No conectado; intentando reconectar...")
                try:
                    client.reconnect()
                except Exception:
                    # recreate client if reconnect fails
                    client.loop_stop(force=True)
                    client = crear_cliente()
                    if not conectar_con_backoff(client):
                        print("[mqtt] Reconexión fallida; espera antes de reintentar todo el ciclo.")
                        time.sleep(5)
                        continue

            data = generar_datos()
            payload = json.dumps(data)
            try:
                info = client.publish(TOPIC_DATA, payload, qos=1)
                # MQTTMessageInfo tiene rc; puede ser 0 si encolado localmente
                rc = getattr(info, "rc", None)
                if rc is None:
                    # en versiones antiguas info.wait_for_publish() puede bloquear
                    if hasattr(info, "wait_for_publish"):
                        info.wait_for_publish()
                    print("[mqtt] Enviado (info):", payload)
                elif rc != mqtt.MQTT_ERR_SUCCESS:
                    print(f"[mqtt] Error publicando: rc={rc}")
                else:
                    print("[mqtt] Enviado:", payload)
                print("-" * 50)
            except Exception as e:
                print("[mqtt] Excepción en publish:", e)
                traceback.print_exc()

            sleep_time = INTERVALO
            # permitir interrupciones en el sleep
            for _ in range(int(sleep_time*10)):
                if not running:
                    break
                time.sleep(0.1)

    except KeyboardInterrupt:
        print("\nInterrumpido por teclado.")
    finally:
        try:
            client.loop_stop()
            client.disconnect()
        except Exception:
            pass
        print("Sender detenido.")

if __name__ == "__main__":
    publicar_loop()