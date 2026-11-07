// Frontend de los minijuegos de luces del panel (huevo de pascua).
//
// Lo lanza el plugin del frontend al pulsar P2 Start. Abre una ventana negra a
// pantalla completa (le roba el foco a Attract-Mode), lleva la logica de los dos
// juegos, el menu, los puntajes y el sonido, lee el mando por SDL, y pinta los
// LEDs del panel mandando lineas al demonio por el FIFO ~/.attract/arduino_fifo.
//
// La logica NO vive en el Arduino: aqui se decide todo y el Arduino solo
// enciende los LEDs que le pintamos con P<ch>,<v> / X. Protocolo y diseno:
// docs/minijuegos.md.
//
// Salir: el boton 0 del panel (el de salida de la mayoria de juegos). En un
// juego vuelve al menu; en el menu cierra el programa (vuelve a AM+).
//
// El mapa boton-fisico -> celda NO se puede saber sin la cabina, asi que hay un
// modo de calibracion que lo guarda en ~/.attract/minijuegos_mapa.conf.

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

#define NUM_CELDAS 12
#define NUM_LEDS   13

// Celda (0..11, por filas: 0..5 arriba, 6..11 abajo) -> canal de LED del PCA.
// Sale de la grilla de Arcade.ino: arriba {1,8,6,3,10,12}, abajo {2,7,5,4,9,11}.
static const int CANAL[NUM_CELDAS] = { 1, 8, 6, 3, 10, 12,  2, 7, 5, 4, 9, 11 };

#define UMBRAL 16000   // eje del stick: cruzar esto = un movimiento
#define ZONA_MUERTA 8000
#define RONDA_MS 60000

enum { A_MENU, A_SALIR };

static SDL_Window   *win;
static SDL_Renderer *ren;
static TTF_Font     *fuente, *fuenteBig;
static Mix_Chunk    *sfxOk, *sfxFail, *sfxTopo;
static Mix_Music    *musMenu, *musFin;
static int anchoV, altoV;
static int demo = 0;   // MINIJUEGOS_DEMO=1: ventana + panel de LEDs en pantalla + teclado

static int fifoFd = -1;
static int ledEstado[NUM_LEDS];   // ultimo brillo enviado por canal (para deltas)

static SDL_Joystick *joys[16];
static SDL_JoystickID joyId[16];
static int numJoys = 0;

// Mapa de botones: para cada celda y para "salir", que (joystick, boton) lo activa.
struct Bind { int joy; int btn; };
static struct Bind bindCelda[NUM_CELDAS];
static struct Bind bindSalir;

static int recordMeta = 0, recordTopo = 0;

static void pantallaFin(int puntos, int record);   // definida mas abajo

// ---- rutas -------------------------------------------------------------------
static char rutaBase[1024];   // directorio del ejecutable (assets)

static void rutaHome(char *buf, size_t n, const char *nombre) {
    const char *home = getenv("HOME");
    snprintf(buf, n, "%s/.attract/%s", home ? home : ".", nombre);
}

// ---- FIFO / LEDs -------------------------------------------------------------
static void fifoAbrir(void) {
    char ruta[1024];
    rutaHome(ruta, sizeof ruta, "arduino_fifo");
    // El demonio mantiene el FIFO abierto (O_RDWR), asi que hay lector; si no lo
    // hay (demonio caido), O_NONBLOCK evita quedarnos colgados: se juega sin LEDs.
    fifoFd = open(ruta, O_WRONLY | O_NONBLOCK);
    if (fifoFd < 0)
        fprintf(stderr, "sin FIFO (%s): se juega sin luces\n", strerror(errno));
}

static void fifoLinea(const char *fmt, ...) {
    if (fifoFd < 0) return;
    char buf[32];
    va_list ap; va_start(ap, fmt);
    int n = vsnprintf(buf, sizeof buf - 1, fmt, ap);
    va_end(ap);
    if (n < 0) return;
    buf[n++] = '\n';
    if (write(fifoFd, buf, n) < 0 && errno != EAGAIN)
        { /* el demonio se cayo: seguimos sin luces */ }
}

