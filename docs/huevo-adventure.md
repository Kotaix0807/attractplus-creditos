# Huevo de pascua: el código Konami del Jugador 2 → Adventure

Idea de Eloy (2026-11-02). Un secreto en la cabina: si en el menú del frontend
se introduce el **código Konami con el segundo joystick**, suena una pequeña
ceremonia (acierto a acierto → sonido de desbloqueo → fundido a negro →
animación de una llave abriendo un cerrojo) y se lanza el **port propio de
Adventure** que programó Eloy. Al ganar el primer nivel, el juego felicita con
«Eres un superjugador». Se sale con la tecla de SALIR.

Este documento es el *diseño* y el reparto de responsabilidades. Estado de hoy:
**andamiaje + preguntas abiertas**, no está terminado ni desplegado.

## El port (REAL)

Está en **`/home/eloy/Dev/arcade/Adventure_linux/`**, y es **C++**: la
reconstrucción *Adventure: Revisited* de Peter Hirschberg del Adventure de Atari
2600, adaptada por Eloy:

- `Adventure.cpp` (140 KB) — el juego (la máquina de estados, las salas, los
  objetos, el dragón, la llave, los castillos). Lógica pura, sin plataforma.
- `LinuxAdventure.cpp` — la capa SDL2/SDL_mixer (ventana, teclado, audio).
- `Adventure.h`, `Makefile`, `sprite_editor.html`.
- `adventure` — el **ejecutable** (ELF x86-64) que se lanza.
- `sounds/` — los sonidos del juego en sí (`win-good.mp3`, `chomp.mp3`,
  `death.mp3`, `slay.mp3`, `drop.mp3`, `pick-up.mp3`), que **carga el propio
  port** desde `<dir del exe>/sounds/*.mp3` (`LinuxAdventure.cpp:59`).

### Qué confirmé leyendo el C++ (importa para el reparto)

- **Ganar** = llevar el cáliz (`OBJECT_CHALISE`) a la sala `0x12` (el castillo
  dorado): en `Adventure.cpp:1309-1319` eso pone `gameState = GAMESTATE_WIN`,
  arranca el parpadeo (`winFlashTimer`) y suena `SOUND_WON`.
- **Los «niveles»** son los tres juegos de Adventure (`GAMESTATE_ACTIVE_1/2/3`),
  que se eligen con el *select switch* (tecla `1`). «Ganar el nivel 1» = ganar
  jugando el juego 1. El disparo de victoria no distingue hoy desde qué juego se
  ganó; para que «Eres un superjugador» sea específico del nivel 1 habría que
  recordar el juego activo al entrar en `GAMESTATE_WIN` (una línea en C).
- **Ya hay una pantalla de felicitación**: en `GAMESTATE_WIN`, `Adventure.cpp`
  (~1897) dibuja `objectGfxcongrats` + nombres + instagram con `DrawText`. O
  sea, el sitio donde poner/estilar «Eres un superjugador» **ya existe**.
- **Salir** = `ESC` (`LinuxAdventure.cpp:79`). Encaja con la cabina, donde la
  tecla SALIR del mueble es `UI_CANCEL` = Esc. Nada que mapear.

Conclusión de reparto: como es **código fuente de Eloy**, la victoria, la
pantalla «superjugador» y su sonido se resuelven **dentro del C++**, no leyendo
RAM (eso es para ROMs cerradas; aquí sobra).

## Arquitectura (reparto frontend / juego)

```
  MENÚ del frontend (Attract-Mode Plus)
    └─ config/plugins/HuevoAdventure.nut   (Squirrel)
         · escucha el código Konami en los controles del JUGADOR 2
         · sonido por acierto / error (regla del >=1) / desbloqueo / llave
         · al completar: fundido a negro + animación llave→cerrojo (arte pend.)
         · lanza el port:  fe.plugin_command(".../Adventure_linux/adventure")
                                   │
                                   ▼
  PORT (/home/eloy/Dev/arcade/Adventure_linux/adventure, C++/SDL2)  ← de Eloy
         · el juego
         · al ganar (cáliz→castillo dorado)  →  pantalla "Eres un superjugador"
           + sonido "50. Fortress Clear.mp3"   (TODO en el C++, ver abajo)
         · ESC  →  vuelve al frontend
```

La frontera es limpia: **todo lo del menú es `.nut`**; **todo lo de dentro del
juego (victoria, superjugador, su sonido) es C++**, porque el estado del juego
ya vive ahí.

## Los sonidos (reales) y dónde viven

Están hoy en la raíz del repo (`/home/eloy/Dev/arcade/attractplus/`). Reparto:

