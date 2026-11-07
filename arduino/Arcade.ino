// Arduino de la cabina: driver de los LEDs de los botones (PCA9685) + rele del
// monedero. Sustituye al display de 7 segmentos de cabina.ino (descartado).
//
// Lo alimenta un solo demonio, arduino/moneyBank.py, por el puerto serie a
// 115200. Cada mensaje es una letra, un valor y un salto de linea. La letra es
// lo que permite compartir el cable (con numeros a secas no se sabria si un "1"
// es "rele encendido" o "anima con el efecto 1"):
//
//   M0 / M1     rele del monedero: 1 = acepta monedas (hay partida)
//   L<n>        brillo global 0..255 (escala todos los LEDs, no el rele)
//   A<n>        corre la animacion de atraccion n (0 = ninguna); 8 = show rotatorio
//   B<hex>      botones de MAME: respiracion suave en los LEDs de la mascara de
//               13 bits (B1FFF = todos, B0 = ninguno)
//   P<ch>,<v>   pinta el LED ch (0..12) a brillo v (0..255); lo usa el minijuego
//               del PC, que manda solo los que cambian
//   X           apaga todos los LEDs (reinicio al entrar/salir del minijuego)
//
// La logica de los juegos NO vive aqui: el PC la lleva y pinta con P/X. Aqui solo
// estan las animaciones de atraccion y la respiracion de los botones.
//
// Detalle a fondo: docs/minijuegos.md.

#include <Wire.h>
#include <Adafruit_PWMServoDriver.h>

Adafruit_PWMServoDriver pwm = Adafruit_PWMServoDriver(0x40);

const int NUM_LEDS = 13;
const int CANAL_MONEDERO = 13; // canal del PCA9685 junto al LED 12
bool monederoEncendido = false;
int brilloGlobal = 255;        // escala de todos los LEDs (no del rele)

// Modos del driver. El ultimo comando manda; solo uno a la vez.
enum { M_OFF, M_ANIM, M_BOTONES, M_PINTA };
byte modo = M_OFF;
int animActual = 8;              // efecto de atraccion vigente (8 = show)
unsigned mascaraBotones = 0;     // LEDs a respirar en M_BOTONES

// Orden en zigzag para las animaciones esteticas
const int ordenZigzag[NUM_LEDS] = {
  0,          // Boton Extra
  1, 8, 6,    // J1 Fila Arriba
  2, 7, 5,    // J1 Fila Abajo
  3, 10, 12,  // J2 Fila Arriba
  4, 9, 11    // J2 Fila Abajo
};

// Grilla 2x6 (fila x columna) para las animaciones por columnas
const int grillaLed[2][6] = {
  {1, 8, 6, 3, 10, 12}, // Fila 0: Arriba
  {2, 7, 5, 4, 9, 11}   // Fila 1: Abajo
};

unsigned long ultimoCambioShow = 0;
int subModoShow = 0;
const int modosShow[] = {1, 2, 3, 4, 5, 6, 7, 9, 10, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26};
const int NUM_SHOW = sizeof(modosShow) / sizeof(modosShow[0]);

// Estado compartido de los efectos (se reinicia al cambiar de efecto)
int brilloBuf[NUM_LEDS];
int fx[6];
unsigned long fxT = 0;
unsigned long msEfecto = 0;

// Linea que se esta recibiendo (se lee caracter a caracter, como cabina.ino).
char linea[16];
unsigned largo = 0;

void setup() {
  Serial.begin(115200);
  pwm.begin();
  pwm.setPWMFreq(1000);
  Wire.setClock(400000); // 13 escrituras I2C por frame: a 100kHz se nota el retardo
  randomSeed(analogRead(A0));

  fijarMonedero(false); // el PCA9685 no se reinicia con el Arduino: forzar estado conocido
  apagarTodos();
  modo = M_ANIM;            // arranca ANIMANDO (atraccion): asi la placa anima aunque
  ultimoCambioShow = millis(); // no haya demonio todavia; el demonio luego confirma o cambia
}

// Escala por el brillo global, salvo el rele (que es on/off puro).
void fijarCanalFisico(int canalFisico, int brillo) {
  if (canalFisico != CANAL_MONEDERO)
    brillo = (int)((long)brillo * brilloGlobal / 255);
  if (brillo <= 0) {
    pwm.setPWM(canalFisico, 0, 4096);
  } else if (brillo >= 4095) {
    pwm.setPWM(canalFisico, 4096, 0);
  } else {
    pwm.setPWM(canalFisico, 0, brillo);
  }
}

