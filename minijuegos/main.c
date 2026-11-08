// Frontend de los minijuegos de luces del panel (huevo de pascua).
//
// Lo lanza el plugin del frontend al pulsar P2 Start. Abre una ventana negra a
// pantalla completa (le roba el foco a Attract-Mode), lleva la logica de los dos
// juegos, el menu, los puntajes y el sonido, lee el mando por SDL, y pinta los
// LEDs del panel mandando lineas al demonio por el FIFO ~/.attract/arduino_fifo.
//
// La logica NO vive en el Arduino: aqui se decide todo y el Arduino solo enciende
// los LEDs que le pintamos con P<ch>,<v> / X. Protocolo y diseno: docs/minijuegos.md.
//
// COMO ESTA ORGANIZADO (de arriba a abajo):
//   1. ajustes y tablas        (que LED es cada celda, tiempos, colores)
//   2. FIFO / LEDs             (pintar el panel)
//   3. mando + mapa de botones (que boton fisico es cada celda)
//   4. ENTRADA                 (leerEntrada: UN solo sitio que traduce mando/teclado)
//   5. puntajes
//   6. dibujo en pantalla
//   7. calibracion
//   8. los dos juegos + fin de ronda
//   9. menu
//  10. main
//
// Para cambiar los controles: toca SOLO la seccion 4 (leerEntrada / teclaCelda).

#include <SDL2/SDL.h>
#include <SDL2/SDL_ttf.h>
#include <SDL2/SDL_mixer.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <stdarg.h>
#include <time.h>

// ============================ 1. AJUSTES Y TABLAS ============================

#define NUM_CELDAS  12       // los 12 botones de jugador (grilla 2x6)
#define NUM_LEDS    13       // + el boton extra (canal 0)
#define RONDA_MS    60000    // dura una partida
#define CELDA_SALIR (-2)     // codigo que devuelve el mapa para "el boton de salir"

// Celda (0..11, por filas: 0..5 arriba, 6..11 abajo) -> canal de LED del PCA.
// Sale de la grilla de Arcade.ino: arriba {1,8,6,3,10,12}, abajo {2,7,5,4,9,11}.
static const int CANAL[NUM_CELDAS] = { 1, 8, 6, 3, 10, 12,  2, 7, 5, 4, 9, 11 };

// Eje analogico: hay que cruzar UMBRAL para contar un movimiento, y volver por
// debajo de ZONA_MUERTA para poder contar el siguiente (asi un empujon = un paso).
#define UMBRAL       16000
#define ZONA_MUERTA  8000

static const SDL_Color BLANCO = { 235, 235, 235, 255 };
static const SDL_Color AMBAR  = { 255, 210,  40, 255 };
static const SDL_Color GRIS   = { 120, 120, 130, 255 };

// Que devuelve menu()/los juegos al volver. OJO: A_MENU=0 y A_SALIR=1, por eso
// las dos opciones de juego valen 2 y 3 (no 1, que chocaria con A_SALIR y haria
// que elegir el primer juego cerrara el programa).
enum { A_MENU, A_SALIR, JUEGO_META, JUEGO_TOPO };

// ------- estado global -------
static SDL_Window   *win;
static SDL_Renderer *ren;
static TTF_Font     *fuente, *fuenteBig;
static Mix_Chunk    *sfxOk, *sfxFail, *sfxTopo, *sfxWhack;
static Mix_Music    *musMenu, *musTopo, *musTopoFin, *musFin;
static int anchoV, altoV;
static int demo = 0;             // MINIJUEGOS_DEMO=1: ventana + teclado + panel en pantalla
static char rutaBase[1024];      // carpeta del ejecutable (de ahi salen fuente y sonidos)

static int fifoFd = -1;
static int ledEstado[NUM_LEDS];  // ultimo brillo enviado a cada canal (para mandar solo cambios)

static int recordMeta = 0, recordTopo = 0;

static void pantallaFin(int puntos, int record);   // se define en la seccion 8

static void rutaHome(char *buf, size_t n, const char *nombre) {
    const char *home = getenv("HOME");
    snprintf(buf, n, "%s/.attract/%s", home ? home : ".", nombre);
}

// Log de diagnostico a ~/.attract/minijuegos.log (para cazar por que se sale).
static void registro(const char *fmt, ...) {
    char ruta[1024];
    rutaHome(ruta, sizeof ruta, "minijuegos.log");
    FILE *f = fopen(ruta, "a");
    if (!f)
        return;
    va_list ap;
    va_start(ap, fmt);
    vfprintf(f, fmt, ap);
    va_end(ap);
    fputc('\n', f);
    fclose(f);
}

