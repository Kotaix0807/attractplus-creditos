#include <SDL2/SDL_image.h>
#include <SDL2/SDL_joystick.h>
#include <SDL2/SDL_mixer.h>
#include <SDL2/SDL_render.h>
#include <SDL2/SDL_video.h>
#include <stdio.h>
#include <SDL2/SDL.h>
#include <SDL2/SDL_ttf.h>
#include <unistd.h>

#define NUM_CELDAS 12
#define CELDA_SALIR (-2)
#define STICK_EMPUJADO 16000   // pasar de aqui = stick empujado
#define STICK_CENTRO    8000   // bajar de aqui = stick de vuelta al centro


enum{
    MENU = 0,
    MOLE,
    GOAL,
    END_GAME,
    END
};

enum{
    //SFX
    SFX_WHACK_MOLE = 0,
    SFX_MOLE,
    SFX_GOAL,
    SFX_FAIL,
};

enum {
    //MUSIC
    MUSIC_MENU,
    MUSIC_MOLE,
    MUSIC_GOAL,
    MUSIC_END_GAME
};

typedef struct {
    SDL_Joystick *controller;
    SDL_JoystickID id;
} input;

typedef struct{
    int controller;
    int pressed;
} button;

typedef struct{
    char baseRoute[1024];
    int state;
    int winW;
    int winH;
    int isRunning;
    float deltaTime;   // segundos desde el frame anterior (p.ej. 0.016 a 60 fps)
    int numJoys;       // How many joysticks connected.

    TTF_Font     *font;
    TTF_Font     *bigFont;
    SDL_Window   *win;
    SDL_Renderer *ren;
    input        *joyStick;
} gameStruct;

typedef struct {
    int celda;
    int dx;
    int dy;
} Entrada;

typedef struct{
    char path[1024];
    Mix_Music *mus;
} music;

typedef struct{
    char path[1024];
    double pitch;
    Mix_Chunk *sfx;
} sfx;


//Global Variables
sfx gameSfx[4]; //meanwhile 5
music gameMusic[5]; //also 5

void loadSfx(gameStruct *game, Mix_Chunk **sfx, const char *name) {
    char path[1200];
    snprintf(path, sizeof(path), "%ssonidos/%s", game->baseRoute, name);
    *sfx = Mix_LoadWAV(path);
}

void loadMus(gameStruct *game, Mix_Music **mus, const char *name) {
    char rm[1200];
    snprintf(rm, sizeof(rm), "%ssonidos/%s", game->baseRoute, name);
    *mus = Mix_LoadMUS(rm);
}

void initMix(gameStruct *game) {
    Mix_Init(MIX_INIT_MP3 | MIX_INIT_OGG);
    if (Mix_OpenAudio(44100, MIX_DEFAULT_FORMAT, 2, 1024) < 0)
        fprintf(stderr, "audio: %s (se juega sin sonido)\n", Mix_GetError());

    Mix_ReserveChannels(1);   // canal 0 solo para sonarFallo; el -1 ya no lo coge

    loadSfx(game, &gameSfx[SFX_GOAL].sfx, "dragon-coin.wav");
    loadSfx(game, &gameSfx[SFX_WHACK_MOLE].sfx,   "clap-pop.wav");
    loadSfx(game, &gameSfx[SFX_FAIL].sfx, "incorrect.wav");
    loadSfx(game, &gameSfx[SFX_MOLE].sfx, "screen-scroll.wav");
    
    loadMus(game, &gameMusic[MUSIC_MENU].mus, "mainMus.mp3");
    loadMus(game, &gameMusic[MUSIC_MOLE].mus, "mole.mp3");
    loadMus(game, &gameMusic[MUSIC_END_GAME].mus, "moleEnd.mp3");
    loadMus(game, &gameMusic[MUSIC_GOAL].mus, "pathGame.mp3");
}

