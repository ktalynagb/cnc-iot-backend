import json
import random
import time
import signal
import sys
import paho.mqtt.client as mqtt

MQTT_BROKER = "74.249.204.133"
MQTT_PORT = 1883
MQTT_USER = "flux_user"
MQTT_PASSWORD = "flux_pass"

TOPIC_DATA = "flux/cnc1/datos"
INTERVALO = 5  # segundos

running = True

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

def conectar():
    client = mqtt.Client()
    client.username_pw_set(MQTT_USER, MQTT_PASSWORD)
    client.connect(MQTT_BROKER, MQTT_PORT, 60)
    return client

def publicar_loop():
    client = conectar()
    print(f"Conectado a {MQTT_BROKER}:{MQTT_PORT}")

    try:
        while running:
            data = generar_datos()
            payload = json.dumps(data)

            result = client.publish(TOPIC_DATA, payload, qos=1)
            if result.rc != mqtt.MQTT_ERR_SUCCESS:
                print(f"Error publicando: rc={result.rc}")
            else:
                print("Enviado:")
                print(payload)
                print("-" * 50)

            time.sleep(INTERVALO)

    except KeyboardInterrupt:
        print("\nInterrumpido por teclado.")
    finally:
        try:
            client.disconnect()
        except Exception:
            pass
        print("Sender detenido.")

if __name__ == "__main__":
    publicar_loop()