// Cambia el TONO de un sonido: devuelve una COPIA nueva de 'orig' reasampleada por
// 'factor' (2.0 = una octava mas agudo y la mitad de larga; 0.5 = una octava mas
// grave y el doble de larga; 1.0 = igual). SDL2_mixer no trae pitch, asi que se
// reasamplea el PCM a mano por interpolacion lineal.
//
// Uso:   Mix_Chunk *agudo = cambiarPitch(sfxOk, 1.5f);
//        Mix_PlayChannel(-1, agudo, 0);
//        ...y cuando ya no se use:  Mix_FreeChunk(agudo);
//
// Solo soporta audio de 16 bits (el formato con que se abre el mixer). Devuelve
// NULL si no puede; el que llama debe comprobarlo.
static Mix_Chunk *cambiarPitch(Mix_Chunk *orig, float factor) {
    if (!orig || factor <= 0.0f)
        return NULL;

    int freq, canales;
    Uint16 formato;
    if (!Mix_QuerySpec(&freq, &formato, &canales) || SDL_AUDIO_BITSIZE(formato) != 16)
        return NULL;

    int bytesPorFrame = 2 * canales;                 // 16 bits x canales
    Uint32 framesOrig  = orig->alen / bytesPorFrame;
    Uint32 framesNuevo = (Uint32)(framesOrig / factor);
    if (framesNuevo == 0)
        return NULL;

    Sint16 *src = (Sint16 *)orig->abuf;
    Sint16 *dst = (Sint16 *)malloc((size_t)framesNuevo * bytesPorFrame);
    if (!dst)
        return NULL;

    for (Uint32 n = 0; n < framesNuevo; n++) {
        float pos = n * factor;                      // frame de origen (con decimales)
        Uint32 i0 = (Uint32)pos;
        Uint32 i1 = (i0 + 1 < framesOrig) ? i0 + 1 : i0;
        float frac = pos - i0;
        for (int c = 0; c < canales; c++) {          // interpolacion lineal por canal
            Sint16 a = src[i0 * canales + c];
            Sint16 b = src[i1 * canales + c];
            dst[n * canales + c] = (Sint16)(a + (b - a) * frac);
        }
    }

    Mix_Chunk *nuevo = (Mix_Chunk *)malloc(sizeof(Mix_Chunk));
    if (!nuevo) {
        free(dst);
        return NULL;
    }
    nuevo->allocated = 1;                             // Mix_FreeChunk liberara abuf
    nuevo->abuf   = (Uint8 *)dst;
    nuevo->alen   = framesNuevo * bytesPorFrame;
    nuevo->volume = orig->volume;
    return nuevo;
}

// ============================ 2. FIFO / LEDs ================================

static void fifoAbrir(void) {
    char ruta[1024];
    rutaHome(ruta, sizeof ruta, "arduino_fifo");
    // El demonio mantiene el FIFO abierto (O_RDWR), asi que siempre hay lector; si
    // no lo hay (demonio caido), O_NONBLOCK evita colgarse: se juega sin luces.
    fifoFd = open(ruta, O_WRONLY | O_NONBLOCK);
    if (fifoFd < 0)
        fprintf(stderr, "sin FIFO (%s): se juega sin luces\n", strerror(errno));
}

static void fifoLinea(const char *fmt, ...) {
    if (fifoFd < 0)
        return;

    char buf[32];
    va_list ap; 
    va_start(ap, fmt);

    int n = vsnprintf(buf, sizeof buf - 1, fmt, ap);
    va_end(ap);
    if (n < 0)
        return;

    buf[n++] = '\n';

    (void)!write(fifoFd, buf, n);   // si el demonio se cayo, seguimos sin luces
}

// Enciende un canal (0..255). Solo manda al Arduino si el valor cambio.
static void led(int canal, int val) {
    if (canal < 0 || canal >= NUM_LEDS)
        return;

    if (val < 0)
        val = 0;

    else if (val > 255)
        val = 255;
    if (ledEstado[canal] == val)
        return;
    ledEstado[canal] = val;
    fifoLinea("P%d,%d", canal, val);
}

static void ledApagarTodo(void) {
    for (int i = 0; i < NUM_LEDS; i++)
        ledEstado[i] = 0;

    fifoLinea("X");
}

// Pinta la grilla: enciende 'encendida' (o -1 para ninguna) y apaga el resto.
static void pintarUnaCelda(int encendida, int brillo) {
    for (int c = 0; c < NUM_CELDAS; c++)
        led(CANAL[c], c == encendida ? brillo : 0);
}

// ====================== 3. MANDO + MAPA DE BOTONES ==========================

static SDL_Joystick  *joys[16];
static SDL_JoystickID joyId[16];
static int numJoys = 0;

// Para cada celda y para "salir": que (joystick, boton) fisico la activa.
struct Bind { int joy; int btn; };
static struct Bind bindCelda[NUM_CELDAS];
static struct Bind bindSalir;

static int joyIndex(SDL_JoystickID id) {
    for (int i = 0; i < numJoys; i++)
        if (joyId[i] == id)
            return i;

    return -1;
}

// Un boton del mando -> celda 0..11, CELDA_SALIR, o -1 si no esta mapeado.
static int celdaDeBoton(int ji, int btn) {
    if (bindSalir.joy == ji && bindSalir.btn == btn)
        return CELDA_SALIR;
    for (int c = 0; c < NUM_CELDAS; c++)
        if (bindCelda[c].joy == ji && bindCelda[c].btn == btn)
            return c;
        
    return -1;
}