| Fichero | Para | Lo reproduce |
|---|---|---|
| `correct.wav` | cada tecla correcta del combo | el `.nut` (`snd_ok`) |
| `incorrect.wav` | fallo (solo si ≥1 acierto) | el `.nut` (`snd_err`) |
| `49. Secret Exit!.mp3` | momento del desbloqueo | el `.nut` (`snd_unlock`) |
| `MW_KeyAppear.wav` | aparición de la llave en la animación | el `.nut` (`snd_key`) |
| `50. Fortress Clear.mp3` | «Eres un superjugador» / nivel superado | **el port (C++)** |

**Dónde deben vivir para que `fe.add_sound` los encuentre:** el plugin resuelve
las rutas relativas contra **`fe.script_dir`** (el directorio del propio plugin,
`fe_vm.cpp:1783`). Por tanto los **cuatro sonidos del menú** se instalan **junto
a `HuevoAdventure.nut`** (en la cabina, `~/.attract/plugins/`). El `.nut` ya trae
esos nombres por defecto; no hay placeholders.

**Paso de instalación (pendiente, NO lo hice):** copiar `correct.wav`,
`incorrect.wav`, `49. Secret Exit!.mp3` y `MW_KeyAppear.wav` al directorio del
plugin (en desarrollo, `config/plugins/`; en la cabina, `~/.attract/plugins/`).
Lo natural es que la tarea del instalador que despliegue el plugin copie también
sus sonidos. **`50. Fortress Clear.mp3` NO va con el plugin**: va a
`Adventure_linux/sounds/` y lo reproduce el C++ (hay que añadirlo a su tabla de
sonidos y dispararlo en `GAMESTATE_WIN`).

## La máquina de estados del detector (reglas EXACTAS de Eloy)

Estados: `escucha` (contando aciertos, `m_current` de 0 a N) y `ceremonia`
(desbloqueo → fundido → animación → lanzar).

Por cada tick, mientras `m_current < N`:

1. Se lee el control esperado (`code[m_current]`) con `fe.get_input_state`. La
   pulsación se registra **al SOLTAR** (como KonamiCode), para no contar varios
   ticks de una misma pulsación.
2. **Acierto** → `m_current++` y **suena `correct.wav`**. Se apunta el tiempo
   para el timeout.
3. **Equivocación** (se pulsa otro control del conjunto) → reinicio. **Suena
   `incorrect.wav` SOLO si `m_current > 0`** (ya llevabas ≥1 acierto). Con
   `m_current == 0` el fallo pasa **desapercibido, sin sonido**.
4. **Timeout de 2 s** sin avanzar (`RESET_TIME = 2000`) → se trata como
   incorrecto (mismo criterio de sonido: solo si llevabas ≥1).

Al completar (`m_current == N`) → `ceremonia`:

1. Suena `49. Secret Exit!.mp3` (desbloqueo).
2. Fundido a negro (alpha 0→255 en `FADE_MS`), con un velo de `zorder` máximo
   creado en `Transition.StartLayout`.
3. A mitad del fundido «aparece» la llave: suena `MW_KeyAppear.wav`. (El **arte**
   de la llave/cerrojo aún no existe: placeholder.)
4. Al terminar el fundido, lanzar el port y, al volver, quitar el velo.

## Preguntas abiertas para Eloy (corta)

1. **El combo**: ¿el clásico `↑↑↓↓←→←→ B A`, o uno propio? ¿Qué **2 botones del
   Jugador 2** son la «A» y la «B»? (Los controles del J2 se mapean al configurar
   el plugin, campos `is_input`.)
2. **Arte de la animación llave→cerrojo** (más allá del sonido, que ya está):
   ¿tienes sprites/fotogramas o un vídeo? ¿Duración y estilo? Hoy es placeholder.
3. **Vía de lanzamiento**: `fe.plugin_command` directo al binario (simple, el
   frontend se bloquea hasta ESC; recomendado para un secreto) **vs.** un
   emulador oculto `config/cabina/adventure.cpp` estilo `hypseus.cfg` (más
   integrado). Recomiendo el directo.
4. **Instalar/recompilar `adventure` en la cabina**: el binario de hoy es x86-64
   compilado en el portátil; la cabina también es x86-64, pero conviene
   **recompilarlo allí** (tiene `Makefile`, pide SDL2 + SDL2_mixer) o copiarlo
   con sus libs y su carpeta `sounds/`. ¿Ruta final en la cabina
   (`/home/arcade/Adventure_linux/adventure`)? Hay que ajustar `port_exe`.

## Lo que NO se hizo (y por qué)

- No se desplegó ni commiteó nada (es diseño).
- No se implementó la animación (falta arte: pregunta 2).
- No se tocó el C++ del port: la pantalla «superjugador» y el disparo de
  `50. Fortress Clear.mp3` en `GAMESTATE_WIN` los hará Eloy (es su código;
  además ya existe ahí el sitio del `congrats`).
- No se movieron los sonidos a su sitio (paso de instalación anotado arriba).
- No se eligió la vía de lanzamiento ni se creó `adventure.cfg` (pregunta 3).
