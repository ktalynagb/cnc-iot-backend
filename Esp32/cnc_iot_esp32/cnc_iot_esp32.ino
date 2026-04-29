// =============================================================
<<<<<<< HEAD
//  CNC IoT - ESP32
//  Sensores : DHT11 (temperatura y humedad)
//             MPU-6050 (aceleración X/Y/Z por I2C)
//  Destino  : POST http://20.12.182.114/datos/
=======
//  CNC IoT - ESP32-C3 Super Mini
//  Sensores : DHT11 (temperatura y humedad)  — GPIO4
//             MPU-6050 (aceleración X/Y/Z)   — SDA=8, SCL=9
//  Nota     : GPIO21 dañado — no usar
>>>>>>> 01aaa633170e123099bff09545a640188c2812ef
// =============================================================

#include "credentials.h"
#include <WiFi.h>
#include <HTTPClient.h>
#include <DHT.h>
#include <Wire.h>

<<<<<<< HEAD
//  DHT11 
#define DHTPIN  4          // GPIO4 : pin DATA del DHT11
=======
// DHT11
#define DHTPIN  0
>>>>>>> 01aaa633170e123099bff09545a640188c2812ef
#define DHTTYPE DHT22
DHT dht(DHTPIN, DHTTYPE);

// MPU-6050
#define MPU_ADDR 0x68
#define SDA_PIN  8
#define SCL_PIN  9

const unsigned long INTERVALO_MS = 2000;
unsigned long ultimoEnvio = 0;
bool mpuOk = true;  // se define una sola vez en setup

// ── Helpers MPU ──────────────────────────────────────────────

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

// ── Setup ────────────────────────────────────────────────────

void setup() {
  Serial.begin(115200);
  delay(500);
  Serial.println("\n=== CNC IoT - ESP32-C3 Super Mini iniciando ===");

  // DHT11
  dht.begin();
  Serial.println("[DHT22] Iniciado en GPIO4");

  // MPU-6050 — verificar solo una vez en setup
  Wire.begin(SDA_PIN, SCL_PIN);
  delay(100);
  mpuEscribir(0x6B, 0x00);  // despertar del modo sleep
  delay(100);

  // WiFi
  Serial.printf("[WiFi] Conectando a %s ", WIFI_SSID);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.printf("\n[WiFi] Conectado. IP: %s\n", WiFi.localIP().toString().c_str());
}

// ── Loop ─────────────────────────────────────────────────────

void loop() {
  unsigned long ahora = millis();
  if (ahora - ultimoEnvio < INTERVALO_MS) return;
  ultimoEnvio = ahora;

  // Leer DHT11
  float humedad     = dht.readHumidity();
  float temperatura = dht.readTemperature();

  if (isnan(humedad) || isnan(temperatura)) {
    Serial.println("[DHT11] Error de lectura - se omite este ciclo");
    return;
  }

  // Leer MPU-6050 directo, sin verificar conexión en cada ciclo
  float accel_x = 0.0, accel_y = 0.0, accel_z = 0.0;

  if (mpuOk) {
    accel_x = (mpuLeerInt16(0x3B) / 16384.0) * 9.81;
    accel_y = (mpuLeerInt16(0x3D) / 16384.0) * 9.81;
    accel_z = (mpuLeerInt16(0x3F) / 16384.0) * 9.81;
  }

  // Monitor serial
  Serial.println("------ Nueva lectura ------");
  Serial.printf("  Temperatura : %.2f °C\n",   temperatura);
  Serial.printf("  Humedad     : %.2f %%\n",   humedad);
  Serial.printf("  Accel X     : %.4f m/s²\n", accel_x);
  Serial.printf("  Accel Y     : %.4f m/s²\n", accel_y);
  Serial.printf("  Accel Z     : %.4f m/s²\n", accel_z);

  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("[WiFi] Sin conexión - se omite el envío");
    return;
  }

  // Construir JSON
  char jsonBody[200];
  snprintf(jsonBody, sizeof(jsonBody),
    "{\"temperatura\":%.2f,\"humedad\":%.2f,"
    "\"accel_x\":%.4f,\"accel_y\":%.4f,\"accel_z\":%.4f}",
    temperatura, humedad, accel_x, accel_y, accel_z
  );

  // HTTP POST
  HTTPClient http;
  http.begin(SERVER_URL);
  http.addHeader("Content-Type", "application/json");

  int httpCode = http.POST(jsonBody);

  if (httpCode > 0) {
    Serial.printf("[HTTP] Respuesta: %d\n", httpCode);
    if (httpCode == 200 || httpCode == 201) {
      String respuesta = http.getString();
      Serial.printf("[HTTP] Body: %s\n", respuesta.c_str());
    }
  } else {
    Serial.printf("[HTTP] Error: %s\n", http.errorToString(httpCode).c_str());
  }

  http.end();
}