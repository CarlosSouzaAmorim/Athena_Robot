#include <WiFi.h>
#include <HTTPClient.h>
#include <Adafruit_SSD1306.h>
#include <ArduinoJson.h>

// ---------------- OLED CONFIG ----------------
#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 64
#define OLED_RESET -1
#define I2C_ADDR 0x3C

Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, OLED_RESET);

// ---------------- WIFI CONFIG ----------------
// Default credentials - can be changed via serial
String wifiSSID = "TP-LINK_7EF4";
String wifiPassword = "casa7654";

// Server configuration
String serverIP = "192.168.0.118";
int serverPort = 5005;
String serverURL = "http://" + serverIP + ":" + String(serverPort) + "/ask_stream";

// New: model string reported by server
String serverModel = "unknown";

// WiFi connection state
bool wifiConnected = false;
unsigned long lastWifiAttempt = 0;
const unsigned long WIFI_RETRY_INTERVAL = 20000; // 20 seconds

// ---------------- BUTTONS ----------------
#define BTN1 12
#define BTN2 14

String q1 = "In one sentence, explain what the ESP32 does.";
String q2 = "In one sentence, define IA.";

// Add this variable to store the full response
String fullResponse = "";

// ---------------- DISPLAY HELPERS ----------------
int cursorY = 0;
String currentLine = "";
String displayBuffer[8];  // 8 lines max (64px / 8px per line)
int bufferLines = 0;

// Forward declarations - REMOVE DEFAULT VALUES FROM DECLARATIONS
void addLineToBuffer(String line);
void refreshDisplay();
void clearDisplayText();
void printToken(String t);
bool connectToWiFi(String ssid, String password, int timeout); // No default value here
void attemptWiFiConnection();
void saveWiFiCredentials(String ssid, String password);
void askOllamaStream(String question);
void fetchServerModel();
void displayWelcome();
void processSerialCommand(String cmd);

void addLineToBuffer(String line) {
  if (bufferLines < 8) {
    displayBuffer[bufferLines++] = line;
  } else {
    // Scroll: shift all lines up
    for (int i = 0; i < 7; i++) {
      displayBuffer[i] = displayBuffer[i + 1];
    }
    displayBuffer[7] = line;
  }
}

void refreshDisplay() {
  display.clearDisplay();
  display.setCursor(0, 0);
  for (int i = 0; i < bufferLines; i++) {
    display.println(displayBuffer[i]);
  }
  display.display();
}

void clearDisplayText() {
  display.clearDisplay();
  display.setCursor(0, 0);
  display.setTextSize(1);
  display.setTextColor(SSD1306_WHITE);
  bufferLines = 0;
  currentLine = "";
  display.display();
}

void printToken(String t) {
  currentLine += t;

  // número máximo aproximado de chars por linha (fonte 6px)
  const int maxChars = SCREEN_WIDTH / 6;

  // Processar todas as quebras explícitas e empacotamento
  while (true) {
    int newlinePos = currentLine.indexOf('\n');
    if (newlinePos != -1) {
      String part = currentLine.substring(0, newlinePos);
      // empacotar se necessário
      while (part.length() > maxChars) {
        addLineToBuffer(part.substring(0, maxChars));
        part = part.substring(maxChars);
      }
      addLineToBuffer(part);
      currentLine = currentLine.substring(newlinePos + 1);
      continue;
    }

    if (currentLine.length() > maxChars) {
      String wrapped = currentLine.substring(0, maxChars);
      addLineToBuffer(wrapped);
      currentLine = currentLine.substring(maxChars);
      continue;
    }
    break;
  }

  refreshDisplay();
}

// ---------------- WIFI MANAGEMENT ----------------
// DEFAULT VALUE ONLY IN FUNCTION DEFINITION, NOT IN DECLARATION
bool connectToWiFi(String ssid, String password, int timeout = 15000) {
  clearDisplayText();
  display.println("Connecting to:");
  display.println(ssid);
  display.display();
  
  Serial.println("Attempting to connect to WiFi: " + ssid);
  
  WiFi.begin(ssid.c_str(), password.c_str());
  
  unsigned long startTime = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - startTime < timeout) {
    delay(500);
    Serial.print(".");
    display.print(".");
    display.display();
  }
  
  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\nWiFi connected!");
    Serial.println("IP address: " + WiFi.localIP().toString());
    wifiConnected = true;
    return true;
  } else {
    Serial.println("\nWiFi connection failed!");
    wifiConnected = false;
    return false;
  }
}

void attemptWiFiConnection() {
  if (millis() - lastWifiAttempt > WIFI_RETRY_INTERVAL) {
    Serial.println("Attempting WiFi connection with current credentials...");
    if (connectToWiFi(wifiSSID, wifiPassword)) {
      fetchServerModel();
      displayWelcome();
    } else {
      clearDisplayText();
      display.println("WiFi failed!");
      display.println("Use serial to set:");
      display.println("setwifi:ssid,pass");
      display.println("Current: " + wifiSSID);
      display.display();
      delay(WIFI_RETRY_INTERVAL) ; // TEMPO MAIOR PARA INSERIR COMANDO NA SERIAL
    }
    lastWifiAttempt = millis();
  }
}