// Teclado del modo demo: fila de arriba = 1..6, fila de abajo = q w e r t y.
// (ESC/0 = salir y las flechas = mover se tratan en leerEntrada.)
static int teclaCelda(SDL_Keycode k) {
    switch (k) {
        case SDLK_1: return 0;
        case SDLK_2: return 1;
        case SDLK_3: return 2;
        case SDLK_4: return 3;
        case SDLK_5: return 4;
        case SDLK_6: return 5;
        case SDLK_q: return 6;
        case SDLK_w: return 7;
        case SDLK_e: return 8;
        case SDLK_r: return 9;
        case SDLK_t: return 10;
        case SDLK_y: return 11;
    }
    return -1;
}

static int cargarMapa(void) {
    char ruta[1024];
    rutaHome(ruta, sizeof ruta, "minijuegos_mapa.conf");
    FILE *f = fopen(ruta, "r");
    if (!f)
        return 0;

    for (int c = 0; c < NUM_CELDAS; c++)
        bindCelda[c].joy = -1;

    bindSalir.joy = -1;
    char clave[32]; 
    int ji, btn, leidos = 0;

    while (fscanf(f, "%31s %d %d", clave, &ji, &btn) == 3) {
        if (strcmp(clave, "salir") == 0)
        {
            bindSalir.joy = ji;
            bindSalir.btn = btn;
            leidos++;
        }
        else {
            int c = atoi(clave);
            if (c >= 0 && c < NUM_CELDAS)
            {
                bindCelda[c].joy = ji;
                bindCelda[c].btn = btn;
                leidos++;
            }
        }
    }
    fclose(f);
    return leidos == NUM_CELDAS + 1;   // completo = 12 celdas + salir
}

static void guardarMapa(void) {
    char ruta[1024];
    rutaHome(ruta, sizeof ruta, "minijuegos_mapa.conf");
    FILE *f = fopen(ruta, "w");

    if (!f)
        return;

    for (int c = 0; c < NUM_CELDAS; c++)
        fprintf(f, "%d %d %d\n", c, bindCelda[c].joy, bindCelda[c].btn);

    fprintf(f, "salir %d %d\n", bindSalir.joy, bindSalir.btn);
    fclose(f);
}

// ============================== 4. ENTRADA ==================================
// Un unico sitio que traduce CUALQUIER evento SDL (mando o teclado) a lo que el
// juego entiende. El resto del codigo solo mira los campos de Entrada.
//
//   celda  : boton de panel pulsado (0..11), o -1
//   dx,dy  : movimiento del stick/flechas (-1/0/+1)
//   salir  : boton 0 / ESC   -> en un juego vuelve al menu; en el menu cierra
//   jugar  : ENTER / ESPACIO -> confirmar en el menu
//   cerrar : se cerro la ventana (SDL_QUIT) -> cierra el programa siempre

typedef struct {
    int celda;
    int dx;
    int dy;
    int salir;
    int jugar;
    int cerrar;
    int recalibrar;
} Entrada;

// Diagnostico (modo demo): el ultimo evento de entrada, en texto, para ver que
// manda cada control fisico. Se dibuja arriba a la izquierda con dibujarDebug().
static char ultimoEvt[96] = "";

static void registrarEvento(const SDL_Event *e) {
    switch (e->type) {
        case SDL_JOYBUTTONDOWN:
            snprintf(ultimoEvt, sizeof ultimoEvt, "JOY %d  BOTON %d",
                     joyIndex(e->jbutton.which), e->jbutton.button); break;
        case SDL_JOYAXISMOTION:
            if (e->jaxis.value > UMBRAL || e->jaxis.value < -UMBRAL)
                snprintf(ultimoEvt, sizeof ultimoEvt, "JOY %d  EJE %d = %d",
            joyIndex(e->jaxis.which), e->jaxis.axis, e->jaxis.value);
            break;
        case SDL_JOYHATMOTION:
            if (e->jhat.value)
                snprintf(ultimoEvt, sizeof ultimoEvt, "JOY %d  HAT = %d",
            joyIndex(e->jhat.which), e->jhat.value);
            break;
        case SDL_KEYDOWN:
            snprintf(ultimoEvt, sizeof ultimoEvt, "TECLA %s", SDL_GetKeyName(e->key.keysym.sym));
            break;
    }
}

// Estado de los ejes (compartido por todos los sticks) para dar un paso por empujon.
static int ejeXact = 0, ejeYact = 0;
static void reiniciarEjes(void) { ejeXact = ejeYact = 0; }

// Rectangulo en pantalla de la celda c del panel de demo. La usan el dibujo y el
// hit-test del raton, asi que el clic cuadra siempre con lo que se ve.
static SDL_Rect celdaRect(int c) {
    int s = anchoV / 14, gap = s / 4;
    int x0 = (anchoV - (6 * s + 5 * gap)) / 2;
    int y0 = altoV - 2 * s - gap - 72;
    SDL_Rect r = { x0 + (c % 6) * (s + gap), y0 + (c / 6) * (s + gap), s, s };
    return r;
}

// Que celda del panel (0..11) cae en el pixel (mx,my), o -1 si ninguna.
static int celdaEnPixel(int mx, int my) {
    for (int c = 0; c < NUM_CELDAS; c++) {
        SDL_Rect r = celdaRect(c);
        if (mx >= r.x && mx < r.x + r.w && my >= r.y && my < r.y + r.h)
            return c;
    }
    return -1;
}

