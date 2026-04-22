#define TINY_GSM_RX_BUFFER 1024

#include <Arduino.h>
#include "utilities.h"
#include <TinyGsmClient.h>
#include <Wire.h>  // For IP5306 configuration

#define SerialMon Serial

// =========================
// MODEM
// =========================
TinyGsm modem(SerialAT);

// =========================
// DEVICE ID
// =========================
#define DEVICE_ID "ESP32_189426166412052"

// =========================
// FIREBASE URLs
// =========================
const char *FIREBASE_DEVICE_URL =
"https://ubsafestep-2200983-default-rtdb.firebaseio.com/devices/" DEVICE_ID ".json";

const char *FIREBASE_EMERGENCY_URL =
"https://ubsafestep-2200983-default-rtdb.firebaseio.com/emergency/" DEVICE_ID ".json";

// =========================
// APN
// =========================
String apn = "internet.globe.com.ph";

// =========================
// EMERGENCY BUTTON - GPIO 13
// =========================
#define BUTTON_PIN 13
#define DEBOUNCE_MS 500
#define EMERGENCY_DURATION_MS 20000UL

// =========================
// GPS STATE
// =========================
String gpsLine = "";
String lastLat = "";
String lastLon = "";
bool gpsHasFix = false;

unsigned long lastButtonPress = 0;
unsigned long emergencyStartTime = 0;
bool emergencyActive = false;

// =========================
// BATTERY MONITORING (Serial only)
// =========================
unsigned long lastBatteryCheck = 0;
#define BATTERY_CHECK_INTERVAL 60000

// =========================
// GPS DATA RECEIPT CHECK
// =========================
unsigned long lastGpsDataTime = 0;
#define GPS_DATA_TIMEOUT_MS 5000  // Timeout for GPS data receipt (5 seconds)

// =========================
// IP5306 POWER MANAGEMENT CHIP - MUST CONFIGURE ON EVERY BOOT
// =========================
#define IP5306_ADDR 0x75
#define IP5306_REG_SYS_CTL0 0x00

// =========================
// CRITICAL: CONFIGURE IP5306 ON EVERY BOOT
// =========================
void forceIP5306Config() {
  // This MUST be called at the VERY BEGINNING of setup()
  // The IP5306 loses its configuration when power is completely cut
  
  // Initialize I2C for IP5306 (SDA=21, SCL=22)
  Wire.begin(21, 22);
  delay(100);
  
  // Try multiple times to configure IP5306
  for (int attempt = 0; attempt < 5; attempt++) {
    // Read current configuration
    Wire.beginTransmission(IP5306_ADDR);
    Wire.write(IP5306_REG_SYS_CTL0);
    if (Wire.endTransmission(false) == 0) {
      Wire.requestFrom(IP5306_ADDR, 1);
      if (Wire.available()) {
        byte currentConfig = Wire.read();
        
        // Configure IP5306 for ALWAYS-ON battery operation:
        // Bit 5 = BOOST_EN (1 = enable boost output)
        // Bit 4 = BOOST (1 = boost mode - converts 3.7V to 5V)
        // Bit 3 = CHARGE_OUT (1 = enable charging output)
        // Bit 2 = POWER_ON_LOAD (0 = disable auto power off)
        // Bit 1 = POWER_ON_KEY (1 = enable power button)
        // Bit 0 = POWER_ON_OFF (1 = keep power ON)
        
        byte newConfig = currentConfig;
        newConfig |= 0x20;  // Enable boost (bit 5)
        newConfig |= 0x10;  // Boost mode (bit 4)
        newConfig |= 0x08;  // Enable charging (bit 3)
        newConfig &= 0xFB;  // Disable auto power off (clear bit 2)
        newConfig |= 0x02;  // Enable power button (bit 1)
        newConfig |= 0x01;  // Keep power ON (bit 0)
        
        // Write new configuration
        Wire.beginTransmission(IP5306_ADDR);
        Wire.write(IP5306_REG_SYS_CTL0);
        Wire.write(newConfig);
        if (Wire.endTransmission() == 0) {
          // Success!
          delay(50);
          
          // Also set charging parameters
          Wire.beginTransmission(IP5306_ADDR);
          Wire.write(0x20);  // Charge Control 0
          Wire.write(0xE0);  // 4.2V charging voltage
          Wire.endTransmission();
          
          delay(50);
          return; // Configuration successful
        }
      }
    }
    
    // If we get here, configuration failed - try again
    delay(100);
  }
  
  // If all attempts fail, at least set the hardware pins
  // This is a fallback method
  pinMode(12, OUTPUT);
  digitalWrite(12, HIGH);
  pinMode(25, OUTPUT);
  digitalWrite(25, LOW);
}

