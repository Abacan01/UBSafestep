#include <TinyGPS++.h>
#include <HardwareSerial.h>
#include <WiFi.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>

// ==================== CONFIGURATION ====================
// WiFi Credentials
const char* ssid = "UBSafestep";
const char* password = "hahatdog";

// Firebase Configuration
const String FIREBASE_HOST = "ubsafestep-2200983-default-rtdb.firebaseio.com";
const String FIREBASE_AUTH = "VkMaDVE18wzCLXSLVHNY1MD9DJtIkuNJ6C4YNqN0";

// SIM800L Configuration
const char* APN = "internet";  // For Globe/Smart

// GPS Setup
TinyGPSPlus gps;
HardwareSerial gpsSerial(1); // UART1 for GPS

// SIM800L Setup
HardwareSerial sim800l(2);   // UART2 for SIM800L

// Pin Definitions
#define GPS_RX       16
#define GPS_TX       17
#define SIM800L_RX   26
#define SIM800L_TX   27

// Tracking Variables
unsigned long lastPrint = 0;
unsigned long lastFirebaseUpdate = 0;
const unsigned long PRINT_INTERVAL = 2000;        // Print every 2 seconds
const unsigned long FIREBASE_INTERVAL = 10000;    // Send to Firebase every 10 seconds

bool wifiConnected = false;
bool cellularActive = false;
bool useCellular = false;

String deviceID = "ESP32_" + String(ESP.getEfuseMac()); // Unique device ID
// ======================================================

void setup() {
  Serial.begin(115200);
  Serial.println();
  Serial.println("🚀 ESP32 Tracker: GPS + SIM800L + Firebase");
  Serial.println("===========================================");
  Serial.print("DeviceId: ");
  Serial.println(deviceID);
  
  // Initialize GPS
  gpsSerial.begin(9600, SERIAL_8N1, GPS_RX, GPS_TX);
  Serial.println("🛰️ GPS NEO-M8N Initialized");
  
  // Initialize SIM800L
  initializeSIM800L();
  
  // Connect to WiFi first
  connectToWiFi();
  
  Serial.println("✅ System Ready!");
  Serial.println();
  
  // Print header
  Serial.println("TIME     | LATITUDE    | LONGITUDE   | SATELLITES | STATUS");
  Serial.println("---------|-------------|-------------|------------|--------");
}

void initializeSIM800L() {
  Serial.println("📱 Initializing SIM800L...");
  
  // Initialize SIM800L serial
  sim800l.begin(9600, SERIAL_8N1, SIM800L_RX, SIM800L_TX);
  delay(3000);
  
  // Check if SIM800L is responding
  if (sendATCommand("AT", 5000)) {
    Serial.println("✅ SIM800L Responding");
    
    // Check SIM card
    if (sendATCommand("AT+CPIN?", 5000)) {
      Serial.println("✅ SIM Card Ready");
    }
    
    // Check network
    if (sendATCommand("AT+CREG?", 5000)) {
      Serial.println("✅ Network Registered");
    }
    
    // Check signal
    sendATCommand("AT+CSQ", 5000);
    
  } else {
    Serial.println("❌ SIM800L Not Responding - Using WiFi only");
  }
}

bool sendATCommand(String command, unsigned long timeout) {
  Serial.print("📱 AT: ");
  Serial.println(command);
  
  sim800l.println(command);
  
  unsigned long startTime = millis();
  String response = "";
  bool gotOK = false;
  
  while (millis() - startTime < timeout) {
    if (sim800l.available()) {
      char c = sim800l.read();
      response += c;
      
      if (response.indexOf("OK") >= 0) {
        gotOK = true;
        break;
      }
      if (response.indexOf("ERROR") >= 0) {
        break;
      }
    }
    delay(10);
  }
  
  return gotOK;
}

