#include <Arduino.h>
#include <WiFi.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>

// Pin Definitions
#define PIR1_PIN 27
#define PIR2_PIN 26
#define PIR3_PIN 25
#define LDR_PIN 36
#define LED1_PIN 16
#define LED2_PIN 17
#define LED3_PIN 18

// System Settings
#define MOTION_TIMEOUT 20000    // 20 seconds for motion timeout
#define SLEEP_TIMEOUT 10000     // 10 seconds for sleep mode
#define SLEEP_BRIGHTNESS 10     // 10% brightness in sleep mode
#define UPDATE_INTERVAL 30000   // 30 seconds for API updates
#define ENERGY_UPDATE_INTERVAL 5000  // 5 seconds for energy updates
#define LDR_DARK_THRESHOLD 3500 // LDR threshold for dark conditions
#define LDR_LIGHT_THRESHOLD 2000 // LDR threshold for light conditions
#define DEBOUNCE_TIME 200       // 200ms debounce for PIR sensors

// WiFi Config
const char* ssid = "strike";
const char* password = "og_strike";
const char* serverUrl = "http://192.168.127.244:3000";
const char* deviceId = "neo";

// System State Structure
typedef struct {
  unsigned long lastTrigger;
  bool motionDetected;
  bool isSleeping;
  int baseBrightness;
  int motionBrightness;
  unsigned long lastUpdate;
  bool manualMode;          // true = manual mode, false = app mode
  unsigned long manualModeEndTime;
  float currentPower;
  float totalEnergy;
  bool ledWorking[3];
  String currentTime;
  String weatherCondition;
  String sunriseTime;
  String sunsetTime;
  unsigned long lastMotionTime;
  unsigned long lastPIR1Time;
  unsigned long lastPIR2Time;
  unsigned long lastPIR3Time;
} SystemState;

SystemState sysState = {
  .lastTrigger = 0,
  .motionDetected = false,
  .isSleeping = false,
  .baseBrightness = 30,
  .motionBrightness = 100,
  .lastUpdate = 0,
  .manualMode = false,       // Start in app mode by default
  .manualModeEndTime = 0,
  .currentPower = 0.0,
  .totalEnergy = 0.0,
  .ledWorking = {true, true, true},
  .currentTime = "00:00:00",
  .weatherCondition = "clear",
  .sunriseTime = "06:00:00",
  .sunsetTime = "18:00:00",
  .lastMotionTime = 0,
  .lastPIR1Time = 0,
  .lastPIR2Time = 0,
  .lastPIR3Time = 0
};

// Interrupt Handlers with Debouncing
void IRAM_ATTR handlePIR1() {
  unsigned long now = millis();
  if (now - sysState.lastPIR1Time > DEBOUNCE_TIME) {
    sysState.motionDetected = true;
    sysState.lastTrigger = now;
    sysState.lastMotionTime = now;
    sysState.lastPIR1Time = now;
  }
}

void IRAM_ATTR handlePIR2() {
  unsigned long now = millis();
  if (now - sysState.lastPIR2Time > DEBOUNCE_TIME) {
    sysState.motionDetected = true;
    sysState.lastTrigger = now;
    sysState.lastMotionTime = now;
    sysState.lastPIR2Time = now;
  }
}

void IRAM_ATTR handlePIR3() {
  unsigned long now = millis();
  if (now - sysState.lastPIR3Time > DEBOUNCE_TIME) {
    sysState.motionDetected = true;
    sysState.lastTrigger = now;
    sysState.lastMotionTime = now;
    sysState.lastPIR3Time = now;
  }
}

void setup() {
  Serial.begin(115200);
  delay(2000);
  
  // Initialize hardware
  pinMode(LED1_PIN, OUTPUT);
  pinMode(LED2_PIN, OUTPUT);
  pinMode(LED3_PIN, OUTPUT);
  analogWrite(LED1_PIN, 0); // Start with LEDs off
  analogWrite(LED2_PIN, 0);
  analogWrite(LED3_PIN, 0);

  // PIR sensor setup with pull-down resistors
  pinMode(PIR1_PIN, INPUT_PULLDOWN);
  pinMode(PIR2_PIN, INPUT_PULLDOWN);
  pinMode(PIR3_PIN, INPUT_PULLDOWN);
  
  // Attach interrupts
  attachInterrupt(digitalPinToInterrupt(PIR1_PIN), handlePIR1, RISING);
  attachInterrupt(digitalPinToInterrupt(PIR2_PIN), handlePIR2, RISING);
  attachInterrupt(digitalPinToInterrupt(PIR3_PIN), handlePIR3, RISING);

  // Connect to WiFi
  connectToWiFi();
  loadInitialConfig();

  // // Determine initial brightness based on LDR
  // updateBrightnessFromLDR();
  
  // LED test sequence
  Serial.println("Testing LEDs...");
  for (int i = 0; i < 3; i++) {
    setAllLEDs(50);
    delay(500);
    setAllLEDs(0);
    delay(500);
  }
  setAllLEDs(sysState.baseBrightness);
  
  Serial.println("System initialized");
}