// =========================
// EMERGENCY BUTTON SETUP
// =========================
void setupEmergencyButton() {
  pinMode(BUTTON_PIN, INPUT_PULLUP);
}

// =========================
// BATTERY VOLTAGE READING
// =========================
float readBatteryVoltage() {
  long sum = 0;
  for(int i = 0; i < 16; i++) {
    sum += analogRead(BOARD_BAT_ADC_PIN);
    delay(1);
  }
  int raw = sum / 16;
  float voltage = (raw / 4095.0) * 3.3 * 2.0;
  return voltage;
}

void checkBattery() {
  float voltage = readBatteryVoltage();
  SerialMon.print("🔋 Battery: ");
  SerialMon.print(voltage, 2);
  SerialMon.println("V");
  
  if (voltage < 3.5) {
    SerialMon.println("⚠️  Low battery");
  }
}

// =========================
// MODEM POWER ON
// =========================
void modemPowerOn() {
  // Step 1: CRITICAL - GPIO 12 must be HIGH for modem power
  pinMode(BOARD_POWERON_PIN, OUTPUT);
  digitalWrite(BOARD_POWERON_PIN, HIGH);
  delay(100);
  
  // Step 2: CRITICAL - GPIO 25 (DTR) must be LOW to prevent modem sleep
  pinMode(MODEM_DTR_PIN, OUTPUT);
  digitalWrite(MODEM_DTR_PIN, LOW);
  
  // Step 3: Pulse GPIO 4 (PWRKEY) to turn on modem
  pinMode(BOARD_PWRKEY_PIN, OUTPUT);
  digitalWrite(BOARD_PWRKEY_PIN, HIGH);
  delay(500);  // 500ms pulse for cold boot
  digitalWrite(BOARD_PWRKEY_PIN, LOW);
  
  delay(8000);  // Wait for modem to boot
}

// =========================
// SETUP - CRITICAL SEQUENCE
// =========================
void setup() {
  SerialMon.begin(115200);
  delay(3000);
  
  SerialMon.println("\n=== GPS TRACKER STARTING ===");
  
  // CRITICAL STEP 1: Configure IP5306 IMMEDIATELY on boot
  // This must be done BEFORE anything else
  forceIP5306Config();
  
  // Step 2: Setup emergency button
  setupEmergencyButton();
  
  // Step 3: Check battery
  checkBattery();
  
  // Step 4: Power on modem
  SerialAT.begin(115200, SERIAL_8N1, MODEM_RX_PIN, MODEM_TX_PIN);
  modemPowerOn();
  
  // Step 5: Wait for modem
  int attempts = 0;
  while (!modem.testAT()) {
    SerialMon.print(".");
    delay(1000);
    attempts++;
    
    if (attempts > 10) {
      SerialMon.println("\nRetrying modem power...");
      // Hardware reset
      digitalWrite(BOARD_PWRKEY_PIN, HIGH);
      delay(500);
      digitalWrite(BOARD_PWRKEY_PIN, LOW);
      delay(8000);
      attempts = 0;
    }
  }
  
  SerialMon.println("\nModem ready");
  
  // Step 6: Disable ALL sleep modes
  SerialAT.println("AT+CSCLK=0");  // Disable modem sleep
  delay(500);
  SerialAT.println("AT+CFUN=1");   // Full functionality
  delay(500);
  
  // Step 7: Check SIM
  while (modem.getSimStatus() != SIM_READY) {
    SerialMon.println("Waiting for SIM...");
    delay(1000);
  }
  
  // Step 8: Network
  while (!modem.isNetworkConnected()) {
    SerialMon.println("Registering network...");
    delay(2000);
  }
  
  // Step 9: Data connection
  if (!modem.setNetworkActive(apn, false)) {
    SerialMon.println("Data connection warning");
  }
  
  // Step 10: GPS setup
  SerialAT.println("AT+CGNSSPWR=1"); delay(1000);
  SerialAT.println("AT+CGNSSMODE=3"); delay(1000);
  SerialAT.println("AT+CGNSSPORTSWITCH=1,1"); delay(1000);
  SerialAT.println("AT+CGNSSTST=1"); delay(1000);
  
  SerialMon.println("System ready");
}