static void led(int canal, int val) {           // delta: solo si cambia
    if (canal < 0 || canal >= NUM_LEDS) return;
    if (val < 0) val = 0; else if (val > 255) val = 255;
    if (ledEstado[canal] == val) return;
    ledEstado[canal] = val;
    fifoLinea("P%d,%d", canal, val);
}

static void ledApagarTodo(void) {
    for (int i = 0; i < NUM_LEDS; i++) ledEstado[i] = 0;
    fifoLinea("X");
}

// ---- joysticks / mapa --------------------------------------------------------
static int joyIndex(SDL_JoystickID id) {
    for (int i = 0; i < numJoys; i++) if (joyId[i] == id) return i;
    return -1;
}

// Devuelve celda 0..11, A_SALIR codificado como -2, o -1 si ese boton no esta mapeado.
static int celdaDeBoton(int ji, int btn) {
    if (bindSalir.joy == ji && bindSalir.btn == btn) return -2;
    for (int c = 0; c < NUM_CELDAS; c++)
        if (bindCelda[c].joy == ji && bindCelda[c].btn == btn) return c;
    return -1;
}

// Teclado del modo demo: numeros 1..6 = fila de arriba, qwerty = fila de abajo,
// ESC/0 = salir (como el boton 0). Devuelve celda 0..11, -2 salir, -1 nada.
static int teclaCelda(SDL_Keycode k) {
    switch (k) {
        case SDLK_1: return 0;  case SDLK_2: return 1;  case SDLK_3: return 2;
        case SDLK_4: return 3;  case SDLK_5: return 4;  case SDLK_6: return 5;
        case SDLK_q: return 6;  case SDLK_w: return 7;  case SDLK_e: return 8;
        case SDLK_r: return 9;  case SDLK_t: return 10; case SDLK_y: return 11;
        case SDLK_ESCAPE: case SDLK_0: return -2;
    }
    return -1;
}

static int cargarMapa(void) {
    char ruta[1024]; rutaHome(ruta, sizeof ruta, "minijuegos_mapa.conf");
    FILE *f = fopen(ruta, "r");
    if (!f) return 0;
    for (int c = 0; c < NUM_CELDAS; c++) bindCelda[c].joy = -1;
    bindSalir.joy = -1;
    char clave[32]; int ji, btn; int leidos = 0;
    while (fscanf(f, "%31s %d %d", clave, &ji, &btn) == 3) {
        if (strcmp(clave, "salir") == 0) { bindSalir.joy = ji; bindSalir.btn = btn; leidos++; }
        else { int c = atoi(clave); if (c >= 0 && c < NUM_CELDAS) { bindCelda[c].joy = ji; bindCelda[c].btn = btn; leidos++; } }
    }
    fclose(f);
    return leidos == NUM_CELDAS + 1;   // completo = 12 celdas + salir
}

static void guardarMapa(void) {
    char ruta[1024]; rutaHome(ruta, sizeof ruta, "minijuegos_mapa.conf");
    FILE *f = fopen(ruta, "w");
    if (!f) return;
    for (int c = 0; c < NUM_CELDAS; c++)
        fprintf(f, "%d %d %d\n", c, bindCelda[c].joy, bindCelda[c].btn);
    fprintf(f, "salir %d %d\n", bindSalir.joy, bindSalir.btn);
    fclose(f);
}

// ---- puntajes ----------------------------------------------------------------
static void cargarPuntajes(void) {
    char ruta[1024]; rutaHome(ruta, sizeof ruta, "minijuegos.json");
    FILE *f = fopen(ruta, "r");
    if (!f) return;
    char buf[256] = {0};
    size_t n = fread(buf, 1, sizeof buf - 1, f);
    buf[n] = 0;
    fclose(f);
    char *p;
    if ((p = strstr(buf, "\"meta\""))) sscanf(p + 6, " : %d", &recordMeta);
    if ((p = strstr(buf, "\"topo\""))) sscanf(p + 6, " : %d", &recordTopo);
}

