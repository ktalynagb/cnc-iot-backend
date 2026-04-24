// =============================================================
//  CNC IoT - ESP32
//  Sensores : DHT11 (temperatura y humedad)
//             MPU-6050 (aceleración X/Y/Z por I2C)
//  Destino  : POST http://192.168.56.10:8000/datos
// =============================================================

// Librerías 
#include "credentials.h"
#include <WiFi.h>
#include <HTTPClient.h>
#include <DHT.h>
#include <Wire.h>
#include <MPU6050.h>   // librería: "MPU6050" de Electronic Cats



//  DHT11 
#define DHTPIN  4          // GPIO4 : pin DATA del DHT11
#define DHTTYPE DHT11
DHT dht(DHTPIN, DHTTYPE);

//  MPU-6050 
// SDA : GPIO21  
// SCL : GPIO22  
MPU6050 mpu;

// Intervalo de envío 
const unsigned long INTERVALO_MS = 5000;   // cada 5 segundos
unsigned long ultimoEnvio = 0;

// Setup
void setup() {
  Serial.begin(115200);
  delay(500);
  Serial.println("\n=== CNC IoT - ESP32 iniciando ===");

  // DHT11
  dht.begin();
  Serial.println("[DHT11] Iniciado en GPIO4");

  //  MPU-6050 
  Wire.begin();          // SDA=21, SCL=22 por defecto
  mpu.initialize();
  if (mpu.testConnection()) {
    Serial.println("[MPU-6050] Conexión OK");
  } else {
    Serial.println("[MPU-6050] ERROR - verifica el cableado I2C");
  }

  // WiFi 
  Serial.printf("[WiFi] Conectando a %s ", WIFI_SSID);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.printf("\n[WiFi] Conectado. IP: %s\n", WiFi.localIP().toString().c_str());
}

// Loop
void loop() {
  unsigned long ahora = millis();
  if (ahora - ultimoEnvio < INTERVALO_MS) return;
  ultimoEnvio = ahora;

  // Leer DHT11 
  float humedad      = dht.readHumidity();
  float temperatura  = dht.readTemperature();

  if (isnan(humedad) || isnan(temperatura)) {
    Serial.println("[DHT11] Error de lectura - se omite este ciclo");
    return;
  }

// Leer MPU-6050 (solo si está conectado)
  float accel_x = 0.0, accel_y = 0.0, accel_z = 0.0;

  if (mpu.testConnection()) {
    int16_t ax_raw, ay_raw, az_raw, gx_raw, gy_raw, gz_raw;
    mpu.getMotion6(&ax_raw, &ay_raw, &az_raw, &gx_raw, &gy_raw, &gz_raw);
    accel_x = (ax_raw / 16384.0) * 9.81;
    accel_y = (ay_raw / 16384.0) * 9.81;
    accel_z = (az_raw / 16384.0) * 9.81;
  } else {
    Serial.println("[MPU-6050] No detectado - enviando ceros");
  }

  //  Monitor serial 
  Serial.println("------ Nueva lectura ------");
  Serial.printf("  Temperatura : %.2f °C\n",  temperatura);
  Serial.printf("  Humedad     : %.2f %%\n",  humedad);
  Serial.printf("  Accel X     : %.4f m/s²\n", accel_x);
  Serial.printf("  Accel Y     : %.4f m/s²\n", accel_y);
  Serial.printf("  Accel Z     : %.4f m/s²\n", accel_z);

  //Verificar WiFi antes de enviar 
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

  //  HTTP POST 
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
