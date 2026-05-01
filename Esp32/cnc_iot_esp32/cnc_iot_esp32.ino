//  CNC IoT - ESP32  |  Entrega 2 — MQTT
//  Sensores : DHT11/22 (temperatura y humedad)  — GPIO0
//             MPU-6050 (aceleración X/Y/Z)      — SDA=8, SCL=9
//  Destino  : Broker Mosquitto en AWS vía MQTT

#include "credentials.h"
#include <WiFi.h>
#include <PubSubClient.h>
#include <DHT.h>
#include <Wire.h>

//  DHT
#define DHTPIN   0
#define DHTTYPE  DHT22
DHT dht(DHTPIN, DHTTYPE);

//  MPU-6050
#define MPU_ADDR  0x68
#define SDA_PIN   8
#define SCL_PIN   9

//  MQTT
#define MQTT_PORT  1883

WiFiClient wifiClient;
PubSubClient mqtt(wifiClient);

//  Intervalo
const unsigned long INTERVALO_MS = 2000;
unsigned long ultimoEnvio = 0;
bool mpuOk = true;


// Helpers MPU (lectura directa por I2C, sin librería externa)

void mpuEscribir(byte reg, byte valor) {
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(reg);
  Wire.write(valor);
  Wire.endTransmission();
}

int16_t mpuLeerInt16(byte reg) {
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(reg);
  Wire.endTransmission(false);
  Wire.requestFrom(MPU_ADDR, 2);
  return (Wire.read() << 8) | Wire.read();
}


// Conexión WiFi

void conectarWiFi() {
  Serial.printf("[WiFi] Conectando a %s ", WIFI_SSID);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.printf("\n[WiFi] Conectado. IP: %s\n", WiFi.localIP().toString().c_str());
}


// Conexión MQTT (con reintentos)

void conectarMQTT() {
  mqtt.setServer(MQTT_BROKER, MQTT_PORT);

  while (!mqtt.connected()) {
    Serial.printf("[MQTT] Conectando a %s...", MQTT_BROKER);
    String clientId = "ESP32-CNC-" + WiFi.macAddress();

    if (mqtt.connect(clientId.c_str(), MQTT_USER, MQTT_PASSWORD)) {
      Serial.println(" OK");
    } else {
      Serial.printf(" Error rc=%d — reintentando en 3s\n", mqtt.state());
      delay(3000);
    }
  }
}


// Setup

void setup() {
  Serial.begin(115200);
  delay(500);
  Serial.println("\n=== CNC IoT ESP32 — Entrega 2 MQTT ===");

  // DHT
  dht.begin();
  Serial.println("[DHT22] Iniciado en GPIO4");

  // MPU-6050
  Wire.begin(SDA_PIN, SCL_PIN);
  delay(100);
  mpuEscribir(0x6B, 0x00);   // sacar del modo sleep
  delay(100);
  Serial.println("[MPU-6050] Iniciado en SDA=8 SCL=9");

  // WiFi
  conectarWiFi();

  // MQTT
  conectarMQTT();
}


// Loop

void loop() {
  if (!mqtt.connected()) {
    Serial.println("[MQTT] Desconectado - reconectando...");
    conectarMQTT();
  }
  mqtt.loop();

  unsigned long ahora = millis();
  if (ahora - ultimoEnvio < INTERVALO_MS) return;
  ultimoEnvio = ahora;

  // Leer DHT22
  float humedad = dht.readHumidity();
  float temperatura = dht.readTemperature();

  if (isnan(humedad) || isnan(temperatura)) {
    Serial.println("[DHT22] Error de lectura - se omite este ciclo");
    return;
  }

  // Leer MPU-6050
  float accel_x = 0.0, accel_y = 0.0, accel_z = 0.0;
  if (mpuOk) {
    accel_x = (mpuLeerInt16(0x3B) / 16384.0) * 9.81;
    accel_y = (mpuLeerInt16(0x3D) / 16384.0) * 9.81;
    accel_z = (mpuLeerInt16(0x3F) / 16384.0) * 9.81;
  } else {
    Serial.println("[MPU-6050] No detectado - enviando ceros");
  }

  // Monitor serial
  Serial.println("------ Nueva lectura ------");
  Serial.printf("  Temperatura : %.2f °C\n", temperatura);
  Serial.printf("  Humedad     : %.2f %%\n", humedad);
  Serial.printf("  Accel X     : %.4f m/s²\n", accel_x);
  Serial.printf("  Accel Y     : %.4f m/s²\n", accel_y);
  Serial.printf("  Accel Z     : %.4f m/s²\n", accel_z);

  // Construir payload único
  char payload[180];
  snprintf(payload, sizeof(payload),
           "{\"temperatura\":%.2f,\"humedad\":%.2f,\"accel_x\":%.4f,\"accel_y\":%.4f,\"accel_z\":%.4f}",
           temperatura, humedad, accel_x, accel_y, accel_z);

  bool ok = mqtt.publish("flux/cnc1/datos", payload, true);
  Serial.printf("[MQTT] flux/cnc1/datos → %s  %s\n", payload, ok ? "OK" : "ERROR");
}