// Convierte el movimiento analogico de un stick (ejes 0 y 1) o su cruceta en dx/dy.
static void leerDireccion(const SDL_Event *e, int *dx, int *dy) {
    if (e->type == SDL_JOYAXISMOTION) {
        int v = e->jaxis.value;
        if (e->jaxis.axis == 0) {
            if(!ejeXact && v >  UMBRAL)
            {
                *dx =  1;
                ejeXact = 1;
            }
            else if (!ejeXact && v < -UMBRAL)
            {
                *dx = -1;
                ejeXact = 1;
            }
            else if ( ejeXact && v > -ZONA_MUERTA && v < ZONA_MUERTA)
                ejeXact = 0;

        } 
        else if (e->jaxis.axis == 1) {
            if (!ejeYact && v >  UMBRAL)
            {
                *dy =  1;
                ejeYact = 1;
            }
            else if (!ejeYact && v < -UMBRAL)
            {
                *dy = -1;
                ejeYact = 1;
            }
            else if ( ejeYact && v > -ZONA_MUERTA && v < ZONA_MUERTA) 
                ejeYact = 0;
        }
    } else if (e->type == SDL_JOYHATMOTION) {

        Uint8 h = e->jhat.value;
        if (h & SDL_HAT_LEFT)
            *dx = -1;

        if (h & SDL_HAT_RIGHT)
            *dx =  1;

        if (h & SDL_HAT_UP)
            *dy = -1;

        if (h & SDL_HAT_DOWN)
            *dy =  1;
    }
}

static Entrada leerEntrada(const SDL_Event *e) {
    Entrada in = { -1, 0, 0, 0, 0, 0, 0 };
    registrarEvento(e);

    if (e->type == SDL_QUIT)
    {
        in.cerrar = 1;
        return in;
    }

    if (e->type == SDL_JOYBUTTONDOWN) {
        int c = celdaDeBoton(joyIndex(e->jbutton.which), e->jbutton.button);
        
        if (c == CELDA_SALIR)
            in.salir = 1;
        else if (c >= 0)
            in.celda = c;
        
        return in;
    }

    if (e->type == SDL_KEYDOWN && e->key.repeat == 0) {   // teclado (modo demo)
        switch (e->key.keysym.sym) {
            case SDLK_ESCAPE: case SDLK_0:     in.salir = 1; break;
            case SDLK_RETURN: case SDLK_SPACE: in.jugar = 1; break;
            case SDLK_c: in.recalibrar = 1; break;   // recalibrar los botones del mando
            case SDLK_LEFT:  in.dx = -1; break;
            case SDLK_RIGHT: in.dx =  1; break;
            case SDLK_UP:    in.dy = -1; break;
            case SDLK_DOWN:  in.dy =  1; break;
            default: {
                int c = teclaCelda(e->key.keysym.sym);
                if (c >= 0)
                    in.celda = c;
            }
        }
        return in;
    }

    // Clic del raton sobre el panel de demo = pulsar esa celda (acierto en el topo).
    if (demo && e->type == SDL_MOUSEBUTTONDOWN && e->button.button == SDL_BUTTON_LEFT) {
        int c = celdaEnPixel(e->button.x, e->button.y);
        if (c >= 0)
            in.celda = c;
        return in;
    }

    leerDireccion(e, &in.dx, &in.dy);   // ejes / cruceta del mando
    return in;
}

// ============================= 5. PUNTAJES ==================================

static void cargarPuntajes(void) {
    char ruta[1024];
    rutaHome(ruta, sizeof ruta, "minijuegos.json");
    FILE *f = fopen(ruta, "r");
    if (!f)
        return;

    char buf[256] = {0};
    size_t n = fread(buf, 1, sizeof buf - 1, f);
    buf[n] = 0;
    fclose(f);

    char *p;
    if ((p = strstr(buf, "\"meta\"")))
        sscanf(p + 6, " : %d", &recordMeta);

    if ((p = strstr(buf, "\"topo\"")))
        sscanf(p + 6, " : %d", &recordTopo);
}

static void guardarPuntajes(void) {
    char ruta[1024];
    rutaHome(ruta, sizeof ruta, "minijuegos.json");
    FILE *f = fopen(ruta, "w");

    if (!f)
        return;

    fprintf(f, "{\"meta\": %d, \"topo\": %d}\n", recordMeta, recordTopo);
    fclose(f);
}

// Si el puntaje supera el record, lo actualiza y lo guarda.
static void guardarRecord(int *record, int puntos) {
    if (puntos > *record)
    {
        *record = puntos;
        guardarPuntajes();
    }
}

// ============================== 6. DIBUJO ===================================

static void texto(const char *s, int cx, int y, TTF_Font *f, SDL_Color c, int centrado) {
    SDL_Surface *su = TTF_RenderUTF8_Blended(f, s, c);
    if (!su)
        return;

    SDL_Texture *tx = SDL_CreateTextureFromSurface(ren, su);
    SDL_Rect r = {
         centrado ? cx - su->w / 2 : cx,
          y,
          su->w,
          su->h
        };
    SDL_RenderCopy(ren, tx, NULL, &r);
    SDL_DestroyTexture(tx);
    SDL_FreeSurface(su);
}