void loop() {
  unsigned long now = millis();
  
  // Handle mode switching
  if (!sysState.manualMode && sysState.manualModeEndTime > 0 && now >= sysState.manualModeEndTime) {
    sysState.manualMode = true;
    sysState.manualModeEndTime = 0; // Reset the end time
    Serial.println("Switching to manual mode");
    updateConfig();
    updateBrightnessFromLDR(); // Update brightness based on current conditions
    setAllLEDs(sysState.isSleeping ? SLEEP_BRIGHTNESS : sysState.baseBrightness);
  }

  // Update brightness based on LDR in manual mode
  if (sysState.manualMode) {
    static unsigned long lastLDRCheck = 0;
    if (now - lastLDRCheck > 10000) { // Check LDR every 10 seconds
      updateBrightnessFromLDR();
      lastLDRCheck = now;
    }
  }

  // Handle motion detection in both modes
  handleMotionDetection(now);
  if(sysState.manualMode){
  delay(10000);
  }
  // Update API and energy periodically
  if (now - sysState.lastUpdate > UPDATE_INTERVAL) {
    updateFromAPI();
    sysState.lastUpdate = now;
  }
  
  static unsigned long lastEnergyUpdate = 0;
  if (now - lastEnergyUpdate >= ENERGY_UPDATE_INTERVAL) {
    updateEnergy();
    lastEnergyUpdate = now;
  }
  
  delay(100);
}

void handleMotionDetection(unsigned long now) {
  if (sysState.motionDetected) {
    Serial.println("Motion detected!");
    
    // Turn on all LEDs to motion brightness
    setAllLEDs(sysState.motionBrightness);
    sysState.isSleeping = false;
    
    // Reset motion flag
    sysState.motionDetected = false;
  }
  
  // Check if motion timeout has elapsed
  if (now - sysState.lastTrigger > MOTION_TIMEOUT && !sysState.isSleeping) {
    // Revert to base brightness
    setAllLEDs(sysState.baseBrightness);
    Serial.println("Motion timeout - reverting to base brightness");
  }
  
  // Check for sleep mode (no motion for SLEEP_TIMEOUT)
  if (now - sysState.lastMotionTime > SLEEP_TIMEOUT && !sysState.isSleeping) {
    setAllLEDs(SLEEP_BRIGHTNESS);
    sysState.isSleeping = true;
    Serial.println("Entering sleep mode");
  }
}

void updateBrightnessFromLDR() {
  int ldrValue = analogRead(LDR_PIN);
  Serial.print("LDR Value: ");
  Serial.println(ldrValue);
  Serial.print("Weather: ");
  Serial.println(sysState.weatherCondition);
  
  if (sysState.manualMode) {
    // Only update brightness in manual mode
    if (sysState.weatherCondition == "clear") {
      // Clear weather - use standard LDR-based brightness
      if (ldrValue > LDR_DARK_THRESHOLD) {
        // Dark conditions
        sysState.baseBrightness = 30;
        sysState.motionBrightness = 100;
      } else if (ldrValue < LDR_LIGHT_THRESHOLD) {
        // Light conditions
        sysState.baseBrightness = 0;
        sysState.motionBrightness = 0;
      } else {
        // Medium light conditions
        sysState.baseBrightness = 15;
        sysState.motionBrightness = 50;
      }
    } 
    else if (sysState.weatherCondition == "cloudy" || sysState.weatherCondition == "overcast") {
      // Cloudy weather - brighter than normal for same light levels
      if (ldrValue > LDR_DARK_THRESHOLD) {
        sysState.baseBrightness = 40;
        sysState.motionBrightness = 100;
      } else if (ldrValue < LDR_LIGHT_THRESHOLD) {
        sysState.baseBrightness = 5;
        sysState.motionBrightness = 20;
      } else {
        sysState.baseBrightness = 25;
        sysState.motionBrightness = 75;
      }
    }
    else if (sysState.weatherCondition == "rain" || sysState.weatherCondition == "snow") {
      // Rainy/snowy weather - brightest settings
      if (ldrValue > LDR_DARK_THRESHOLD) {
        sysState.baseBrightness = 50;
        sysState.motionBrightness = 100;
      } else if (ldrValue < LDR_LIGHT_THRESHOLD) {
        sysState.baseBrightness = 10;
        sysState.motionBrightness = 30;
      } else {
        sysState.baseBrightness = 35;
        sysState.motionBrightness = 85;
      }
    }
    else {
      // Default case for other weather conditions
      sysState.baseBrightness = 30;
      sysState.motionBrightness = 100;
    }
    
    Serial.print("Updated brightness - Base: ");
    Serial.print(sysState.baseBrightness);
    Serial.print(", Motion: ");
    Serial.println(sysState.motionBrightness);
  }
}