int initFont(gameStruct *game) {
    if (TTF_Init() < 0)
    {
        fprintf(stderr, "TTF_Init: %s\n", TTF_GetError());
        return 1;
    }
    
    char rf[1100];
    snprintf(rf, sizeof rf, "%sfuente.ttf", game->baseRoute);
    game->font    = TTF_OpenFont(rf, 28);
    game->bigFont = TTF_OpenFont(rf, 52);
    if (!game->font || !game->bigFont) 
    { 
        fprintf(stderr, "fuente %s: %s\n", rf, TTF_GetError()); 
        return 1; 
    }
    
    return 0;
}

int initJoysticks(gameStruct *game) {
    int *numJoys = &game->numJoys;
    *numJoys = SDL_NumJoysticks();

    if (*numJoys > 16)
        *numJoys = 16;

    game->joyStick = malloc(sizeof(input) * *numJoys);

    if(!game->joyStick)
    {
        fprintf(stderr, "Malloc failed\n");
        return 1;
    }

    input *joys = game->joyStick;

    for (int i = 0; i < *numJoys; i++) {
        joys[i].controller = SDL_JoystickOpen(i);
        joys[i].id = joys[i].controller ? SDL_JoystickInstanceID(joys[i].controller) : -1;
    }
    return 0;
}

int initSDL(gameStruct *game) {
    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_JOYSTICK | SDL_INIT_AUDIO) < 0) {
        fprintf(stderr, "SDL_Init: %s\n", SDL_GetError());
        return 1;
    }
    
    game->win = SDL_CreateWindow("Minijuegos", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
                           1024, 768, SDL_WINDOW_OPENGL);
    
    game->ren = SDL_CreateRenderer(game->win, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
    
    if (!game->ren)
        game->ren = SDL_CreateRenderer(game->win, -1, SDL_RENDERER_SOFTWARE);   // sin GPU (p.ej. pruebas)

    if (!game->win || !game->ren)
    {
        fprintf(stderr, "window: %s\n", SDL_GetError());
        return 1;
    }

    //Get basepath
    char *basePath = SDL_GetBasePath();
    snprintf(game->baseRoute, sizeof(game->baseRoute), "%s", basePath ? basePath : "./");

    if (basePath)
        SDL_free(basePath);

    SDL_ShowCursor(SDL_DISABLE);

    //Set render size
    SDL_GetRendererOutputSize(game->ren, &game->winW, &game->winH);

    //Init font
    if(initFont(game))
        return 1;

    initMix(game);
    IMG_Init(IMG_INIT_PNG);

    if(initJoysticks(game))
        return 1;

    //Once all loaded, set menu as current window
    game->state = MENU;
    game->isRunning = 1;

    return 0;
}

void exitGame(gameStruct *game) {
    for(int i = 0; i < 4; i++)
    {
        if(gameSfx[i].sfx)
            Mix_FreeChunk(gameSfx[i].sfx);
    }

    for(int i = 0; i < 5; i++)
    {
        if(gameMusic[i].mus)
            Mix_FreeMusic(gameMusic[i].mus);
    }


    int *numJoys = &game->numJoys;
    input *joyStick = game->joyStick;

    //TODO: Arreglar esta ensalada.
    for (int i = 0; i < *numJoys; i++) {
        if(joyStick[i].controller)
            SDL_JoystickClose(joyStick[i].controller);
    }
    free(joyStick);


    if(game->font)
        TTF_CloseFont(game->font);

    if(game->bigFont)
        TTF_CloseFont(game->bigFont);

    TTF_Quit();

    IMG_Quit();

    Mix_CloseAudio();
    Mix_Quit();
    
    //First the renderer
    SDL_DestroyRenderer(game->ren);
    //Then the renderer
    SDL_DestroyWindow(game->win);

    SDL_Quit();
}

static int pasoDelEje(int valor, int *empujado) {
    if (!*empujado && valor >  STICK_EMPUJADO)
    {
        *empujado = 1;
        return 1;
    }
    if (!*empujado && valor < -STICK_EMPUJADO)
    {
        *empujado = 1;
        return -1;
    }
    if (valor > -STICK_CENTRO && valor < STICK_CENTRO)
        *empujado = 0;   // volvio al centro
    return 0;
}