static void guardarPuntajes(void) {
    char ruta[1024]; rutaHome(ruta, sizeof ruta, "minijuegos.json");
    FILE *f = fopen(ruta, "w");
    if (!f) return;
    fprintf(f, "{\"meta\": %d, \"topo\": %d}\n", recordMeta, recordTopo);
    fclose(f);
}

// ---- dibujo ------------------------------------------------------------------
static void texto(const char *s, int cx, int y, TTF_Font *f, SDL_Color c, int centrado) {
    SDL_Surface *su = TTF_RenderUTF8_Blended(f, s, c);
    if (!su) return;
    SDL_Texture *tx = SDL_CreateTextureFromSurface(ren, su);
    SDL_Rect r = { centrado ? cx - su->w / 2 : cx, y, su->w, su->h };
    SDL_RenderCopy(ren, tx, NULL, &r);
    SDL_DestroyTexture(tx);
    SDL_FreeSurface(su);
}

static void limpiarPantalla(void) {
    SDL_SetRenderDrawColor(ren, 10, 10, 16, 255);
    SDL_RenderClear(ren);
}

// Modo demo: dibuja el panel de botones en la pantalla (el boton extra arriba a
// la izquierda y la grilla 2x6) con el brillo que mandariamos a cada LED, para
// ver las luces sin la cabina.
static void dibujarPanelDemo(void) {
    int s = anchoV / 14, gap = s / 4;
    int x0 = (anchoV - (6 * s + 5 * gap)) / 2;
    int y0 = altoV - 2 * s - gap - 72;   // deja sitio para los rotulos de abajo
    SDL_Rect ex = { x0, y0 - s - gap, s, s };            // boton extra (canal 0)
    int ve = ledEstado[0];
    SDL_SetRenderDrawColor(ren, ve, ve * 4 / 5, 12, 255);
    SDL_RenderFillRect(ren, &ex);
    for (int cell = 0; cell < NUM_CELDAS; cell++) {
        SDL_Rect r = { x0 + (cell % 6) * (s + gap), y0 + (cell / 6) * (s + gap), s, s };
        int v = ledEstado[CANAL[cell]];
        SDL_SetRenderDrawColor(ren, v, v * 4 / 5, 12, 255);
        SDL_RenderFillRect(ren, &r);
        SDL_SetRenderDrawColor(ren, 60, 60, 70, 255);
        SDL_RenderDrawRect(ren, &r);
    }
}

// ---- entrada -----------------------------------------------------------------
// Estado de los ejes para emitir un solo movimiento por empujon (todos los sticks juntos).
static int ejeXact = 0, ejeYact = 0;

// Procesa un evento de movimiento y devuelve -1/0/+1 en *dx,*dy (0 si no hubo).
static void leerDireccion(const SDL_Event *e, int *dx, int *dy) {
    *dx = *dy = 0;
    if (e->type == SDL_JOYAXISMOTION) {
        int v = e->jaxis.value;
        if (e->jaxis.axis == 0) {
            if (!ejeXact && v > UMBRAL)  { *dx = 1;  ejeXact = 1; }
            else if (!ejeXact && v < -UMBRAL) { *dx = -1; ejeXact = 1; }
            else if (ejeXact && v > -ZONA_MUERTA && v < ZONA_MUERTA) ejeXact = 0;
        } else if (e->jaxis.axis == 1) {
            if (!ejeYact && v > UMBRAL)  { *dy = 1;  ejeYact = 1; }
            else if (!ejeYact && v < -UMBRAL) { *dy = -1; ejeYact = 1; }
            else if (ejeYact && v > -ZONA_MUERTA && v < ZONA_MUERTA) ejeYact = 0;
        }
    } else if (e->type == SDL_JOYHATMOTION) {
        Uint8 h = e->jhat.value;
        if (h & SDL_HAT_LEFT)  *dx = -1;
        if (h & SDL_HAT_RIGHT) *dx = 1;
        if (h & SDL_HAT_UP)    *dy = -1;
        if (h & SDL_HAT_DOWN)  *dy = 1;
    } else if (e->type == SDL_KEYDOWN && e->key.repeat == 0) {   // teclado (demo)
        switch (e->key.keysym.sym) {
            case SDLK_LEFT:  *dx = -1; break;
            case SDLK_RIGHT: *dx = 1;  break;
            case SDLK_UP:    *dy = -1; break;
            case SDLK_DOWN:  *dy = 1;  break;
        }
    }
}

