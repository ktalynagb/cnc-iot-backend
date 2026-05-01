import json
import random
import time
import paho.mqtt.client as mqtt

# Configuración
MQTT_BROKER = "52.165.194.217"   # cambia por tu IP pública de la VM front
MQTT_PORT = 1883
MQTT_USER = "flux_user"
MQTT_PASSWORD = "flux_pass"

TOPIC_TEMP = "flux/cnc1/temperatura"
TOPIC_HUM = "flux/cnc1/humedad"
TOPIC_VIB = "flux/cnc1/vibracion"

INTERVALO = 2  # segundos

def generar_datos():
    temperatura = round(random.uniform(20.0, 45.0), 2)
    humedad = round(random.uniform(30.0, 80.0), 2)
    accel_x = round(random.uniform(-2.0, 2.0), 4)
    accel_y = round(random.uniform(-2.0, 2.0), 4)
    accel_z = round(random.uniform(-2.0, 2.0), 4)

    return temperatura, humedad, accel_x, accel_y, accel_z

def conectar():
    client = mqtt.Client()
    client.username_pw_set(MQTT_USER, MQTT_PASSWORD)
    client.connect(MQTT_BROKER, MQTT_PORT, 60)
    return client

def publicar_loop():
    client = conectar()
    print(f"Conectado a {MQTT_BROKER}:{MQTT_PORT}")

    while True:
        temperatura, humedad, ax, ay, az = generar_datos()

        payload_temp = json.dumps({"value": temperatura})
        payload_hum = json.dumps({"value": humedad})
        payload_vib = json.dumps({
            "accel_x": ax,
            "accel_y": ay,
            "accel_z": az
        })

        client.publish(TOPIC_TEMP, payload_temp, qos=1, retain=True)
        client.publish(TOPIC_HUM, payload_hum, qos=1, retain=True)
        client.publish(TOPIC_VIB, payload_vib, qos=1, retain=True)

        print("Enviado:")
        print("  temperatura:", payload_temp)
        print("  humedad    :", payload_hum)
        print("  vibracion  :", payload_vib)
        print("-" * 50)

        time.sleep(INTERVALO)

if __name__ == "__main__":
    publicar_loop()