// =========================
// MAIN LOOP
// =========================
void loop() {
  // Read GPS data
  while (SerialAT.available()) {
    char c = SerialAT.read();
    if (c == '\n' || c == '\r') {
      if (gpsLine.length() > 0) {
        processGPSLine(gpsLine);
        gpsLine = "";
      }
    } else {
      gpsLine += c;
    }
  }
  
  // Query GPS every 500ms
  static unsigned long lastGpsQuery = 0;
  if (millis() - lastGpsQuery > 500) {
    lastGpsQuery = millis();
    SerialAT.println("AT+CGNSSINFO");
  }
  
  // Emergency button
  if (digitalRead(BUTTON_PIN) == LOW) {
    if (millis() - lastButtonPress > DEBOUNCE_MS) {
      lastButtonPress = millis();
      triggerEmergency();
    }
  }
  
  // Emergency timeout
  if (emergencyActive && millis() - emergencyStartTime > EMERGENCY_DURATION_MS) {
    emergencyActive = false;
    SerialMon.println("Emergency ended");
  }
  
  // Battery check
  if (millis() - lastBatteryCheck > BATTERY_CHECK_INTERVAL) {
    lastBatteryCheck = millis();
    checkBattery();
  }
  
  // =========================
  // GPS DATA RECEIPT CHECK
  // =========================
  static unsigned long lastGpsCheck = 0;
  if (millis() - lastGpsCheck > 1000) {  // Check every 1 second
    lastGpsCheck = millis();
    if (millis() - lastGpsDataTime > GPS_DATA_TIMEOUT_MS) {
      SerialMon.println("⚠️  No GPS data received for 5 seconds");
    } else {
      SerialMon.println("✅ GPS data is being received");
    }
  }
}

// =========================
// GPS PROCESSING
// =========================
void processGPSLine(String line) {
  // Update the last GPS data time whenever we receive a CGNSSINFO line
  lastGpsDataTime = millis();
  
  if (!line.startsWith("+CGNSSINFO")) return;
  
  line.replace("+CGNSSINFO: ", "");
  
  String fields[20];
  int fieldCount = 0;
  
  while (line.length() && fieldCount < 20) {
    int commaPos = line.indexOf(',');
    if (commaPos == -1) {
      fields[fieldCount++] = line;
      break;
    }
    fields[fieldCount++] = line.substring(0, commaPos);
    line = line.substring(commaPos + 1);
  }
  
  // Check fix status
  if (fieldCount > 0) {
    int fixStatus = fields[0].toInt();
    bool newFixStatus = (fixStatus == 1 || fixStatus == 2);
    
    if (newFixStatus != gpsHasFix) {
      gpsHasFix = newFixStatus;
    }
  }
  
  // Get coordinates
  if (fieldCount > 7 && fields[5].length() && fields[7].length() && 
      fields[5] != "0" && fields[7] != "0") {
    String lat = fields[5];
    String lon = fields[7];
    
    if (lat != lastLat || lon != lastLon) {
      lastLat = lat;
      lastLon = lon;
      
      SerialMon.print("\nLocation: ");
      SerialMon.print(lat);
      SerialMon.print(", ");
      SerialMon.println(lon);
      
      if (emergencyActive) {
        sendToFirebase(lat, lon, FIREBASE_EMERGENCY_URL, true);
      } else {
        sendToFirebase(lat, lon, FIREBASE_DEVICE_URL, false);
      }
    }
  }
}

// =========================
// EMERGENCY FUNCTION
// =========================
void triggerEmergency() {
  SerialMon.println("\nEMERGENCY BUTTON PRESSED!");
  
  if (lastLat.length() && lastLon.length()) {
    emergencyActive = true;
    emergencyStartTime = millis();
    sendToFirebase(lastLat, lastLon, FIREBASE_EMERGENCY_URL, true);
  } else {
    SerialMon.println("No GPS fix");
    emergencyActive = true;
    emergencyStartTime = millis();
    sendToFirebase("0", "0", FIREBASE_EMERGENCY_URL, true);
  }
}

// =========================
// FIREBASE FUNCTIONS
// =========================
void sendToFirebase(String lat, String lon, const char *url, bool emergency) {
  if (!modem.isNetworkConnected()) {
    SerialMon.println("No network");
    return;
  }
  
  modem.https_begin();
  modem.https_set_url(url);
  modem.https_set_accept_type("application/json");
  
  String payload = "{";
  payload += "\"device_id\":\"" DEVICE_ID "\","; 
  payload += "\"connection_type\":\"cellular\",";
  payload += "\"latitude\":" + lat + ",";
  payload += "\"longitude\":" + lon + ",";
  payload += "\"altitude\":0,"; 
  payload += "\"speed\":0,"; 
  payload += "\"satellites\":0,"; 
  payload += "\"hdop\":99.99,"; 
  payload += "\"sos_active\":" + String(emergency ? "true" : "false") + ",";
  payload += "\"timestamp\":" + String(millis());
  payload += "}";
  
  int code = modem.https_put(payload);
  
  SerialMon.print("Firebase: ");
  SerialMon.println(code);
  
  if (code == 200) {
    SerialMon.println("Firebase updated");
  } else {
    SerialMon.println("Firebase failed");
  }
  
  modem.https_end();
} 