void leerDireccion(const SDL_Event *e, int *dx, int *dy) {
    if (e->type == SDL_JOYAXISMOTION) {

        if (e->jaxis.axis == 0)
            *dx = pasoDelEje(e->jaxis.value, &stickXEmpujado);
        if (e->jaxis.axis == 1)
            *dy = pasoDelEje(e->jaxis.value, &stickYEmpujado);
    }
    if (e->type == SDL_JOYHATMOTION) {
        Uint8 cruceta = e->jhat.value;
        if (cruceta & SDL_HAT_LEFT)  *dx = -1;
        if (cruceta & SDL_HAT_RIGHT) *dx =  1;
        if (cruceta & SDL_HAT_UP)    *dy = -1;
        if (cruceta & SDL_HAT_DOWN)  *dy =  1;
    }
}

int joyIndex(gameStruct *game, SDL_JoystickID id) {
    for (int i = 0; i < game->numJoys; i++)
        if (game->joyStick[i].id == id)
            return i;
    return -1;
}

int celdaDeBoton(int mando, int boton) {
    if (button.mando == mando && botonSalir.boton == boton)
        return CELDA_SALIR;
    
    for (int celda = 0; celda < NUM_CELDAS; celda++)
        if (botonDeCelda[celda].mando == mando && botonDeCelda[celda].boton == boton)
            return celda;

    return -1;
}

Entrada leerEntrada(gameStruct *game, const SDL_Event *e) {

    Entrada in = { -1, 0, 0 };

    /*
    if (e->type == SDL_QUIT)
    {
        in.cerrar = 1;
        return in;
    }
    */
    
    if (e->type == SDL_JOYBUTTONDOWN) {
        int celda = celdaDeBoton(joyIndex(game, e->jbutton.which), e->jbutton.button);
        
        if (celda == CELDA_SALIR)
            in.salir = 1;
        else if (celda >= 0)
            in.celda = celda;
        
        return in;
    }
    /*
    if (e->type == SDL_KEYDOWN && e->key.repeat == 0) {   // teclado (modo demo)
    switch (e->key.keysym.sym) {
        case SDLK_0:
            in.salir = 1;
            break;
            
        case SDLK_SPACE:
            in.jugar = 1;
            break;
        
        case SDLK_LEFT:
            in.dx = -1;
            break;

        case SDLK_RIGHT:
            in.dx =  1;
            break;
        
        case SDLK_UP:
            in.dy = -1;
            break;
        
        case SDLK_DOWN:
            in.dy =  1;
            break;

        default: {
            int c = teclaCelda(e->key.keysym.sym);
            if (c >= 0)
                in.celda = c;
        }
    }
    return in;
}
*/

    leerDireccion(e, &in.dx, &in.dy);   // ejes / cruceta del mando
    return in;
}

void input(gameStruct *game)
{


}

// Todo lo que se mueva se multiplica por game->deltaTime, así la velocidad
// es en "unidades por segundo" y no depende de los fps.
// Ejemplo: x += 200 * game->deltaTime;   // 200 píxeles por segundo
void logic(gameStruct *game)
{



}


void render(gameStruct *game)
{
    SDL_RenderPresent(game->ren);


}

int main()
{
    gameStruct game;
    if(initSDL(&game))
        return 1;

    const int TARGET_FPS = 60;
    const Uint32 FRAME_DELAY = 1000 / TARGET_FPS; // ~16ms per frame

    Uint32 frameStart;
    Uint32 frameTime;
    Uint32 lastFrame = SDL_GetTicks();

    while (game.isRunning) {
        frameStart = SDL_GetTicks();

        // deltaTime: cuánto tiempo pasó desde el frame anterior, en segundos
        game.deltaTime = (frameStart - lastFrame) / 1000.0f;
        lastFrame = frameStart;

        // Si el juego se trabó (ventana movida, carga lenta...), no dar un salto enorme
        if (game.deltaTime > 0.1f)
            game.deltaTime = 0.1f;

        input(&game);
        logic(&game);
        render(&game);

        frameTime = SDL_GetTicks() - frameStart;

        if (FRAME_DELAY > frameTime) {
            SDL_Delay(FRAME_DELAY - frameTime);
        }
    }

    exitGame(&game);

    return 0;
}