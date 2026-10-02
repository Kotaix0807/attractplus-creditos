#define COINBANK_PIN 2

void setup(){
    Serial.begin(9600);            
    pinMode(COINBANK_PIN, OUTPUT);
}


void loop() {
    if (Serial.available()) {
        int coinSwitch = Serial.parseInt();
        digitalWrite(COINBANK_PIN, coinSwitch ? LOW : HIGH);
    }
    delay(100);
  }
