#include <WiFi.h>
#include <WebServer.h>
#include <Adafruit_Fingerprint.h>

const char* SSID = "TU_WIFI";
const char* PASSWORD = "TU_PASSWORD";
HardwareSerial sensorSerial(2);
Adafruit_Fingerprint finger(&sensorSerial);
WebServer server(80);
bool ready = false;
constexpr size_t MAX_TEMPLATE_SIZE = 2048;
String transferError;
bool transferFail(const String& reason) {
  transferError = reason;
  Serial.println(String("[AS608] ") + reason);
  return false;
}
bool validTemplateSize(size_t size) { return size >= 256 && size <= MAX_TEMPLATE_SIZE && size % 32 == 0; }

void reply(bool ok, const String& message) {
  server.send(ok ? 200 : 400, "application/json",
    String("{\"ok\":") + (ok ? "true" : "false") + ",\"message\":\"" + message + "\"}");
}
bool available() {
  if (!ready) { reply(false, "Lector no detectado. Revisa cableado y reinicia ESP32."); return false; }
  return true;
}
// Transferencias UART con cabecera, longitud y checksum validados.
void sendPacket(uint8_t type, const uint8_t* data, uint16_t size) {
  uint16_t length = size + 2;
  const uint8_t header[] = {0xEF, 0x01, 0xFF, 0xFF, 0xFF, 0xFF, type, uint8_t(length >> 8), uint8_t(length)};
  uint16_t checksum = type + header[7] + header[8];
  sensorSerial.write(header, sizeof(header));
  for (uint16_t i = 0; i < size; i++) { sensorSerial.write(data[i]); checksum += data[i]; }
  sensorSerial.write(uint8_t(checksum >> 8)); sensorSerial.write(uint8_t(checksum));
  sensorSerial.flush(true); // Esperar TX sin descartar la respuesta RX.
}
bool readBytes(uint8_t* target, size_t length, uint32_t started) {
  size_t received = 0;
  while (received < length && millis() - started < 3000) {
    if (sensorSerial.available()) target[received++] = sensorSerial.read();
    else delay(1);
  }
  if (received != length) return transferFail(String("UART timeout: recibidos ") + received + "/" + length + " bytes");
  return true;
}
bool readPacket(uint8_t& type, uint8_t* data, uint16_t& size) {
  uint32_t started = millis();
  uint8_t header[9], tail[2];
  if (!readBytes(header, 9, started)) return false;
  if (header[0] != 0xEF || header[1] != 0x01) return transferFail("Cabecera UART invalida");
  for (int i = 2; i < 6; i++) if (header[i] != 0xFF) return transferFail("Direccion UART inesperada");
  uint16_t length = (uint16_t(header[7]) << 8) | header[8];
  if (length < 2 || length > 258) return transferFail(String("Longitud de paquete invalida: ") + length);
  size = length - 2; type = header[6];
  if (!readBytes(data, size, started) || !readBytes(tail, 2, started)) return false;
  uint16_t checksum = type + header[7] + header[8];
  for (uint16_t i = 0; i < size; i++) checksum += data[i];
  if (checksum != ((uint16_t(tail[0]) << 8) | tail[1])) return transferFail("Checksum UART incorrecto");
  return true;
}
bool command(const uint8_t* data, uint16_t length, uint8_t* response, uint16_t& size) {
  while (sensorSerial.available()) sensorSerial.read();
  sendPacket(0x01, data, length);
  uint8_t type;
  if (!readPacket(type, response, size)) return false;
  if (type != 0x07 || size < 1) return transferFail("Se esperaba ACK del sensor");
  return true;
}
bool exportTemplate(uint8_t* target, size_t& total) {
  transferError = "";
  total = 0;
  uint8_t cmd[] = {0x08, 0x01}, data[256], type;
  uint16_t size = 0;
  if (!command(cmd, sizeof(cmd), data, size)) return false;
  if (data[0] != 0) return transferFail(String("UpChar rechazado, codigo 0x") + String(data[0], HEX));
  const uint32_t started = millis();
  for (int packets = 0; packets < 64 && millis() - started < 5000; packets++) {
    if (!readPacket(type, data, size)) return false;
    if (type != 0x02 && type != 0x08) return transferFail(String("Tipo inesperado: 0x") + String(type, HEX));
    if (size == 0 || total + size > MAX_TEMPLATE_SIZE) return transferFail("Plantilla vacia o mayor de 2048 bytes");
    memcpy(target + total, data, size); total += size;
    Serial.printf("[AS608] paquete %d: tipo 0x%02X, %u bytes, total %u\n", packets + 1, type, size, unsigned(total));
    if (type == 0x08) {
      if (!validTemplateSize(total)) return transferFail(String("Tamano de plantilla no admitido: ") + unsigned(total));
      return true;
    }
  }
  return transferFail("No llego el paquete final de la plantilla");
}
bool importTemplate(const uint8_t* source, size_t length) {
  uint8_t cmd[] = {0x09, 0x02}, data[256];
  uint16_t size = 0;
  if (!command(cmd, sizeof(cmd), data, size)) return false;
  if (data[0] != 0) return transferFail(String("DownChar rechazado, codigo 0x") + String(data[0], HEX));
  for (size_t offset = 0; offset < length; offset += 32) {
    sendPacket(offset + 32 == length ? 0x08 : 0x02, source + offset, 32);
    delay(5);
  }
  delay(100);
  return true;
}
String hexTemplate(const uint8_t* bytes, size_t length) {
  const char digits[] = "0123456789abcdef";
  String result; result.reserve(length * 2);
  for (size_t i = 0; i < length; i++) { result += digits[bytes[i] >> 4]; result += digits[bytes[i] & 15]; }
  return result;
}
int hexDigit(char c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  return -1;
}
bool parseTemplate(const String& text, uint8_t* bytes, size_t& length) {
  length = text.length() / 2;
  if (text.length() % 2 != 0 || !validTemplateSize(length)) return false;
  for (size_t i = 0; i < length; i++) {
    int hi = hexDigit(text[i * 2]), lo = hexDigit(text[i * 2 + 1]);
    if (hi < 0 || lo < 0) return false;
    bytes[i] = (hi << 4) | lo;
  }
  return true;
}
bool waitImage(uint32_t started) {
  while (millis() - started < 55000) {
    uint8_t code = finger.getImage();
    if (code == FINGERPRINT_OK) return true;
    if (code != FINGERPRINT_NOFINGER) { reply(false, "Error de captura. Intenta nuevamente."); return false; }
    delay(50);
  }
  reply(false, "Tiempo agotado esperando el dedo."); return false;
}
void enroll() {
  if (!available()) return;
  uint32_t started = millis();
  Serial.println("Coloca el dedo");
  if (!waitImage(started)) return;
  if (finger.image2Tz(1) != FINGERPRINT_OK) { reply(false, "Primera captura invalida."); return; }
  Serial.println("Retira el dedo y vuelve a colocarlo");
  while (true) {
    uint8_t code = finger.getImage();
    if (code == FINGERPRINT_NOFINGER) break;
    if (code != FINGERPRINT_OK || millis() - started > 55000) { reply(false, "Error o tiempo agotado al retirar el dedo."); return; }
    delay(50);
  }
  delay(500);
  if (!waitImage(started)) return;
  if (finger.image2Tz(2) != FINGERPRINT_OK || finger.createModel() != FINGERPRINT_OK) { reply(false, "Las capturas no coinciden. Usa el mismo dedo."); return; }
  uint8_t bytes[MAX_TEMPLATE_SIZE];
  size_t length = 0;
  if (!exportTemplate(bytes, length)) { reply(false, String("Transferencia fallida: ") + transferError); return; }
  server.send(200, "application/json", String("{\"ok\":true,\"template\":\"") + hexTemplate(bytes, length) + "\"}");
}
void verify() {
  if (!available()) return;
  uint8_t bytes[MAX_TEMPLATE_SIZE];
  size_t length = 0;
  if (!parseTemplate(server.arg("template"), bytes, length)) { reply(false, "Plantilla hexadecimal invalida (256 a 2048 bytes, multiplos de 32)."); return; }
  Serial.println("Coloca el dedo para verificar");
  if (!waitImage(millis())) return;
  if (finger.image2Tz(1) != FINGERPRINT_OK) { reply(false, "Captura invalida."); return; }
  if (!importTemplate(bytes, length)) { reply(false, String("No se pudo cargar la plantilla: ") + transferError); return; }
  uint8_t cmd[] = {0x03}, data[256]; uint16_t size = 0;
  if (!command(cmd, sizeof(cmd), data, size)) { reply(false, "Error de comunicacion al comparar."); return; }
  if (data[0] == FINGERPRINT_NOMATCH) { server.send(200, "application/json", "{\"ok\":true,\"match\":false}"); return; }
  if (data[0] != FINGERPRINT_OK || size != 3) { reply(false, "El lector no pudo comparar las plantillas."); return; }
  uint16_t score = (uint16_t(data[1]) << 8) | data[2];
  server.send(200, "application/json", String("{\"ok\":true,\"match\":true,\"score\":") + score + "}");
}
void setup() {
  Serial.begin(115200);
  sensorSerial.setRxBufferSize(8192);
  // AS608 TX -> GPIO16; AS608 RX -> GPIO17. GND común.
  sensorSerial.begin(57600, SERIAL_8N1, 16, 17);
  finger.begin(57600);
  sensorSerial.setRxFIFOFull(32);
  ready = finger.verifyPassword();
  Serial.println("Firmware SQLite: transferencia variable v3");
  Serial.println(ready ? "AS608 conectado" : "AS608 no detectado");
  WiFi.begin(SSID, PASSWORD);
  while (WiFi.status() != WL_CONNECTED) { delay(500); Serial.print('.'); }
  Serial.print("\nDireccion para Flutter: http://"); Serial.println(WiFi.localIP());
  server.on("/status", HTTP_GET, []() { if (available()) server.send(200, "application/json", "{\"ok\":true,\"protocol\":2}"); });
  server.on("/enroll", HTTP_POST, enroll);
  server.on("/verify", HTTP_POST, verify);
  server.onNotFound([]() { server.send(404, "application/json", "{\"ok\":false,\"message\":\"Ruta no encontrada\"}"); });
  server.begin();
}
void loop() { server.handleClient(); delay(2); }