// ---- calibracion -------------------------------------------------------------
static const char *NOMBRE_CELDA[NUM_CELDAS] = {
    "ARRIBA  col 1", "ARRIBA  col 2", "ARRIBA  col 3", "ARRIBA  col 4", "ARRIBA  col 5", "ARRIBA  col 6",
    "ABAJO   col 1", "ABAJO   col 2", "ABAJO   col 3", "ABAJO   col 4", "ABAJO   col 5", "ABAJO   col 6"
};

// Devuelve 1 si calibro completo, 0 si se canceló (ESC).
static int calibrar(void) {
    SDL_Color blanco = {235,235,235,255}, ama = {255,210,40,255};
    int objetivo = 0;   // 0..11 celdas, 12 = boton salir
    ledApagarTodo();
    for (int c = 0; c < NUM_CELDAS; c++) bindCelda[c].joy = -1;
    bindSalir.joy = -1;

    while (objetivo <= NUM_CELDAS) {
        // pista en el panel: enciende el LED del objetivo (salir = LED extra 0)
        for (int i = 0; i < NUM_LEDS; i++) ledEstado[i] = -1; // forzar reenvio
        for (int c = 0; c < NUM_CELDAS; c++) led(CANAL[c], 0);
        led(0, 0);
        if (objetivo < NUM_CELDAS) led(CANAL[objetivo], 255);
        else led(0, 255);

        SDL_Event e;
        int hecho = 0;
        while (!hecho) {
            if (!SDL_WaitEvent(&e)) continue;
            if (e.type == SDL_QUIT) return 0;
            if (e.type == SDL_KEYDOWN && e.key.keysym.sym == SDLK_ESCAPE) return 0;
            if (e.type == SDL_JOYBUTTONDOWN) {
                int ji = joyIndex(e.jbutton.which);
                if (ji < 0) continue;
                if (objetivo < NUM_CELDAS) { bindCelda[objetivo].joy = ji; bindCelda[objetivo].btn = e.jbutton.button; }
                else { bindSalir.joy = ji; bindSalir.btn = e.jbutton.button; }
                objetivo++;
                hecho = 1;
            }
            // redibujar
            limpiarPantalla();
            texto("CALIBRACION", anchoV/2, altoV/4, fuenteBig, ama, 1);
            char msg[64];
            if (objetivo < NUM_CELDAS) snprintf(msg, sizeof msg, "Pulsa el boton:  %s", NOMBRE_CELDA[objetivo]);
            else snprintf(msg, sizeof msg, "Pulsa el boton de SALIR (boton 0)");
            texto(msg, anchoV/2, altoV/2, fuente, blanco, 1);
            texto("ESC para cancelar", anchoV/2, altoV*3/4, fuente, blanco, 1);
            SDL_RenderPresent(ren);
        }
    }
    guardarMapa();
    ledApagarTodo();
    return 1;
}