static void limpiarPantalla(void) {
    SDL_SetRenderDrawColor(ren, 10, 10, 16, 255);
    SDL_RenderClear(ren);
}

// Solo en modo demo: dibuja el panel de botones en la pantalla (boton extra arriba
// a la izquierda + grilla 2x6) con el brillo de cada LED, para verlo sin la cabina.
static void dibujarPanelDemo(void) {
    int s = anchoV / 14, gap = s / 4;
    int x0 = (anchoV - (6 * s + 5 * gap)) / 2;
    int y0 = altoV - 2 * s - gap - 72;
    int ve = ledEstado[0];
    SDL_Rect ex = { x0, y0 - s - gap, s, s };     // boton extra (canal 0)
    SDL_SetRenderDrawColor(ren, ve, ve * 4 / 5, 12, 255);
    SDL_RenderFillRect(ren, &ex);
    for (int c = 0; c < NUM_CELDAS; c++) {
        SDL_Rect r = celdaRect(c);                 // misma geometria que el hit-test del raton
        int v = ledEstado[CANAL[c]];
        SDL_SetRenderDrawColor(ren, v, v * 4 / 5, 12, 255);
        SDL_RenderFillRect(ren, &r);
        SDL_SetRenderDrawColor(ren, 60, 60, 70, 255);
        SDL_RenderDrawRect(ren, &r);
    }
}

// Diagnostico (modo demo): el ultimo evento de entrada, arriba a la izquierda.
static void dibujarDebug(void) {
    if (!demo || ultimoEvt[0] == '\0')
        return;
    texto(ultimoEvt, 10, 8, fuente, AMBAR, 0);
}

// Pantalla comun de los dos juegos: titulo, puntos, record y segundos restantes.
static void hud(const char *titulo, int puntos, int record, Uint32 restante_ms) {
    char s[64];
    limpiarPantalla();
    texto(titulo, anchoV / 2, 40, fuenteBig, BLANCO, 1);

    snprintf(s, sizeof s, "Puntos: %d", puntos);
    texto(s, anchoV / 2, altoV / 2 - 30, fuenteBig, BLANCO, 1);

    snprintf(s, sizeof s, "Record: %d", record);
    texto(s, anchoV / 2, altoV / 2 + 40, fuente, BLANCO, 1);

    snprintf(s, sizeof s, "%u s", restante_ms / 1000);
    texto(s, anchoV / 2, altoV - 70, fuente, BLANCO, 1);

    if (demo) {
        dibujarPanelDemo();
        dibujarDebug();
    }
}

// ============================ 7. CALIBRACION ================================
// Se pide cada celda y el boton de salir; se guarda que boton fisico es cada uno.
// Hace falta porque los indices de boton del mando no se saben sin la cabina.

static const char *NOMBRE_CELDA[NUM_CELDAS] = {
    "ARRIBA  col 1", "ARRIBA  col 2", "ARRIBA  col 3", "ARRIBA  col 4", "ARRIBA  col 5", "ARRIBA  col 6",
    "ABAJO   col 1", "ABAJO   col 2", "ABAJO   col 3", "ABAJO   col 4", "ABAJO   col 5", "ABAJO   col 6"
};

// Ese (joystick, boton) ya se asigno a una celda anterior? (evita mapear el mismo
// boton a dos cosas, que dejaria botones "muertos" o actuando de salir.)
static int botonYaUsado(int ji, int btn, int hasta) {
    for (int c = 0; c < hasta && c < NUM_CELDAS; c++)
        if (bindCelda[c].joy == ji && bindCelda[c].btn == btn)
            return 1;
    return 0;
}