void saveWiFiCredentials(String ssid, String password) {
  wifiSSID = ssid;
  wifiPassword = password;
  
  // Here you could save to EEPROM for persistence
  // For now, we just update the variables
  Serial.println("WiFi credentials updated:");
  Serial.println("SSID: " + wifiSSID);
  Serial.println("Password: " + wifiPassword);
}

// New: fetch model info from server /model endpoint
void fetchServerModel() {
  if (!wifiConnected) return;
  
  HTTPClient http;
  String url = "http://" + serverIP + ":" + String(serverPort) + "/model";
  http.begin(url);
  int code = http.GET();
  if (code == 200) {
    String body = http.getString();
    DynamicJsonDocument doc(256);
    auto err = deserializeJson(doc, body);
    if (!err && doc.containsKey("model")) {
      serverModel = doc["model"].as<String>();
    } else {
      serverModel = "parse_err";
    }
  } else {
    serverModel = "no_resp";
  }
  http.end();
}

void displayWelcome() {
  clearDisplayText();
  display.setTextSize(1);
  display.setTextColor(SSD1306_WHITE);
  display.println("Conectado: Ready!");
  display.println("SSID: " + wifiSSID);
  display.println("IP: " + WiFi.localIP().toString());
  display.println("Server: " + serverIP);
  display.println("Port: " + String(serverPort));
  display.println("Model: " + serverModel); // show model here
  display.display();
  delay(500);
}

// ---------------- STREAMING REQUEST ----------------
void askOllamaStream(String question) {
  if (!wifiConnected) {
    clearDisplayText();
    display.println("No WiFi!");
    display.println("Connect first");
    display.display();
    delay(2000);
    displayWelcome();
    return;
  }

  WiFiClient client;

  if (!client.connect(serverIP.c_str(), serverPort)) {
    clearDisplayText();
    display.println("Conn failed");
    display.display();
    delay(500);
    return;
  }

  String payload = "{\"question\":\"" + question + "\"}";

  client.println("POST /ask_stream HTTP/1.1");
  client.println("Host: " + serverIP);
  client.println("Content-Type: application/json");
  client.println("Content-Length: " + String(payload.length()));
  client.println();
  client.print(payload);

  // Não limpar a tela aqui — já mostramos a query + "Waiting response..."
  fullResponse = "";  // Reset response buffer

  bool headerEnded = false;
  bool firstToken = true;

  while (client.connected()) {
    String line = client.readStringUntil('\n');
    if (line.length() == 0) continue;

    if (!headerEnded) {
      if (line == "\r") headerEnded = true;
      continue;
    }

    DynamicJsonDocument doc(512);
    auto err = deserializeJson(doc, line);
    if (!err) {
      String token = doc["response"].as<String>();

      // Remover a linha "Waiting response..." antes do primeiro token
      if (firstToken) {
        if (bufferLines > 0 && displayBuffer[bufferLines - 1] == "Waiting response...") {
          bufferLines--;            // remove última linha
        }
        firstToken = false;
      }

      printToken(token);
      fullResponse += token;  // Accumulate response
    }
  }

  // Ao terminar a stream, garantir que o que restou em currentLine seja exibido
  if (currentLine.length() > 0) {
    // empacotar a última linha residual
    const int maxChars = SCREEN_WIDTH / 6;
    while (currentLine.length() > 0) {
      if (currentLine.length() <= maxChars) {
        addLineToBuffer(currentLine);
        currentLine = "";
      } else {
        addLineToBuffer(currentLine.substring(0, maxChars));
        currentLine = currentLine.substring(maxChars);
      }
    }
    refreshDisplay();
  }

  client.stop();

  // Send complete response to serial
  Serial.println("\n--- SERVER RESPONSE ---");
  Serial.println(fullResponse);
  Serial.println("--- END RESPONSE ---\n");
}