// ---- juego: alcanza la meta --------------------------------------------------
// Devuelve A_MENU o A_SALIR.
static int jugarMeta(void) {
    SDL_Color blanco = {235,235,235,255};
    int cursor = 0, meta = 5, puntos = 0;
    Uint32 ini = SDL_GetTicks();
    ejeXact = ejeYact = 0;
    ledApagarTodo();

    for (;;) {
        Uint32 ahora = SDL_GetTicks();
        if (ahora - ini >= RONDA_MS) break;

        SDL_Event e;
        while (SDL_PollEvent(&e)) {
            if (e.type == SDL_QUIT) return A_SALIR;
            if (e.type == SDL_JOYBUTTONDOWN &&
                celdaDeBoton(joyIndex(e.jbutton.which), e.jbutton.button) == -2) return A_MENU;
            if (e.type == SDL_KEYDOWN && e.key.repeat == 0 &&
                teclaCelda(e.key.keysym.sym) == -2) return A_MENU;   // boton/ESC de salir -> menu
            int dx, dy; leerDireccion(&e, &dx, &dy);
            if (dx || dy) {
                int fila = cursor / 6, col = cursor % 6;
                if (dy < 0) fila = 0; else if (dy > 0) fila = 1;
                col += dx; if (col < 0) col = 0; else if (col > 5) col = 5;
                cursor = fila * 6 + col;
                if (cursor == meta) {
                    puntos++;
                    Mix_PlayChannel(-1, sfxOk, 0);
                    do { meta = rand() % NUM_CELDAS; } while (meta == cursor);
                }
            }
        }

        // LEDs: cursor fijo, meta parpadea, resto apagado
        int blink = (SDL_GetTicks() / 300) % 2;
        for (int c = 0; c < NUM_CELDAS; c++)
            led(CANAL[c], c == cursor ? 255 : (c == meta ? (blink ? 255 : 40) : 0));

        limpiarPantalla();
        texto("ALCANZA LA META", anchoV/2, 40, fuenteBig, blanco, 1);
        char s[64];
        snprintf(s, sizeof s, "Puntos: %d", puntos);          texto(s, anchoV/2, altoV/2 - 30, fuenteBig, blanco, 1);
        snprintf(s, sizeof s, "Record: %d", recordMeta);      texto(s, anchoV/2, altoV/2 + 40, fuente, blanco, 1);
        snprintf(s, sizeof s, "%d s", (RONDA_MS - (ahora - ini)) / 1000); texto(s, anchoV/2, altoV - 70, fuente, blanco, 1);
        if (demo) dibujarPanelDemo();
        SDL_RenderPresent(ren);
        SDL_Delay(8);
    }
    if (puntos > recordMeta) { recordMeta = puntos; guardarPuntajes(); }
    pantallaFin(puntos, recordMeta);
    return A_MENU;
}

// ---- juego: whack-a-mole -----------------------------------------------------
static int jugarTopo(void) {
    SDL_Color blanco = {235,235,235,255};
    int puntos = 0, topo = -1;
    Uint32 ini = SDL_GetTicks();
    Uint32 topoHasta = 0, proximo = ini + 400;
    ledApagarTodo();

    for (;;) {
        Uint32 ahora = SDL_GetTicks();
        if (ahora - ini >= RONDA_MS) break;

        // gestionar el topo
        if (topo < 0 && ahora >= proximo) {
            topo = rand() % NUM_CELDAS;
            int dur = 1200 - puntos * 25; if (dur < 400) dur = 400;   // acelera
            topoHasta = ahora + dur;
            Mix_PlayChannel(-1, sfxTopo, 0);
        } else if (topo >= 0 && ahora >= topoHasta) {
            topo = -1; proximo = ahora + 300;                          // se escapo
        }

        SDL_Event e;
        while (SDL_PollEvent(&e)) {
            int c = -3;
            if (e.type == SDL_QUIT) return A_SALIR;
            if (e.type == SDL_JOYBUTTONDOWN) c = celdaDeBoton(joyIndex(e.jbutton.which), e.jbutton.button);
            else if (e.type == SDL_KEYDOWN && e.key.repeat == 0) c = teclaCelda(e.key.keysym.sym);
            if (c == -2) return A_MENU;               // boton/ESC de salir -> menu
            if (c >= 0) {
                if (c == topo) { puntos++; Mix_PlayChannel(-1, sfxOk, 0); topo = -1; proximo = ahora + 250; }
                else Mix_PlayChannel(-1, sfxFail, 0);
            }
        }

        for (int c = 0; c < NUM_CELDAS; c++) led(CANAL[c], c == topo ? 255 : 0);

        limpiarPantalla();
        texto("DALE AL TOPO", anchoV/2, 40, fuenteBig, blanco, 1);
        char s[64];
        snprintf(s, sizeof s, "Puntos: %d", puntos);     texto(s, anchoV/2, altoV/2 - 30, fuenteBig, blanco, 1);
        snprintf(s, sizeof s, "Record: %d", recordTopo); texto(s, anchoV/2, altoV/2 + 40, fuente, blanco, 1);
        snprintf(s, sizeof s, "%d s", (RONDA_MS - (ahora - ini)) / 1000); texto(s, anchoV/2, altoV - 70, fuente, blanco, 1);
        if (demo) dibujarPanelDemo();
        SDL_RenderPresent(ren);
        SDL_Delay(8);
    }
    if (puntos > recordTopo) { recordTopo = puntos; guardarPuntajes(); }
    pantallaFin(puntos, recordTopo);
    return A_MENU;
}