void connectToWiFi() {
  Serial.println("📡 Connecting to WiFi...");
  
  WiFi.begin(ssid, password);
  
  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 20) {
    delay(500);
    Serial.print(".");
    attempts++;
  }
  
  if (WiFi.status() == WL_CONNECTED) {
    wifiConnected = true;
    Serial.println("\n✅ WiFi Connected!");
    Serial.print("📡 IP: ");
    Serial.println(WiFi.localIP());
  } else {
    wifiConnected = false;
    Serial.println("\n❌ WiFi Failed!");
    enableCellularMode();
  }
}

void enableCellularMode() {
  Serial.println("🔄 Enabling Cellular Mode...");
  
  if (setupGPRS()) {
    cellularActive = true;
    useCellular = true;
    Serial.println("✅ Cellular Data Activated");
  } else {
    Serial.println("❌ Cellular Setup Failed");
  }
}

bool setupGPRS() {
  Serial.println("🌐 Setting up GPRS...");
  
  // Configure cellular data
  if (!sendATCommand("AT+CGATT=1", 10000)) return false;
  
  String apnCommand = "AT+CSTT=\"" + String(APN) + "\",\"\",\"\"";
  if (!sendATCommand(apnCommand, 10000)) return false;
  
  if (!sendATCommand("AT+CIICR", 15000)) return false;
  if (!sendATCommand("AT+CIFSR", 10000)) return false;
  
  return true;
}

void loop() {
  // Read and process GPS data
  processGPS();
  
  // Print status every 2 seconds
  if (millis() - lastPrint >= PRINT_INTERVAL) {
    printGPSStatus();
    lastPrint = millis();
  }
  
  // Send to Firebase every 10 seconds (when we have GPS fix)
  if (millis() - lastFirebaseUpdate >= FIREBASE_INTERVAL) {
    if (gps.location.isValid()) {
      sendToFirebase();
    }
    lastFirebaseUpdate = millis();
  }
  
  // Monitor connections
  monitorConnections();
  
  delay(100);
}

void processGPS() {
  while (gpsSerial.available() > 0) {
    if (gps.encode(gpsSerial.read())) {
      // GPS data parsed successfully
    }
  }
}

void printGPSStatus() {
  Serial.print(getTimeString());
  Serial.print(" | ");
  
  if (gps.location.isValid()) {
    // Print location data
    Serial.print(gps.location.lat(), 6);
    Serial.print(" | ");
    Serial.print(gps.location.lng(), 6);
    Serial.print(" | ");
    Serial.print("    ");
    Serial.print(gps.satellites.value());
    Serial.print("     | ");
    
    // Print connection type
    if (wifiConnected) {
      Serial.print("📡 WiFi");
    } else if (cellularActive) {
      Serial.print("🌐 Cellular");
    } else {
      Serial.print("❌ Offline");
    }
    
  } else {
    // No GPS fix
    Serial.print("   ---      |    ---      |     --     | ");
    
    if (gps.satellites.value() > 0) {
      Serial.print("🔍 Searching (");
      Serial.print(gps.satellites.value());
      Serial.print(" sats)");
    } else {
      Serial.print("❌ No GPS");
    }
  }
  
  Serial.println();
}

void sendToFirebase() {
  if (!gps.location.isValid()) {
    Serial.println("❌ No valid GPS data to send");
    return;
  }
  
  Serial.println("📡 Sending to Firebase...");
  
  // Create JSON data
  String jsonData = createLocationJSON();
  
  // Send via WiFi or Cellular
  if (wifiConnected) {
    sendViaWiFi(jsonData);
  } else if (cellularActive) {
    sendViaCellular(jsonData);
  } else {
    Serial.println("❌ No internet connection");
  }
}

String createLocationJSON() {
  String json = "{";
  json += "\"device_id\":\"" + deviceID + "\",";
  json += "\"latitude\":" + String(gps.location.lat(), 6) + ",";
  json += "\"longitude\":" + String(gps.location.lng(), 6) + ",";
  json += "\"altitude\":" + String(gps.altitude.isValid() ? gps.altitude.meters() : 0) + ",";
  json += "\"speed\":" + String(gps.speed.isValid() ? gps.speed.kmph() : 0) + ",";
  json += "\"satellites\":" + String(gps.satellites.value()) + ",";
  json += "\"hdop\":" + String(gps.hdop.isValid() ? gps.hdop.value() / 100.0 : 0) + ",";
  json += "\"connection_type\":\"" + String(wifiConnected ? "wifi" : "cellular") + "\",";
  json += "\"timestamp\":" + String(millis());
  json += "}";
  
  return json;
}