void processSerialCommand(String cmd) {
  cmd.trim();
  
  if (cmd.startsWith("setwifi:")) {
    // Format: setwifi:ssid,password
    String credentials = cmd.substring(8);
    int commaPos = credentials.indexOf(',');
    
    if (commaPos != -1) {
      String newSSID = credentials.substring(0, commaPos);
      String newPassword = credentials.substring(commaPos + 1);
      
      saveWiFiCredentials(newSSID, newPassword);
      
      clearDisplayText();
      display.println("New WiFi set:");
      display.println("SSID: " + newSSID);
      display.println("Connecting...");
      display.display();
      
      if (connectToWiFi(newSSID, newPassword)) {
        fetchServerModel();
        displayWelcome();
      } else {
        clearDisplayText();
        display.println("WiFi connect");
        display.println("failed!");
        display.println("Check credentials");
        display.display();
        delay(3000);
        displayWelcome();
      }
    } else {
     
      Serial.println("Invalid format. Use: setwifi:ssid,password");
    }
  }
  else if (cmd.startsWith("setip:")) {
    serverIP = cmd.substring(6);
    // update URL if used elsewhere
    serverURL = "http://" + serverIP + ":" + String(serverPort) + "/ask_stream";
    // fetch model after change
    if (wifiConnected) {
      fetchServerModel();
    }
    clearDisplayText();
    display.println("IP updated to:");
    display.println(serverIP);
    display.display();
    delay(2000);
    displayWelcome();
  } 
  else if (cmd.startsWith("setport:")) {
    serverPort = cmd.substring(8).toInt();
    serverURL = "http://" + serverIP + ":" + String(serverPort) + "/ask_stream";
    if (wifiConnected) {
      fetchServerModel();
    }
    clearDisplayText();
    display.println("Port updated to:");
    display.println(String(serverPort));
    display.display();
    delay(2000);
    displayWelcome();
  }
  else if (cmd == "status") {
    Serial.println("=== STATUS ===");
    Serial.println("WiFi SSID: " + wifiSSID);
    Serial.println("WiFi Connected: " + String(wifiConnected ? "Yes" : "No"));
    if (wifiConnected) {
      Serial.println("IP: " + WiFi.localIP().toString());
    }
    Serial.println("Server: " + serverIP + ":" + String(serverPort));
    Serial.println("Model: " + serverModel);
    Serial.println("==============");
  }
  else if (cmd == "connect") {
    attemptWiFiConnection();
  }
  else if (cmd == "disconnect") {
    WiFi.disconnect();
    wifiConnected = false;
    clearDisplayText();
    display.println("WiFi disconnected");
    display.display();
    delay(2000);
    displayWelcome();
  }
  else {
    // Only process queries if WiFi is connected
    if (!wifiConnected) {
      Serial.println("Error: Not connected to WiFi. Use 'connect' or 'setwifi:ssid,pass'");
      return;
    }
    
    // Mostrar a query na tela (usando buffer) antes de enviar
    clearDisplayText();
    addLineToBuffer("Query:");
    addLineToBuffer(cmd);
    addLineToBuffer("Waiting response...");
    refreshDisplay();
    delay(1000);                 // esperar 1s antes de enviar
    askOllamaStream(cmd);
  }
}

// ---------------- SETUP ----------------
void setup() {
  Serial.begin(9600);

  pinMode(BTN1, INPUT_PULLUP);
  pinMode(BTN2, INPUT_PULLUP);

  Wire.begin(5, 4); // SDA, SCL

  if (!display.begin(SSD1306_SWITCHCAPVCC, I2C_ADDR)) {
    while (1);
  }

  clearDisplayText();
  display.println("ESP32 Ollama Client");
  display.println("Initializing...");
  display.display();
  delay(1000);

  // Attempt initial connection with default credentials
  if (connectToWiFi(wifiSSID, wifiPassword)) {
    fetchServerModel();
    displayWelcome();
  } else {
    clearDisplayText();
    display.println("WiFi failed!");
    display.println("Use serial cmd:");
    display.println("setwifi:ssid,pass");
    display.println("or 'connect' to retry");
    display.display();
  }
  
  Serial.println("\n=== ESP32 Ollama Client ===");
  Serial.println("Available commands:");
  Serial.println("setwifi:ssid,password  - Change WiFi credentials");
  Serial.println("setip:192.168.x.x      - Change server IP");
  Serial.println("setport:5005           - Change server port");
  Serial.println("status                  - Show current status");
  Serial.println("connect                 - Attempt WiFi connection");
  Serial.println("disconnect              - Disconnect WiFi");
  Serial.println("Your question here      - Send query to Ollama");
  Serial.println("===========================\n");
}

// ---------------- LOOP ----------------
void loop() {
  // Auto-reconnect logic
  if (!wifiConnected) {
    attemptWiFiConnection();
  }

  // ---- BUTTON 1 ----
  if (digitalRead(BTN1) == LOW && wifiConnected) {
    clearDisplayText();
    addLineToBuffer("Query:");
    addLineToBuffer(q1);         // mostrar a pergunta (via buffer)
    addLineToBuffer("Waiting response...");
    refreshDisplay();
    delay(1000);                 // esperar antes de enviar
    askOllamaStream(q1);
    delay(500);
  } else if (digitalRead(BTN1) == LOW && !wifiConnected) {
    clearDisplayText();
    display.println("No WiFi!");
    display.println("Connect first");
    display.display();
    delay(2000);
    displayWelcome();
  }

  // ---- BUTTON 2 ----
  if (digitalRead(BTN2) == LOW && wifiConnected) {
    clearDisplayText();
    addLineToBuffer("Query:");
    addLineToBuffer(q2);         // mostrar a pergunta (via buffer)
    addLineToBuffer("Waiting response...");
    refreshDisplay();
    delay(1000);                 // esperar antes de enviar
    askOllamaStream(q2);
    delay(500);
  } else if (digitalRead(BTN2) == LOW && !wifiConnected) {
    clearDisplayText();
    display.println("No WiFi!");
    display.println("Connect first");
    display.display();
    delay(2000);
    displayWelcome();
  }
  
  // ---- SERIAL INPUT ----
  if (Serial.available()) {
    String userInput = Serial.readStringUntil('\n');
    userInput.trim();

    if (userInput.length() > 0) {
      processSerialCommand(userInput);
    }
  }
}