void fijarMonedero(bool encendido) {
  monederoEncendido = encendido;
  fijarCanalFisico(CANAL_MONEDERO, encendido ? 4095 : 0); // 100% o 0%, sin PWM intermedio
}

void apagarTodos() {
  for (int i = 0; i < 16; i++) if (i != CANAL_MONEDERO) pwm.setPWM(i, 0, 4096);
}

void fijarColumna(int col, int brillo) {
  if (col == 0) { fijarCanalFisico(0, brillo); return; }
  fijarCanalFisico(grillaLed[0][col - 1], brillo);
  fijarCanalFisico(grillaLed[1][col - 1], brillo);
}

// ============================================================================
// PROTOCOLO SERIE
// ============================================================================
void leerSerie() {
  while (Serial.available()) {
    char c = Serial.read();
    if (c == '\n' || c == '\r') {
      if (largo > 0) { linea[largo] = '\0'; procesarLinea(); largo = 0; }
    } else if (largo < sizeof(linea) - 1) {
      linea[largo++] = c;
    }
  }
}

void cambiarModo(byte m) {
  if (modo != m) { modo = m; apagarTodos(); } // limpia LEDs colgados del modo anterior
}

void procesarLinea() {
  char *arg = linea + 1;
  switch (linea[0]) {
    case 'M':
      fijarMonedero(atoi(arg) != 0);
      break;
    case 'L':
      brilloGlobal = constrain(atoi(arg), 0, 255);
      break;
    case 'A': {
      int n = atoi(arg);
      if (n <= 0) { modo = M_OFF; apagarTodos(); }
      else { animActual = n; if (n == 8) ultimoCambioShow = millis(); cambiarModo(M_ANIM); }
      break;
    }
    case 'B': {
      unsigned m = (unsigned)strtol(arg, NULL, 16);
      if (m == 0) { modo = M_OFF; apagarTodos(); }
      else { mascaraBotones = m; cambiarModo(M_BOTONES); }
      break;
    }
    case 'P': {
      char *coma = strchr(arg, ',');
      if (coma) {
        *coma = '\0';
        int ch = atoi(arg);
        int v = constrain(atoi(coma + 1), 0, 255);
        if (ch >= 0 && ch < NUM_LEDS) {
          modo = M_PINTA; // el PC controla; el loop no pisa los LEDs
          fijarCanalFisico(ch, (int)((long)v * 4095 / 255));
        }
      }
      break;
    }
    case 'X':
      apagarTodos();
      modo = M_PINTA;
      break;
  }
}

// Respiracion suave de los botones que usa el juego (modo M_BOTONES)
void animacionBotones() {
  int b = (int)(pow((sin(millis() * 0.004) + 1.0) * 0.5, 2) * 4095.0);
  for (int i = 0; i < NUM_LEDS; i++)
    fijarCanalFisico(i, ((mascaraBotones >> i) & 1) ? b : 0);
}

// ============================================================================
// ANIMACIONES (Clasicas + 2 Nuevas)  -- de ledArcadeTest.ino, sin cambios
// ============================================================================
void animacionZigzag() {
  float pos = fmod(msEfecto * 0.010, (float)NUM_LEDS);
  for (int i = 0; i < NUM_LEDS; i++) {
    float dist = pos - i;
    if (dist < 0) dist += NUM_LEDS;
    if (dist < 3.5) {
      float f = (3.5 - dist) / 3.5;
      fijarCanalFisico(ordenZigzag[i], (int)(f * f * 4095.0));
    } else {
      fijarCanalFisico(ordenZigzag[i], 0);
    }
  }
}

void animacionOla() {
  float t = msEfecto * 0.004;
  for (int i = 0; i < NUM_LEDS; i++) {
    float onda = (sin(t - (i * 0.48)) + 1.0) * 0.5;
    fijarCanalFisico(ordenZigzag[i], (int)(onda * onda * 4095.0));
  }
}

void animacionColumna2D() {
  float ciclo = fmod(msEfecto * 0.006, 12.0);
  float posCol = (ciclo < 6.0) ? ciclo : (12.0 - ciclo);
  for (int col = 0; col < 7; col++) {
    float dist = abs(posCol - col);
    int brillo = (dist < 1.8) ? (int)(pow((1.8 - dist) / 1.8, 2) * 4095.0) : 0;
    fijarColumna(col, brillo);
  }
}

