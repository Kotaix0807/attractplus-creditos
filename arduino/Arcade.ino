#define MAX_CREDITS 99
#define LED_PIN 2

const int NUM_LEDS = 3;
const int ledPins[NUM_LEDS] = {4, 5, 6};
const int botonSuma = 2;
const int botonResta = 3;

int contador = 0;

void setup() {
  Serial.begin(9600);
  pinMode(LED_PIN, OUTPUT);
}

void loop() {
  if (Serial.available()) {
    int creditos = Serial.parseInt();

    if (creditos > 0) {
      contador = creditos;
      if (contador > MAX_CREDITS)
        contador = MAX_CREDITS;

      for (int i = 0; i < contador; i++) {
        digitalWrite(LED_PIN, HIGH);
        delay(100);
        digitalWrite(LED_PIN, LOW);
        delay(100);                     // el apagado tambien tiene que durar
      }
    }
  }
}

void actualizarLeds() {
  for (int i = 0; i < NUM_LEDS; i++) {
    if (i < contador)
      digitalWrite(ledPins[i], HIGH);
    else
      digitalWrite(ledPins[i], LOW);
  }
}