static int calibrar(void) {   // 1 = calibro completo, 0 = cancelado (ESC)
    int objetivo = 0;         // 0..11 celdas, 12 = boton de salir
    int repetido = 0;
    for (int c = 0; c < NUM_CELDAS; c++)
    {
        bindCelda[c].joy = -1;
        bindCelda[c].btn = -1;
    }

    bindSalir.joy = -1;
    bindSalir.btn = -1;

    while (objetivo <= NUM_CELDAS) {
        // Pista en el panel: enciende solo el LED que toca pulsar (salir = extra).
        pintarUnaCelda(-1, 0);
        led(objetivo < NUM_CELDAS ? CANAL[objetivo] : 0, 255);

        SDL_Event e;
        int hecho = 0;
        while (!hecho) {
            if (!SDL_WaitEvent(&e))
                continue;
            if (e.type == SDL_QUIT)
                return 0;
            if (e.type == SDL_KEYDOWN && e.key.keysym.sym == SDLK_ESCAPE)
                return 0;
            if (e.type == SDL_JOYBUTTONDOWN) {
                int ji = joyIndex(e.jbutton.which), btn = e.jbutton.button;
                if (ji < 0)
                    continue;
                int hasta = (objetivo < NUM_CELDAS) ? objetivo : NUM_CELDAS;
                if (botonYaUsado(ji, btn, hasta)) {
                    repetido = 1;                 // ese boton ya esta cogido: pide otro
                } else {
                    struct Bind *b = (objetivo < NUM_CELDAS) ? &bindCelda[objetivo] : &bindSalir;
                    b->joy = ji;
                    b->btn = btn;
                    objetivo++;
                    hecho = 1;
                    repetido = 0;
                }
            }
            limpiarPantalla();
            texto("CALIBRACION", anchoV / 2, altoV / 4, fuenteBig, AMBAR, 1);
            char msg[64];
            if (objetivo < NUM_CELDAS)
                snprintf(msg, sizeof msg, "Pulsa el boton:  %s", NOMBRE_CELDA[objetivo]);
            else
                snprintf(msg, sizeof msg, "Pulsa el boton de SALIR (boton 0)");

            texto(msg, anchoV / 2, altoV / 2, fuente, BLANCO, 1);

            if (repetido)
                texto("ese boton ya esta usado, prueba otro", anchoV / 2, altoV / 2 + 50, fuente, AMBAR, 1);

            texto("ESC para cancelar", anchoV / 2, altoV * 3 / 4, fuente, BLANCO, 1);

            if (ultimoEvt[0])   // que manda el ultimo control pulsado (diagnostico)
                texto(ultimoEvt, 10, 8, fuente, AMBAR, 0);
            
            SDL_RenderPresent(ren);
        }
    }
    guardarMapa();
    ledApagarTodo();
    return 1;
}

// ============================ 8. LOS JUEGOS ================================

// Mueve el cursor por la grilla 2x6 (2 filas, 6 columnas).
static int mover(int celda, int dx, int dy) {
    int fila = celda / 6, col = celda % 6;
    if (dy < 0)
        fila = 0;
    else if (dy > 0)
        fila = 1;
    col += dx;
    if (col < 0)
        col = 0;
    else if (col > 5)
        col = 5;

    return fila * 6 + col;
}

static int celdaAlAzarMenos(int evita) {
    int c;
    do
    {
        c = rand() % NUM_CELDAS;
    } while (c == evita);

    return c;
}

// Juego 1: mueve el cursor hasta la celda que parpadea (la meta). +1 por acierto.
static int jugarMeta(void) {
    int cursor = 0, meta = 5, puntos = 0;
    Uint32 ini = SDL_GetTicks();
    reiniciarEjes();
    ledApagarTodo();

    while(1) {
        Uint32 ahora = SDL_GetTicks();
        if (ahora - ini >= RONDA_MS)
            break;

        SDL_Event e;
        while (SDL_PollEvent(&e)) {
            Entrada in = leerEntrada(&e);

            if (in.cerrar)
                return A_SALIR;

            if (in.salir)
                return A_MENU;

            if (in.dx || in.dy) {
                cursor = mover(cursor, in.dx, in.dy);
                if (cursor == meta) {
                    puntos++;
                    float tono = 1.0f + ((float)rand() / (float)RAND_MAX) * 0.3f;   // 1.0 .. 1.8
                    Mix_Chunk *highPitchOk = cambiarPitch(sfxOk, tono);
                    Mix_PlayChannel(-1, highPitchOk, 0);
                    meta = celdaAlAzarMenos(cursor);
                }
            }
        }

        // cursor fijo encendido, meta parpadeando, el resto apagado
        int blink = (SDL_GetTicks() / 300) % 2;
        for (int c = 0; c < NUM_CELDAS; c++)
            led(CANAL[c], c == cursor ? 255 : (c == meta ? (blink ? 255 : 40) : 0));

        hud("ALCANZA LA META", puntos, recordMeta, RONDA_MS - (ahora - ini));
        SDL_RenderPresent(ren);
        SDL_Delay(8);
    }
    guardarRecord(&recordMeta, puntos);
    pantallaFin(puntos, recordMeta);
    return A_MENU;
}