// LED control functions
void setAllLEDs(int brightness) {
  // Map 0-100 brightness to 0-255 for analogWrite
  int pwmValue = brightness;
  
  if (sysState.ledWorking[0]) analogWrite(LED1_PIN, pwmValue);
  if (sysState.ledWorking[1]) analogWrite(LED2_PIN, pwmValue);
  if (sysState.ledWorking[2]) analogWrite(LED3_PIN, pwmValue);
  
  Serial.print("Setting all LEDs to: ");
  Serial.print(brightness);
  Serial.println("%");
}

void connectToWiFi() {
  WiFi.begin(ssid, password);
  Serial.print("Connecting to WiFi");
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println();
  Serial.println("WiFi connected");
  Serial.print("IP address: ");
  Serial.println(WiFi.localIP());
}

void loadInitialConfig() {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("WiFi not connected!");
    return;
  }

  HTTPClient http;
  String endpoint = String(serverUrl) + "/api/neolight/" + deviceId;
  http.begin(endpoint.c_str());
  
  int httpCode = http.GET();
  
  if (httpCode == HTTP_CODE_OK) {
    String payload = http.getString();
    DynamicJsonDocument doc(1024);
    deserializeJson(doc, payload);
    
    if (doc.containsKey("currentMode")) {
      String mode = doc["currentMode"].as<String>();
      sysState.manualMode = mode == "manual";
      Serial.print("Initial mode: ");
      Serial.println(mode);
    }

    if (!sysState.manualMode && doc.containsKey("appControlDuration")) {
      int durationMinutes = doc["appControlDuration"].as<int>();
      sysState.manualModeEndTime = millis() + (durationMinutes * 60000);
      Serial.print("App control duration set to ");
      Serial.print(durationMinutes);
      Serial.println(" minutes");
    }
    
    // Load base and motion brightness
    if (doc.containsKey("baseBrightness")) {
      sysState.baseBrightness = doc["baseBrightness"];
      Serial.print("Base brightness: ");
      Serial.println(sysState.baseBrightness);
    }
    if (doc.containsKey("motionBrightness")) {
      sysState.motionBrightness = doc["motionBrightness"];
      Serial.print("Motion brightness: ");
      Serial.println(sysState.motionBrightness);
    }

    // Load LED working status
    for (int i = 0; i < 3; i++) {
      String key = "led" + String(i+1) + "Working";
      if (doc.containsKey(key.c_str())) {
        sysState.ledWorking[i] = doc[key.c_str()];
        Serial.print("LED ");
        Serial.print(i+1);
        Serial.print(" working: ");
        Serial.println(sysState.ledWorking[i] ? "YES" : "NO");
      }
    }

    if (doc.containsKey("time")) {
      sysState.currentTime = doc["time"].as<String>();
      Serial.print("Current time: ");
      Serial.println(sysState.currentTime);
    }
    if (doc.containsKey("weather")) {
      sysState.weatherCondition = doc["weather"].as<String>();
      Serial.print("Weather: ");
      Serial.println(sysState.weatherCondition);
    }
    if (doc.containsKey("sunrise")) {
      sysState.sunriseTime = doc["sunrise"].as<String>();
      Serial.print("Sunrise: ");
      Serial.println(sysState.sunriseTime);
    }
    if (doc.containsKey("sunset")) {
      sysState.sunsetTime = doc["sunset"].as<String>();
      Serial.print("Sunset: ");
      Serial.println(sysState.sunsetTime);
    }
  } else {
    Serial.printf("HTTP request failed with code %d\n", httpCode);
  }
  
  http.end();
}