void animacionVersus() {
  float s = sin(msEfecto * 0.005);
  int b1 = (int)(pow((s + 1.0) * 0.5, 2) * 4095.0);
  int b2 = (int)(pow((-s + 1.0) * 0.5, 2) * 4095.0);
  fijarCanalFisico(0, (int)((sin(msEfecto * 0.01) + 1.0) * 2000.0));
  for (int i = 1; i <= 6; i++) fijarCanalFisico(ordenZigzag[i], b1);
  for (int i = 7; i <= 12; i++) fijarCanalFisico(ordenZigzag[i], b2);
}

void animacionRebote() {
  float s = sin(msEfecto * 0.007);
  int bUp = (int)(pow((s + 1.0) * 0.5, 2) * 4095.0);
  int bDown = (int)(pow((-s + 1.0) * 0.5, 2) * 4095.0);
  fijarCanalFisico(0, bUp);
  for (int col = 0; col < 6; col++) {
    fijarCanalFisico(grillaLed[0][col], bUp);
    fijarCanalFisico(grillaLed[1][col], bDown);
  }
}

void animacionEstrellas() {
  if (random(0, 100) < 20) brilloBuf[random(0, NUM_LEDS)] = 4095;
  pintarBuf(0.88);
}

void animacionRespiracion() {
  int b = (int)(pow((sin(msEfecto * 0.0025) + 1.0) * 0.5, 2) * 4095.0);
  for (int i = 0; i < NUM_LEDS; i++) fijarCanalFisico(ordenZigzag[i], b);
}

void animacionLluviaNeon() {
  float paso = fmod(msEfecto * 0.007, 7.0);
  for (int col = 0; col < 7; col++) {
    float dist = abs(paso - col);
    int brillo = (dist < 1.2) ? (int)((1.2 - dist) / 1.2 * 4095.0) : 0;
    fijarColumna(col, brillo);
  }
}

void animacionRadar() {
  float radio = fmod(msEfecto * 0.005, 4.0);
  for (int i = 0; i < NUM_LEDS; i++) {
    float distCentro = abs(i - 6.0) * 0.3;
    float diff = abs(distCentro - radio);
    int brillo = (diff < 0.8) ? (int)((0.8 - diff) / 0.8 * 4095.0) : 0;
    fijarCanalFisico(ordenZigzag[i], brillo);
  }
}

// ============================================================================
// UTILIDADES PARA LOS EFECTOS
// ============================================================================
int curva(float x) { return (int)(x * x * 4095.0); }

int idxZ(int f, int col) { return (col < 3) ? 1 + f * 3 + col : 7 + f * 3 + (col - 3); }

void coordenadas(int i, int &f, int &col) {
  if (i == 0) { f = -1; col = -1; return; }
  int j = i - 1;
  f = (j % 6) / 3;
  col = (j / 6) * 3 + j % 3;
}

void pintarBuf(float decay) {
  for (int i = 0; i < NUM_LEDS; i++) {
    fijarCanalFisico(ordenZigzag[i], brilloBuf[i]);
    brilloBuf[i] = (int)(brilloBuf[i] * decay);
    if (brilloBuf[i] < 15) brilloBuf[i] = 0;
  }
}

// ============================================================================
// EFECTOS NUEVOS
// ============================================================================
void animacionLatido() {
  int t = msEfecto % 1200;
  float x = 0;
  if (t < 150) x = 1.0 - t / 150.0;
  else if (t >= 250 && t < 500) x = 0.7 * (1.0 - (t - 250) / 250.0);
  int b = curva(x);
  for (int i = 0; i < NUM_LEDS; i++) fijarCanalFisico(ordenZigzag[i], b);
}

void animacionFuegos() {
  if (msEfecto - fxT >= (fx[1] == 2 ? 700UL : 120UL)) {
    fxT = msEfecto;
    fx[1] = (fx[1] + 1) % 3;
    if (fx[1] == 0) fx[0] = random(0, 6);
    if (fx[1] == 2) {
      for (int c = fx[0] - 1; c <= fx[0] + 1; c++) {
        if (c < 0 || c > 5) continue;
        brilloBuf[idxZ(0, c)] = 4095;
        brilloBuf[idxZ(1, c)] = 2500;
      }
      if (fx[0] < 2) brilloBuf[0] = 4095;
    }
  }
  if (fx[1] < 2) brilloBuf[idxZ(1 - fx[1], fx[0])] = 1200;
  pintarBuf(0.9);
}