// Juego 2: sale un topo (una celda encendida), pegale al boton antes de que
// desaparezca. +1 por acierto; va acelerando con el puntaje.
static int jugarTopo(void) {
    int puntos = 0, topo = -1;
    Uint32 ini = SDL_GetTicks(), topoHasta = 0, proximo = SDL_GetTicks() + 400;
    static Mix_Chunk *topoAgudo = NULL;   // copia del sonido del topo con el tono subido
                                          // (static: se reaprovecha y se libera en el siguiente topo)
    ledApagarTodo();

    Mix_PlayMusic(musTopo, -1);
    while (1) {
        Uint32 ahora = SDL_GetTicks();
        if (ahora - ini >= 2000)//RONDA_MS)
            break;

        if (topo < 0 && ahora >= proximo) {            // sale un topo nuevo
            topo = rand() % NUM_CELDAS;
            int visible = 1200 - puntos * 25;          // cada vez dura menos
            
            if (visible < 400)
                visible = 400;

            topoHasta = ahora + visible;
            // El topo suena a un tono aleatorio entre 1.0 y 1.8 (demo de cambiarPitch).
            if (topoAgudo)
                Mix_FreeChunk(topoAgudo);              // libera el de la vez anterior
            float tono = 1.0f + ((float)rand() / (float)RAND_MAX) * 0.8f;   // 1.0 .. 1.8
            topoAgudo = cambiarPitch(sfxTopo, tono);
            Mix_PlayChannel(-1, topoAgudo ? topoAgudo : sfxTopo, 0);

        } else if (topo >= 0 && ahora >= topoHasta) {  // se escapo
            topo = -1;
            proximo = ahora + 300;
        }

        SDL_Event e;
        while (SDL_PollEvent(&e)) {
            Entrada in = leerEntrada(&e);

            if (in.cerrar)
                return A_SALIR;

            if (in.salir)
                return A_MENU;

            if (in.celda >= 0) {
                if (in.celda == topo) {                // acierto
                    puntos++;
                    Mix_PlayChannel(-1, sfxWhack, 0);
                    topo = -1;
                    proximo = ahora + 250;
                } else {                               // fallo
                    Mix_PlayChannel(-1, sfxFail, 0);
                }
            }
        }

        pintarUnaCelda(topo, 255);
        hud("DALE AL TOPO", puntos, recordTopo, RONDA_MS - (ahora - ini));
        SDL_RenderPresent(ren);
        SDL_Delay(8);
    }
    guardarRecord(&recordTopo, puntos);
    Mix_HaltMusic();                 // corta la musica de fondo del topo
    Mix_PlayMusic(musTopoFin, 1);    // jingle de victoria: suena DURANTE la pantalla de fin
    pantallaFin(puntos, recordTopo); // (pantallaFin BLOQUEA ~4 s; por eso la musica va antes)
    return A_MENU;
}

// Tras una ronda: puntaje y record unos segundos, o hasta que se pulse algo.
static void pantallaFin(int puntos, int record) {
    //if (musFin)
      //  Mix_PlayMusic(musFin, 1);   // una vez
    ledApagarTodo();
    Uint32 fin = SDL_GetTicks() + 4000;
    while (SDL_GetTicks() < fin) {
        SDL_Event e;
        while (SDL_PollEvent(&e)) {
            Entrada in = leerEntrada(&e);
            if (in.cerrar || in.salir || in.jugar || in.celda >= 0) fin = 0;  // cualquier cosa corta
        }
        char s[64];
        limpiarPantalla();
        texto("FIN", anchoV / 2, altoV / 3, fuenteBig, AMBAR, 1);

        snprintf(s, sizeof s, "Puntos: %d", puntos);
        texto(s, anchoV / 2, altoV / 2, fuenteBig, BLANCO, 1);

        snprintf(s, sizeof s, "Record: %d", record);
        texto(s, anchoV / 2, altoV / 2 + 70, fuente, BLANCO, 1);

        SDL_RenderPresent(ren);
        SDL_Delay(16);
        if (fin == 0)
            break;
    }
}

// =============================== 9. MENU ===================================
// Arriba/abajo elige juego (lista vertical); cualquier boton o ENTER juega;
// el boton 0 / ESC cierra el programa.

static int menu(void) {
    const char *nombres[2] = { "ALCANZA LA META", "DALE AL TOPO" };
    int sel = 0;
    reiniciarEjes();
    if (musMenu)
        Mix_PlayMusic(musMenu, -1);   // UNA vez (antes -1 repetia el jingle sin parar)
    ledApagarTodo();
    Uint32 t0 = SDL_GetTicks();

    while(1) {
        SDL_Event e;
        while (SDL_PollEvent(&e)) {
            Entrada in = leerEntrada(&e);
            if (in.cerrar || in.salir)
                return A_SALIR;
            if (in.recalibrar && numJoys > 0)
            {
                calibrar();
                break;
            }   // tecla C: reasignar botones
            if (in.jugar || in.celda >= 0)
            {
                Mix_HaltMusic();
                return sel == 0 ? JUEGO_META : JUEGO_TOPO;
            }

            if (in.dy)
                sel ^= 1;   // arriba/abajo alterna entre los dos juegos
        }

        // un LED paseando por el panel, de adorno
        int paso = (SDL_GetTicks() - t0) / 150 % NUM_CELDAS;
        pintarUnaCelda(paso, 180);

        limpiarPantalla();
        texto("MINIJUEGOS DE LUCES", anchoV / 2, altoV / 5, fuenteBig, AMBAR, 1);

        for (int i = 0; i < 2; i++)
            texto(nombres[i], anchoV / 2, altoV / 2 - 60 + i * 64, fuenteBig, i == sel ? BLANCO : GRIS, 1);

        if (demo) {
            texto("teclado: flechas elegir   ENTER jugar   ESC salir", anchoV / 2, altoV - 30, fuente, GRIS, 1);
            dibujarPanelDemo();
            dibujarDebug();
        }
        SDL_RenderPresent(ren);
        SDL_Delay(16);
    }
}

// =============================== 10. MAIN ==================================

static void cargarSonido(Mix_Chunk **sfx, const char *nombre) {
    char ruta[1200];
    snprintf(ruta, sizeof ruta, "%ssonidos/%s", rutaBase, nombre);
    *sfx = Mix_LoadWAV(ruta);
}

