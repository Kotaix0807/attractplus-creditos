# Panel de LEDs de botones + minijuegos (huevo de pascua)

Diseño acordado con Eloy (2026-11-06) e **implementado** el mismo día. Este
documento es el contrato entre las cuatro piezas; lo de *por qué* de las
decisiones sigue el estilo de `docs/panel.md`.

**Estado (2026-11-06):** las cuatro piezas escritas y verificadas en hp-envy
hasta donde se puede sin la cabina — `Arcade.ino` compila (Uno, 47% flash);
`moneyBank.py` probado de punta a punta contra un PTY (arbitraje A/B/minijuego +
FIFO); `minijuegos/` compila y arranca headless con el FIFO correcto;
`Minijuegos.nut` escrito; `creditos.lua` con `luac` y `correr.sh` en verde.
Falta probarlo **en la cabina** (lista de pendientes al final). Sin commit.

## Qué es

La cabina lleva un **módulo PCA9685** (PWM por I2C, 0x40) que controla la
intensidad de los **13 LEDs de los botones** del panel y, en el canal 13, el
**relé del monedero**. Con eso se quieren tres cosas:

1. **Atracción:** cuando AM+ está en el menú sin hacer nada, el panel corre
   animaciones de luces (las que ya hay en `ledArcadeTest.ino`).
2. **En MAME:** iluminar *suavemente* (con fundido/respiración) solo los botones
   que usa el juego en marcha. Ej.: Centipede → el botón de disparo. Sin el de
   start.
3. **Minijuegos (huevo de pascua):** al pulsar **P2 Start** en el frontend se
   abre un lanzador con dos juegos de luces (el de la grilla que ya existe y un
   whack-a-mole). Se juega en los **botones físicos**, mirando los LEDs.

El relé del monedero (abrir/cerrar la ranura) sigue existiendo y se controlará
también desde la web del panel para el re-calibrado.

**El display de 7 segmentos queda descartado** por ahora: fuera del sketch nuevo,
pero `arduino/cabina/cabina.ino` se conserva en el repo.

## Hardware y mapa del panel

- **PCA9685** en I2C (`0x40`). Canales 0–12 = LEDs de botones (brillo PWM 12 bits).
  Canal 13 = relé del monedero (solo on/off, sin PWM).
- **El PCA no se reinicia con el Arduino**, así que el sketch fuerza el relé a un
  estado conocido en el `setup()` (ya lo hace `ledArcadeTest.ino`).
- Layout de LEDs (de `ledArcadeTest.ino`): índice **0 = botón extra** (es el que
  Eloy usa como **salida** en la mayoría de juegos). Grilla 2×6 de jugadores:

  ```
  fila arriba:  1   8   6  | 3  10  12
  fila abajo:   2   7   5  | 4   9  11
                J1 (col 0-2)  J2 (col 3-5)
  ```

- **Serie a 115200 baudios** (antes 9600). Lo suben el sketch y el demonio a la
  vez; a 9600 el ancho de banda se quedaba corto para refrescar LEDs en el juego.

## Las cuatro piezas

| Pieza | Lenguaje | Rol | Fichero |
|---|---|---|---|
| Sketch del Arduino | C++ (Arduino) | Driver de LEDs + relé: corre animaciones de atracción, respira los botones de MAME, pinta lo que le manden en el minijuego. **Sin lógica de juego.** | `arduino/Arcade.ino` (reemplaza el actual) |
| Demonio | Python | **Único dueño del puerto serie.** Multiplexa todos los canales en el protocolo de una-letra-por-línea. | `arduino/moneyBank.py` (se amplía) |
| Frontend de minijuegos | C + SDL2 + SDL2_mixer | La **lógica** de los dos juegos, el menú, los puntajes y el sonido. Lee el mando por SDL, pinta los LEDs mandando comandos al demonio por un FIFO. | `minijuegos/` (nuevo) |
| Plugin del frontend | Squirrel (`.nut`) | Detecta **P2 Start** en AM+ y lanza el frontend de minijuegos (como el huevo de Adventure). | `config/plugins/` (nuevo) |

Dentro de MAME, **`creditos.lua`** apunta qué botones usa el juego (ver abajo).

## El protocolo de líneas (demonio → Arduino)

Una letra + valor + `\n`. La letra permite compartir el cable (es el mismo
criterio de `cabina.ino`). Todo lo manda el **demonio**, que es el único que abre
el puerto.

| Comando | Significado |
|---|---|
| `M0` / `M1` | Relé del monedero: 1 acepta monedas (hay partida), 0 cerrado. |
| `L<n>` | Brillo global 0–255 (escala todos los canales). |
| `A<n>` | Correr la animación de atracción `n` (0 = ninguna). La placa la ejecuta sola, frame a frame. |
| `B<hex>` | Botones de MAME: respiración suave en los LEDs de la máscara de 13 bits (`B1FFF` = todos, `B0` = ninguno). La placa anima el fundido. |
| `P<ch>,<v>` | Pintar: fija el LED `ch` (0–12) a brillo `v` (0–255). Para el minijuego; el PC manda solo los que cambian (deltas). |
| `X` | Apagar todos los LEDs (reinicio de estado al entrar/salir del minijuego). |