// ---- fin de ronda ------------------------------------------------------------
static void pantallaFin(int puntos, int record) {
    SDL_Color blanco = {235,235,235,255}, ama = {255,210,40,255};
    if (musFin) Mix_PlayMusic(musFin, 1);
    ledApagarTodo();
    Uint32 fin = SDL_GetTicks() + 4000;
    while (SDL_GetTicks() < fin) {
        SDL_Event e;
        while (SDL_PollEvent(&e)) {
            if (e.type == SDL_QUIT || e.type == SDL_JOYBUTTONDOWN ||
                (e.type == SDL_KEYDOWN)) { fin = 0; }
        }
        limpiarPantalla();
        char s[64];
        texto("FIN", anchoV/2, altoV/3, fuenteBig, ama, 1);
        snprintf(s, sizeof s, "Puntos: %d", puntos);  texto(s, anchoV/2, altoV/2, fuenteBig, blanco, 1);
        snprintf(s, sizeof s, "Record: %d", record);  texto(s, anchoV/2, altoV/2 + 70, fuente, blanco, 1);
        SDL_RenderPresent(ren);
        SDL_Delay(16);
        if (fin == 0) break;
    }
}

// ---- menu --------------------------------------------------------------------
static int menu(void) {
    SDL_Color blanco = {235,235,235,255}, ama = {255,210,40,255}, gris = {120,120,130,255};
    const char *nombres[2] = { "ALCANZA LA META", "DALE AL TOPO" };
    int sel = 0;
    ejeXact = ejeYact = 0;
    if (musMenu) Mix_PlayMusic(musMenu, -1);
    ledApagarTodo();
    Uint32 t0 = SDL_GetTicks();

    for (;;) {
        SDL_Event e;
        while (SDL_PollEvent(&e)) {
            if (e.type == SDL_QUIT) return A_SALIR;
            if (e.type == SDL_KEYDOWN && e.key.repeat == 0) {
                SDL_Keycode k = e.key.keysym.sym;
                if (k == SDLK_ESCAPE || k == SDLK_0) return A_SALIR;
                if (k == SDLK_RETURN || k == SDLK_SPACE) { Mix_HaltMusic(); return sel == 0 ? 1 : 2; }
            }
            if (e.type == SDL_JOYBUTTONDOWN) {
                int c = celdaDeBoton(joyIndex(e.jbutton.which), e.jbutton.button);
                if (c == -2) return A_SALIR;          // salir del programa
                if (c >= 0) { Mix_HaltMusic(); return sel == 0 ? 1 : 2; }  // cualquier boton confirma
            }
            int dx, dy; leerDireccion(&e, &dx, &dy);
            if (dx) sel ^= 1;   // izq/der alterna entre los dos juegos
        }

        // un LED paseando por el panel como adorno del menu
        int paso = (SDL_GetTicks() - t0) / 150 % NUM_CELDAS;
        for (int c = 0; c < NUM_CELDAS; c++) led(CANAL[c], c == paso ? 180 : 0);

        limpiarPantalla();
        texto("MINIJUEGOS DE LUCES", anchoV/2, altoV/5, fuenteBig, ama, 1);
        for (int i = 0; i < 2; i++)
            texto(nombres[i], anchoV/2, altoV/2 - 60 + i*64, fuenteBig, i == sel ? blanco : gris, 1);
        texto("stick: elegir   boton: jugar   boton 0: salir", anchoV/2, altoV - 60, fuente, gris, 1);
        if (demo) {
            texto("teclado: flechas elegir   ENTER jugar   ESC salir", anchoV/2, altoV - 30, fuente, gris, 1);
            dibujarPanelDemo();
        }
        SDL_RenderPresent(ren);
        SDL_Delay(16);
    }
}