void updateFromAPI() {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("WiFi disconnected, attempting to reconnect...");
    connectToWiFi();
    return;
  }

  HTTPClient http;
  String endpoint = String(serverUrl) + "/api/neolight/" + deviceId;
  http.begin(endpoint.c_str());
  
  int httpCode = http.GET();
  if (httpCode == HTTP_CODE_OK) {
    String payload = http.getString();
    DynamicJsonDocument doc(1024);
    deserializeJson(doc, payload);
    
    if (sysState.manualMode) {
      sysState.manualMode = doc["currentMode"] == "manual";
      Serial.print("Updated mode: ");
      Serial.println(sysState.manualMode ? "MANUAL" : "APP");
      
      if (sysState.manualMode && doc.containsKey("appControlDuration")) {
        int durationMinutes = doc["appControlDuration"].as<int>();
        sysState.manualModeEndTime =  millis() + (durationMinutes * 60000);
        Serial.print("App control duration updated to ");
        Serial.print(durationMinutes);
        Serial.println(" minutes");
      } else {
        sysState.manualModeEndTime = 0;
      }
    }
    
    if(!sysState.manualMode){
    if (doc.containsKey("baseBrightness")) {
      sysState.baseBrightness = doc["baseBrightness"];
      Serial.print("Updated base brightness: ");
      Serial.println(sysState.baseBrightness);
    }
    if (doc.containsKey("motionBrightness")) {
      sysState.motionBrightness = doc["motionBrightness"];
      Serial.print("Updated motion brightness: ");
      Serial.println(sysState.motionBrightness);
    }
    }
    
    // Update LED working status
    if (doc.containsKey("led1Working")) {
      sysState.ledWorking[0] = doc["led1Working"].as<bool>();
      Serial.print("LED1 working: ");
      Serial.println(sysState.ledWorking[0] ? "YES" : "NO");
    }
    if (doc.containsKey("led2Working")) {
      sysState.ledWorking[1] = doc["led2Working"].as<bool>();
      Serial.print("LED2 working: ");
      Serial.println(sysState.ledWorking[1] ? "YES" : "NO");
    }
    if (doc.containsKey("led3Working")) {
      sysState.ledWorking[2] = doc["led3Working"].as<bool>();
      Serial.print("LED3 working: ");
      Serial.println(sysState.ledWorking[2] ? "YES" : "NO");
    }
    
    if (doc.containsKey("time")) {
      sysState.currentTime = doc["time"].as<String>();
    }
    if (doc.containsKey("weather")) {
      sysState.weatherCondition = doc["weather"].as<String>();
    }
    if (doc.containsKey("sunrise")) {
      sysState.sunriseTime = doc["sunrise"].as<String>();
    }
    if (doc.containsKey("sunset")) {
      sysState.sunsetTime = doc["sunset"].as<String>();
    }
    
    // Update LEDs immediately after config change
    if(!sysState.manualMode){
    if (sysState.motionDetected) {
      setAllLEDs(sysState.motionBrightness);
    } else if (sysState.isSleeping) {
      setAllLEDs(SLEEP_BRIGHTNESS);
    } else {
      setAllLEDs(sysState.baseBrightness);
    }
  }} else {
    Serial.printf("HTTP update request failed with code %d\n", httpCode);
  }
  http.end();
}

void updateEnergy() {
  sysState.currentPower = 0.0;
  
  // Calculate power based on current LED states
  int brightness = 0;
  if (sysState.isSleeping) {
    brightness = SLEEP_BRIGHTNESS;
  } else if (sysState.motionDetected || (millis() - sysState.lastTrigger < MOTION_TIMEOUT)) {
    brightness = sysState.motionBrightness;
  } else {
    brightness = sysState.baseBrightness;
  }
  
  // Calculate power for all working LEDs
  for (int i = 0; i < 3; i++) {
    if (sysState.ledWorking[i]) {
      sysState.currentPower += brightness * 0.1; // 0.1W per 100% brightness per LED
    }
  }
  
  // Update total energy (kWh)
  sysState.totalEnergy += sysState.currentPower * (ENERGY_UPDATE_INTERVAL / 3600000.0);
  
  // Update server with energy data
  updateConfig();
}

void updateConfig() {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("WiFi not connected, skipping config update");
    return;
  }

  HTTPClient http;
  String endpoint = String(serverUrl) + "/api/neolight/" + deviceId;
  http.begin(endpoint.c_str());
  http.addHeader("Content-Type", "application/json");
  
  DynamicJsonDocument doc(512);
  doc["currentPower"] = sysState.currentPower;
  doc["totalEnergy"] = sysState.totalEnergy;
  doc["led1Working"] = sysState.ledWorking[0];
  doc["led2Working"] = sysState.ledWorking[1];
  doc["led3Working"] = sysState.ledWorking[2];
  doc["currentMode"] = sysState.manualMode ? "manual" : "app";
  
  String payload;
  serializeJson(doc, payload);
  int httpCode = http.PUT(payload);
  
  if (httpCode != HTTP_CODE_OK) {
    Serial.printf("Config update failed with code %d\n", httpCode);
  }
  
  http.end();
}