static void initJoysticks()
{
    numJoys = SDL_NumJoysticks();

    if (numJoys > 16)
        numJoys = 16;

    for (int i = 0; i < numJoys; i++) {
        joys[i] = SDL_JoystickOpen(i);
        joyId[i] = joys[i] ? SDL_JoystickInstanceID(joys[i]) : -1;
    }

    registro("=== arranque: demo=%d joysticks=%d ===", demo, numJoys);
    for (int i = 0; i < numJoys; i++)
        registro("  joy %d: '%s'  botones=%d ejes=%d hats=%d", i,
                 SDL_JoystickName(joys[i]) ? SDL_JoystickName(joys[i]) : "?",
                 SDL_JoystickNumButtons(joys[i]), SDL_JoystickNumAxes(joys[i]),
                 SDL_JoystickNumHats(joys[i]));

    // Mapa de botones "sin asignar" de entrada: asi, sin calibrar, NINGUN boton
    // del mando hace nada (antes el 0-por-defecto hacia que el boton 0 = salir).
    for (int c = 0; c < NUM_CELDAS; c++)
    {
        bindCelda[c].joy = -1;
        bindCelda[c].btn = -1;
    }

    bindSalir.joy = -1;
    bindSalir.btn = -1;
}

static int initFont()
{
    if (TTF_Init() < 0)
    {
        fprintf(stderr, "TTF_Init: %s\n", TTF_GetError());
        return 1;
    }
    
    char rf[1100];
    snprintf(rf, sizeof rf, "%sfuente.ttf", rutaBase);
    fuente    = TTF_OpenFont(rf, 28);
    fuenteBig = TTF_OpenFont(rf, 52);
    if (!fuente || !fuenteBig) 
    { 
        fprintf(stderr, "fuente %s: %s\n", rf, TTF_GetError()); 
        return 1; 
    }
    
    return 0;
}

static void initMix()
{
    Mix_Init(MIX_INIT_MP3 | MIX_INIT_OGG);
    if (Mix_OpenAudio(44100, MIX_DEFAULT_FORMAT, 2, 1024) < 0)
        fprintf(stderr, "audio: %s (se juega sin sonido)\n", Mix_GetError());

    cargarSonido(&sfxOk,   "dragon-coin.wav");
    cargarSonido(&sfxWhack,   "clap-pop.wav");
    cargarSonido(&sfxFail, "incorrect.wav");
    cargarSonido(&sfxTopo, "screen-scroll.wav");
    
    char rm[1200];
    snprintf(rm, sizeof rm, "%ssonidos/mainMus.mp3", rutaBase);
    musMenu = Mix_LoadMUS(rm);
    snprintf(rm, sizeof rm, "%ssonidos/fin.mp3", rutaBase);
    musFin = Mix_LoadMUS(rm);
    snprintf(rm, sizeof rm, "%ssonidos/mole.mp3", rutaBase);
    musTopo = Mix_LoadMUS(rm);
    snprintf(rm, sizeof rm, "%ssonidos/moleEnd.mp3", rutaBase);
    musTopoFin = Mix_LoadMUS(rm);
}

static int initComponents()
{
    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_JOYSTICK | SDL_INIT_AUDIO) < 0) {
        fprintf(stderr, "SDL_Init: %s\n", SDL_GetError());
        return 1;
    }
    
    win = SDL_CreateWindow("Minijuegos", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
                           1024, 768, demo ? 0 : SDL_WINDOW_FULLSCREEN_DESKTOP);
    
    ren = SDL_CreateRenderer(win, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
    
    if (!ren)
        ren = SDL_CreateRenderer(win, -1, SDL_RENDERER_SOFTWARE);   // sin GPU (p.ej. pruebas)
    if (!win || !ren)
    {
        fprintf(stderr, "ventana: %s\n", SDL_GetError());
        return 1;
    }

    char *basePath = SDL_GetBasePath();
    snprintf(rutaBase, sizeof rutaBase, "%s", basePath ? basePath : "./");
    if (basePath)
        SDL_free(basePath);

    if (!demo)
        SDL_ShowCursor(SDL_DISABLE);

    SDL_GetRendererOutputSize(ren, &anchoV, &altoV);

    if(initFont())
        return 1;

    initMix();

    initJoysticks();

    return 0;
}



int main(void) {
    srand(time(NULL) ^ getpid());
    demo = (getenv("MINIJUEGOS_DEMO") != NULL);

    if(initComponents())
        return 1;

    cargarPuntajes();
    fifoAbrir();
    fifoLinea("[");             // reclamar el panel al demonio

    // Si hay un mando sin mapear, se calibra (tambien en demo, para poder jugar con
    // el). ESC durante la calibracion lo salta y se juega solo con el teclado.
    if (!cargarMapa() && numJoys > 0)
        calibrar();

    while(1) {
        int eleccion = menu();
        if (eleccion == A_SALIR) 
            break;
        int gameSelect = (eleccion == JUEGO_META) ? jugarMeta() : jugarTopo();   // cada juego muestra su fin de ronda
        if (gameSelect == A_SALIR)
            break;
    }

    fifoLinea("]");             // soltar el panel -> el demonio vuelve a atraccion
    ledApagarTodo();
    if (fifoFd >= 0) 
        close(fifoFd);
    SDL_Quit();
    return 0;
}