void animacionPingPong() {
  unsigned long paso = msEfecto / 110;
  int p = paso % 10;
  int col = (p < 6) ? p : 10 - p;
  int f = paso % 2;
  brilloBuf[idxZ(f, col)] = 4095;
  if (col == 0 || col == 5) brilloBuf[idxZ(1 - f, col)] = 4095;
  if (col == 0) brilloBuf[0] = 2000;
  pintarBuf(0.7);
}

void animacionSirena() {
  int t = msEfecto % 800;
  int s = t % 400;
  bool on = s < 360 && (s % 120) < 60;
  int b1 = (on && t < 400) ? 4095 : 0;
  int b2 = (on && t >= 400) ? 4095 : 0;
  fijarCanalFisico(0, b1);
  for (int f = 0; f < 2; f++)
    for (int col = 0; col < 6; col++) fijarCanalFisico(grillaLed[f][col], col < 3 ? b1 : b2);
}

int perimetro(int k) { return (k < 6) ? idxZ(0, k) : idxZ(1, 11 - k); }

void animacionRuleta() {
  if (fx[1] == 0) fx[1] = 25;
  if (fx[2] == 0) {
    if (msEfecto - fxT >= (unsigned long)fx[1]) {
      fxT = msEfecto;
      fx[0] = (fx[0] + 1) % 12;
      fx[1] += fx[1] / 10 + random(1, 4);
      if (fx[1] > 380) fx[2] = 1;
    }
    brilloBuf[perimetro(fx[0])] = 4095;
  } else {
    int b = ((msEfecto - fxT) / 120) % 2 ? 0 : 4095;
    brilloBuf[perimetro(fx[0])] = b;
    brilloBuf[0] = b;
    if (msEfecto - fxT >= 2000) { fx[1] = 25; fx[2] = 0; }
  }
  pintarBuf(0.8);
}

void animacionLlenado() {
  unsigned long t = msEfecto % 3600;
  int n;
  if (t < 1950) n = t / 150;
  else if (t < 2550) n = (((t - 1950) / 100) % 2) ? 0 : NUM_LEDS;
  else { n = 13 - (int)((t - 2550) / 80); if (n < 0) n = 0; }
  for (int i = 0; i < NUM_LEDS; i++) {
    int b = (i < n) ? 4095 : 0;
    if (t < 1950 && i == n) b = 500;
    fijarCanalFisico(ordenZigzag[i], b);
  }
}

void animacionTormenta() {
  if (fx[0] == 0 && random(0, 180) == 0) fx[0] = random(2, 5);
  if (fx[0] > 0 && random(0, 5) == 0) {
    for (int i = 0; i < NUM_LEDS; i++) brilloBuf[i] = 4095;
    fx[0]--;
  }
  for (int i = 0; i < NUM_LEDS; i++)
    if (brilloBuf[i] < 120) brilloBuf[i] = random(20, 120);
  pintarBuf(0.75);
}

void animacionFuego() {
  for (int i = 0; i < NUM_LEDS; i++) {
    int f, col;
    coordenadas(i, f, col);
    int minimo = (f == 1) ? 1800 : 300;
    brilloBuf[i] = constrain(brilloBuf[i] + (int)random(-500, 501), minimo, 4095);
    fijarCanalFisico(ordenZigzag[i], brilloBuf[i]);
  }
}

void animacionBinario() {
  unsigned long n = msEfecto / 200;
  for (int i = 1; i < NUM_LEDS; i++) fijarCanalFisico(ordenZigzag[i], ((n >> (i - 1)) & 1) ? 4095 : 0);
  fijarCanalFisico(0, (msEfecto % 200) < 40 ? 1500 : 0);
}

void animacionCortina() {
  unsigned long c = msEfecto % 2400;
  float r = (c < 1200) ? c / 300.0 : (2400 - c) / 300.0;
  for (int i = 0; i < NUM_LEDS; i++) {
    int f, col;
    coordenadas(i, f, col);
    float d = abs(col - 2.5);
    fijarCanalFisico(ordenZigzag[i], curva(constrain(r - d, 0.0, 1.0)));
  }
}