- Brillos en 0–255 (líneas cortas); el sketch los escala a los 12 bits del PCA.
- `A` y `B` son autónomos en la placa (el fundido/animación no gasta serie).
  `P` es control directo del PC, que lleva su propio estado y manda deltas.

## Arbitraje de estados (lo decide el demonio)

El demonio elige qué mandar según el estado, y la placa obedece el último
comando. Solo uno manda a la vez:

| Estado | Cómo lo sabe el demonio | Qué manda |
|---|---|---|
| **Minijuego** | hay sesión reclamada en el FIFO (ver abajo) | relé `M0`; reenvía los `P`/`X` del PC; **no** manda `A`/`B` |
| **En MAME** | `pgrep -x mame` (ya lo hace) | `M1`; `B<máscara>` con los botones del juego |
| **Atracción** | ni lo uno ni lo otro | `M0`; `A<n>` (animación/“show”) |
| siempre | fichero de brillo cambió | `L<n>` |

## IPC: ficheros y FIFO

Todo en `~/.attract/` (patrón ya existente). El demonio los vigila y manda al
Arduino solo lo que cambia.

| Ruta | Lo escribe | Para |
|---|---|---|
| `monedero_switch` | `creditos.lua` | relé (`M`), ya existe |
| `botones_juego` | `creditos.lua` | botones que usa el juego → `B` (nuevo) |
| `brillo_leds` | web del panel / config | brillo global → `L` (nuevo) |
| `arduino_fifo` | frontend de minijuegos | **FIFO** en tiempo real: líneas `P`/`X` + reclamar/soltar el control (nuevo) |

- **El FIFO** es un pipe con nombre. El frontend escribe `[` para reclamar el
  panel al entrar y `]` al salir; entre medias, las líneas crudas (`P6,200`, `X`).
  El demonio lee el FIFO **sin bloquear su bucle** (select/lectura no bloqueante)
  y reenvía al instante, así que la latencia es de un `write`, no de los 0.1 s
  del sondeo de ficheros.
- `creditos_juego` (el del display) **se deja de usar**; el display ya no está.

### Qué botones usa el juego (`botones_juego`)

`creditos.lua`, al arrancar el juego, enumera los `ioport` de P1 y apunta qué
botones de acción están activos (sin `START`). Escribe en `botones_juego` la
**máscara de LEDs** del panel ya traducida (13 bits, hex), o la lista de botones
y que traduzca el demonio. **El mapa “botón de MAME → canal de LED” es del
hardware de la cabina y hay que confirmarlo allí** (ver pendientes). Vive en un
solo sitio (el demonio, que es la pieza que toca el hardware).

## Los dos juegos (frontend SDL)

Ambos sobre la grilla **2×6 de botones de jugador (12 LEDs)**; el botón 0 (extra)
es **salir**.

- **Alcanza la meta** (portado del `.ino`): mueves con el stick; un botón
  parpadea = la meta; al llegar, +1 y nueva meta.
- **Whack-a-mole:** se enciende un botón al azar (el topo); le pegas al **botón
  físico** encendido antes de que desaparezca; suma y acelera; ronda con tiempo
  límite.

El PC lee el mando por SDL directamente (no pasa por el Arduino), lleva la
lógica/puntaje/menú en pantalla, y pinta los LEDs mandando `P`/`X` al FIFO.
**Salir:** botón 0.

Reglas finas del whack-a-mole (puntos, topos simultáneos, duración) y el aspecto
de la pantalla **se afinan al implementar**; si Eloy quiere, mockup antes.

## Sonido

SDL2_mixer (hace falta para MP3; WAV solo no basta). Assets en
**`minijuegos/sonidos/`** (se mueven ahí los cinco de la raíz del repo, mismos
nombres). Son de relleno; se reemplazan cambiando los ficheros de esa carpeta.
Mapa provisional: `correct.wav` = acierto, `incorrect.wav` = fallo,
`MW_KeyAppear.wav` = aparece el topo, los dos `.mp3` = música de menú / jingle de
fin de ronda.

## Puntajes

Récord por juego, entre sesiones, en `~/.attract/minijuegos.json` (fuera del
repo, escribible en la cabina).

## Instalación

Tarea nueva en `instalar.sh` (patrón de `tarea_monedero`): instala SDL2 +
SDL2_mixer por gestor, compila `minijuegos/`, e instala el plugin `.nut`.
**Opcional** (desmarcada salvo quizá GroovyArcade), porque es un huevo de pascua.

## Pendiente de confirmar en la cabina

- **El mapa “botón de MAME → canal de LED”** (qué LED es cada botón de acción de
  P1). Es cableado del panel; se mide allí.
- **El índice SDL del botón 0 (salida)** y de los botones de la grilla, para el
  whack-a-mole. Se lee probando el mando en la cabina.
- Que la placa aguante 115200 por el CH340 (estándar, pero se verifica).
- La tarifa del relé / web del panel para el brillo es trabajo aparte del panel
  (`docs/panel.md`); aquí solo se consume `brillo_leds`.