void sendViaWiFi(String jsonData) {
  HTTPClient http;
  
  String url = "https://" + FIREBASE_HOST + "/devices/" + deviceID + ".json?auth=" + FIREBASE_AUTH;
  
  Serial.print("📡 Sending via WiFi to: ");
  Serial.println(url);
  Serial.print("📦 Data: ");
  Serial.println(jsonData);
  
  http.begin(url);
  http.addHeader("Content-Type", "application/json");
  
  int httpCode = http.PUT(jsonData);
  
  Serial.print("📨 HTTP Response: ");
  Serial.println(httpCode);
  
  if (httpCode == 200) {
    Serial.println("✅ Successfully sent to Firebase");
    String response = http.getString();
    Serial.println("📄 Response: " + response);
  } else {
    Serial.println("❌ Failed to send to Firebase");
  }
  
  http.end();
}

void sendViaCellular(String jsonData) {
  Serial.println("📡 Sending via Cellular...");
  
  // Start TCP connection
  String connectCmd = "AT+CIPSTART=\"TCP\",\"";
  connectCmd += FIREBASE_HOST;
  connectCmd += "\",443";
  
  if (sendATCommand(connectCmd, 30000)) {
    Serial.println("✅ Connected to Firebase via cellular");
    
    // Prepare HTTP request
    String httpRequest = "PUT /devices/" + deviceID + ".json?auth=" + FIREBASE_AUTH + " HTTP/1.1\r\n";
    httpRequest += "Host: " + FIREBASE_HOST + "\r\n";
    httpRequest += "Content-Type: application/json\r\n";
    httpRequest += "Content-Length: " + String(jsonData.length()) + "\r\n";
    httpRequest += "Connection: close\r\n\r\n";
    httpRequest += jsonData;
    
    // Send data
    String sendCmd = "AT+CIPSEND=" + String(httpRequest.length());
    if (sendATCommand(sendCmd, 5000)) {
      delay(100);
      sim800l.print(httpRequest);
      delay(2000);
      
      // Read response
      readCellularResponse();
    }
    
    // Close connection
    sendATCommand("AT+CIPCLOSE", 5000);
    
  } else {
    Serial.println("❌ Cellular connection failed");
  }
}

void readCellularResponse() {
  unsigned long start = millis();
  String response = "";
  
  while (millis() - start < 10000) {
    if (sim800l.available()) {
      response += sim800l.readString();
    }
    delay(100);
  }
  
  if (response.length() > 0) {
    Serial.print("📨 Cellular Response: ");
    Serial.println(response);
  }
}

void monitorConnections() {
  static unsigned long lastCheck = 0;
  
  if (millis() - lastCheck >= 30000) { // Every 30 seconds
    // Check WiFi connection
    if (wifiConnected && WiFi.status() != WL_CONNECTED) {
      Serial.println("🔄 WiFi disconnected, reconnecting...");
      wifiConnected = false;
      connectToWiFi();
    }
    
    // Check cellular signal
    if (cellularActive) {
      sendATCommand("AT+CSQ", 5000);
    }
    
    lastCheck = millis();
  }
}

String getTimeString() {
  unsigned long seconds = millis() / 1000;
  unsigned long minutes = seconds / 60;
  unsigned long hours = minutes / 60;
  
  seconds %= 60;
  minutes %= 60;
  
  String timeStr = "";
  if (hours < 10) timeStr += "0";
  timeStr += String(hours);
  timeStr += ":";
  if (minutes < 10) timeStr += "0";
  timeStr += String(minutes);
  timeStr += ":";
  if (seconds < 10) timeStr += "0";
  timeStr += String(seconds);
  
  return timeStr;
}