void animacionAjedrez() {
  int fase = (msEfecto / 350) % 2;
  for (int i = 0; i < NUM_LEDS; i++) {
    int f, col;
    coordenadas(i, f, col);
    fijarCanalFisico(ordenZigzag[i], ((f + col + 2) % 2 == fase) ? 4095 : 0);
  }
}

void animacionGotas() {
  for (int col = 0; col < 6; col++) {
    if (fx[col] == 0 && random(0, 50) == 0) fx[col] = 1;
    if (fx[col] == 0) continue;
    if (fx[col] == 1) brilloBuf[idxZ(0, col)] = 4095;
    if (fx[col] == 8) brilloBuf[idxZ(1, col)] = 4095;
    if (++fx[col] > 8) fx[col] = 0;
  }
  brilloBuf[0] = 400;
  pintarBuf(0.85);
}

void animacionCometas() {
  int p = (msEfecto / 90) % 9;
  if (p < 6) {
    brilloBuf[idxZ(0, p)] = 4095;
    brilloBuf[idxZ(1, 5 - p)] = 4095;
  }
  if (p == 2 || p == 3) brilloBuf[0] = 4095;
  pintarBuf(0.8);
}

void animacionDisco() {
  float t = msEfecto * 0.001;
  for (int i = 0; i < NUM_LEDS; i++) {
    float s = sin(t * (2 + i % 5) + i * 1.7);
    fijarCanalFisico(ordenZigzag[i], curva((s + 1.0) * 0.5));
  }
}

void animacionOndaImpacto() {
  unsigned long t = msEfecto - fxT;
  if (t >= 1300) { fxT = msEfecto; fx[0] = random(0, 2); fx[1] = random(0, 6); t = 0; }
  float r = t / 180.0;
  for (int i = 0; i < NUM_LEDS; i++) {
    int f, col;
    coordenadas(i, f, col);
    float d = abs(f - fx[0]) + abs(col - fx[1]);
    fijarCanalFisico(ordenZigzag[i], curva(constrain(1.0 - abs(d - r), 0.0, 1.0)));
  }
}

void ejecutarAnimacion(int m) {
  static int anterior = -1;
  static unsigned long inicio = 0;
  if (m != anterior) { // efecto nuevo: estado limpio
    anterior = m;
    inicio = millis();
    fxT = 0;
    for (int i = 0; i < 6; i++) fx[i] = 0;
    for (int i = 0; i < NUM_LEDS; i++) brilloBuf[i] = 0;
  }
  msEfecto = millis() - inicio;

  switch (m) {
    case 1: animacionZigzag(); break;
    case 2: animacionOla(); break;
    case 3: animacionColumna2D(); break;
    case 4: animacionVersus(); break;
    case 5: animacionRebote(); break;
    case 6: animacionEstrellas(); break;
    case 7: animacionRespiracion(); break;
    case 9: animacionLluviaNeon(); break;
    case 10: animacionRadar(); break;
    case 12: animacionLatido(); break;
    case 13: animacionFuegos(); break;
    case 14: animacionPingPong(); break;
    case 15: animacionSirena(); break;
    case 16: animacionRuleta(); break;
    case 17: animacionLlenado(); break;
    case 18: animacionTormenta(); break;
    case 19: animacionFuego(); break;
    case 20: animacionBinario(); break;
    case 21: animacionCortina(); break;
    case 22: animacionAjedrez(); break;
    case 23: animacionGotas(); break;
    case 24: animacionCometas(); break;
    case 25: animacionDisco(); break;
    case 26: animacionOndaImpacto(); break;
  }
}

void loop() {
  leerSerie();

  switch (modo) {
    case M_ANIM:
      if (animActual == 8) {
        if (millis() - ultimoCambioShow >= 8000) {
          ultimoCambioShow = millis();
          subModoShow = (subModoShow + 1) % NUM_SHOW;
        }
        ejecutarAnimacion(modosShow[subModoShow]);
      } else {
        ejecutarAnimacion(animActual);
      }
      break;
    case M_BOTONES:
      animacionBotones();
      break;
    case M_OFF:
    case M_PINTA:
      break; // los LEDs quedan como estan (apagados, o lo que pinto el PC)
  }

  delay(15);
}