// ---- main --------------------------------------------------------------------
int main(void) {
    srand(time(NULL) ^ getpid());
    demo = (getenv("MINIJUEGOS_DEMO") != NULL);

    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_JOYSTICK | SDL_INIT_AUDIO) < 0) {
        fprintf(stderr, "SDL_Init: %s\n", SDL_GetError());
        return 1;
    }
    char *bp = SDL_GetBasePath();
    snprintf(rutaBase, sizeof rutaBase, "%s", bp ? bp : "./");
    if (bp) SDL_free(bp);

    win = SDL_CreateWindow("Minijuegos", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
                           1024, 768, demo ? 0 : SDL_WINDOW_FULLSCREEN_DESKTOP);
    ren = SDL_CreateRenderer(win, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
    if (!ren) ren = SDL_CreateRenderer(win, -1, SDL_RENDERER_SOFTWARE);  // sin GPU (p.ej. pruebas)
    if (!win || !ren) { fprintf(stderr, "ventana: %s\n", SDL_GetError()); return 1; }
    SDL_GetRendererOutputSize(ren, &anchoV, &altoV);
    if (!demo) SDL_ShowCursor(SDL_DISABLE);

    if (TTF_Init() < 0) { fprintf(stderr, "TTF_Init: %s\n", TTF_GetError()); return 1; }
    char rf[1100]; snprintf(rf, sizeof rf, "%sfuente.ttf", rutaBase);
    fuente    = TTF_OpenFont(rf, 28);
    fuenteBig = TTF_OpenFont(rf, 52);
    if (!fuente || !fuenteBig) { fprintf(stderr, "fuente %s: %s\n", rf, TTF_GetError()); return 1; }

    Mix_Init(MIX_INIT_MP3 | MIX_INIT_OGG);
    if (Mix_OpenAudio(44100, MIX_DEFAULT_FORMAT, 2, 1024) < 0)
        fprintf(stderr, "audio: %s (se juega sin sonido)\n", Mix_GetError());
    char rs[1200];
    snprintf(rs, sizeof rs, "%ssonidos/correct.wav", rutaBase);     sfxOk   = Mix_LoadWAV(rs);
    snprintf(rs, sizeof rs, "%ssonidos/incorrect.wav", rutaBase);   sfxFail = Mix_LoadWAV(rs);
    snprintf(rs, sizeof rs, "%ssonidos/MW_KeyAppear.wav", rutaBase);sfxTopo = Mix_LoadWAV(rs);
    snprintf(rs, sizeof rs, "%ssonidos/menu.mp3", rutaBase);        musMenu = Mix_LoadMUS(rs);
    snprintf(rs, sizeof rs, "%ssonidos/fin.mp3", rutaBase);         musFin  = Mix_LoadMUS(rs);

    numJoys = SDL_NumJoysticks(); if (numJoys > 16) numJoys = 16;
    for (int i = 0; i < numJoys; i++) {
        joys[i] = SDL_JoystickOpen(i);
        joyId[i] = joys[i] ? SDL_JoystickInstanceID(joys[i]) : -1;
    }

    cargarPuntajes();
    fifoAbrir();
    fifoLinea("[");             // reclamar el panel al demonio

    // En demo se juega con teclado, no hace falta el mapa de botones del panel.
    if (!demo && !cargarMapa())   // sin mapa -> calibrar antes de jugar
        calibrar();               // (si se cancela, seguimos con los botones sin mapear)

    for (;;) {
        int eleccion = menu();
        if (eleccion == A_SALIR) break;
        int r = (eleccion == 1) ? jugarMeta() : jugarTopo();  // cada juego muestra su fin de ronda
        if (r == A_SALIR) break;
    }

    fifoLinea("]");             // soltar el panel -> el demonio vuelve a atraccion
    ledApagarTodo();
    if (fifoFd >= 0) close(fifoFd);
    SDL_Quit();
    return 0;
}
