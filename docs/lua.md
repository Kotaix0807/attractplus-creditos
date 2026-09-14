# Los scripts Lua del sistema de créditos, explicados a fondo

Este documento explica, fichero por fichero y función por función, cómo
funciona el código Lua de `creditos/`. Está escrito para alguien que sabe
programar pero no conoce ni este código ni la API de Lua que expone MAME.

No repite el *por qué* de las decisiones de diseño — eso está en
`CLAUDE.md`, que es el historial de la investigación —, sino el *cómo*:
qué hace cada línea, qué recibe y devuelve cada función, qué callbacks se
registran y cuándo se disparan, y qué pasaría si se quitara tal comprobación.

Para el método de **búsqueda** de la dirección de RAM del contador de
créditos (el algoritmo general, sus filtros, y por qué hacen falta tres
monedas y no dos), hay un documento aparte: `docs/direcciones-ram.md`. Aquí
sólo se documenta qué hace el script `buscar_creditos.lua` como programa,
sin repetir esa metodología.

## Índice

- [0. El mapa: quién llama a quién y qué ficheros se leen/escriben](#0-el-mapa)
- [1. `creditos.lua` — el orquestador](#1-creditoslua)
- [2. `monedero.lua` — la cuenta del monedero](#2-monederolua)
- [3. `tarifa.lua` — el DIP de tarifa](#3-tarifalua)
- [4. `aviso.lua` — el cuadro de salida](#4-avisolua)
- [5. `memoria.lua` — leer/escribir la RAM del juego](#5-memorialua)
- [6. `cerrojo.lua` — bloquear el botón de moneda](#6-cerrojolua)
- [7. `ajustes.lua` — el parser de `arranque.dat`](#7-ajusteslua)
- [8. `buscar_creditos.lua` — encontrar la dirección](#8-buscar_creditoslua)
- [9. `volcar.lua` — volcar el bloque de `hiscore.dat`](#9-volcarlua)
- [10. `poner_1c1c.lua` — pasada única de tarifa](#10-poner_1c1clua)
- [11. Los scripts de `pruebas/`](#11-los-scripts-de-pruebas)
- [12. Apéndice: chuleta de la API Lua de MAME](#12-apéndice-chuleta-de-la-api-lua-de-mame)

---

## 0. El mapa

Todo el sistema gira alrededor de un único script que MAME ejecuta como
`-autoboot_script`: **`creditos.lua`**. Es el único que MAME conoce; todos
los demás son bibliotecas normales que `creditos.lua` carga con `dofile()`
en tiempo de ejecución, desde el mismo directorio donde vive él (calculado
con `debug.getinfo(1,'S').source`, ver más abajo).

```
                         MAME lo invoca con -autoboot_script
                                       │
                                       ▼
                              ┌─────────────────┐
                              │  creditos.lua    │  el orquestador
                              └─────────────────┘
                          dofile()  │  │  │  │  │  │
              ┌───────────────────┘  │  │  │  │  └──────────────┐
              ▼                      ▼  │  ▼  │                 ▼
        tarifa.lua              monedero.lua  aviso.lua   ajustes.lua
      (lee el DIP,          (contabilidad del  (cuadro de   (arranque.dat:
       sin tocar MAME       fichero compartido, salida,      velocidad,
       más que leer el      sin tocar MAME)     sin tocar    segundos,
       campo)                                    MAME)       nvram...)
                                       │
                                       ▼
                                 memoria.lua        cerrojo.lua
                            (leer/escribir un    (bloquear el botón,
                             byte de la RAM,      sin tocar MAME más
                             sin tocar MAME       que recibir las
                             más que recibir      funciones de
                             la función leer)      bloquear/soltar)
```

Cuatro de los seis módulos que carga `creditos.lua` (`monedero.lua`,
`aviso.lua`, `memoria.lua`, `cerrojo.lua`) están escritos **a propósito sin
tocar la API de MAME**: reciben funciones (`leer`, `escribir`, `bloquear`,
`soltar`, `log`...) en vez de llamar directamente a `manager.machine...`.
Eso es lo que permite probarlos con un intérprete Lua a secas
(`pruebas/prueba_*.lua`), sin compilar ni arrancar MAME. `tarifa.lua` es la
excepción: sí llama a `manager.machine.ioport` porque su trabajo es
inspeccionar los DIP switches de la máquina en marcha, y no hay forma de
fingir eso sin una maqueta de MAME (por eso `poner_1c1c.lua` y `creditos.lua`
sí lo cargan directamente y sus pruebas —`prueba_tarifa.lua`— sólo prueban
las funciones puras `M.partir` y `M.con_premio`, no `M.buscar_dip`).

Los ficheros de datos que se leen/escriben, y quién lo hace:

| Fichero | Quién escribe | Quién lee |
|---|---|---|
| `$HOME/.attract/creditos.txt` | el plugin Squirrel del frontend, y `creditos.lua` (vía `monedero.lua`) | los dos, y sólo si `GA_MONEDERO=1` |
| `creditos/creditos.dat` | a mano / `buscar_creditos.lua` (por consola) | `creditos.lua` (vía `memoria.lua`) |
| `creditos/arranque.dat` | a mano | `creditos.lua` (vía `ajustes.lua`) |

`buscar_creditos.lua`, `volcar.lua` y `poner_1c1c.lua` **no** son
`-autoboot_script` de uso normal en la cabina: son herramientas de
diagnóstico/configuración que se lanzan a mano (o desde un `.sh` que
recorre la lista de juegos), una vez por juego, y que imprimen una línea de
resultado por `print()` en vez de vigilar una partida entera.

---

## 1. `creditos.lua`

### 1.1 Propósito y papel

Es el **`-autoboot_script`** que MAME ejecuta al arrancar cada partida. Hace
tres cosas, en este orden de importancia:

1. Al arrancar, mete (o no, según el modo) los créditos que le tocan a esta
   partida.
2. Durante toda la partida, vigila el botón físico de moneda y el contador
   de créditos del juego (si se conoce su dirección de RAM), y lleva la
   cuenta del monedero.
3. Si el jugador intenta salir dejando créditos dentro de la máquina, frena
   la salida y pinta un cuadro de aviso.

Es el módulo que **de verdad habla con MAME**: es quien busca el campo de
entrada de la moneda, quien lee y escribe el DIP y la RAM, quien pinta en
pantalla y quien se suscribe a los notificadores de frame. Todos los demás
módulos son bibliotecas de las que `creditos.lua` es cliente.

### 1.2 Cómo se invoca

Como `-autoboot_script` de MAME:

```bash
mame pacman -autoboot_script creditos.lua -autoboot_delay 0
```

`-autoboot_delay` en la práctica se deja a **0**: el script arranca desde el
frame 0 y es él mismo quien tapa la pantalla y gestiona el tiempo de carga
(ver la sección «arranque tapado» más abajo). El fichero se ejecuta como un
*chunk* de Lua normal, de arriba abajo, en el momento del autoboot; no es
una función que MAME llame periódicamente — el "periódicamente" lo consigue
suscribiéndose él mismo a `emu.add_machine_frame_notifier`.

También puede invocarse a mano para depurar, con las mismas variables de
entorno que usa la cabina (ver `GA_VERBOSO=1` para ver el log).

### 1.3 Variables de entorno (`GA_*`)

Todas son opcionales. Las que tienen equivalente en `arranque.dat` están
marcadas; para esas, la variable de entorno **manda sobre el fichero**
(precedencia: entorno > línea del juego > línea `defecto` > valor interno,
resuelta por `ajustes.lua`).

| Variable | Defecto | Qué hace |
|---|---|---|
| `GA_MONEDERO` | apagado | `1` activa el monedero compartido con el frontend. Apagado (el estado actual de la cabina) = monedas de verdad: el script sólo tapa el arranque y avisa al salir. |
| `GA_CREDITOS` | — | fuerza cuántos créditos insertar, por encima de lo que diga el fichero del monedero. |
| `GA_ARCHIVO` | `$HOME/.attract/creditos.txt` | ruta del fichero del monedero. |
| `GA_TARIFA` | `1c1c` | `1c1c` deja el DIP en 1 moneda/1 crédito para el futuro y compensa la tarifa vieja en esta partida; `auto` sólo compensa sin tocar el DIP; `off` ignora los DIP (1 moneda = 1 crédito siempre). |
| `GA_VIGILAR` | `1` | `0` para no llevar la cuenta del monedero ni del botón de moneda durante la partida. |
| `GA_AVISO` | `1` | `0` para no avisar al salir con créditos dentro. |
| `GA_AVISO_ESPERA` | `300` | frames (mínimo 30) que el cuadro de aviso espera respuesta antes de rendirse. |
| `GA_AVISO_GUARDA` | `15` | frames tras pintar el cuadro en los que un segundo flanco de la tecla de salir **no** cuenta como confirmación (antirrebote de esa tecla). |
| `GA_MENSAJE` | `150` | frames (mínimo 30) que dura el mensaje corto al meter una moneda («CREDITO PARA ESTE JUEGO...»). |
| `GA_SINCRONIZAR` | `1` | `0` para no escribir los créditos directamente en la RAM del juego (sólo aplica si hay dirección conocida, monedero y no es partida gratis). |
| `GA_TOPE` | `9` | máximo que se escribe en el contador al sincronizar por escritura. |
| `GA_TABLA` | `creditos.dat` (al lado del script) | ruta de la tabla de direcciones de RAM. |
| `GA_PULSO` | `8` | frames que se mantiene pulsada cada moneda simulada al insertar. |
| `GA_HUECO` | `8` | frames de separación entre monedas simuladas. |
| `GA_ESPERA` | `0` | frames extra de espera antes de empezar a insertar. |
| `GA_ARRANQUE` / **`segundos`** en `arranque.dat` | `300` frames (5 s) | frames MÍNIMOS (o EXACTOS, si `auto=0`) de arranque tapado. |
| `GA_ARRANQUE_MAX` / `max` | `1800` | tope del arranque tapado cuando `auto=1` y no se puede detectar el final. |
| `GA_ARRANQUE_SIN` / `sin` | `900` | frames de arranque tapado en juegos sin contador de créditos conocido (sólo aplica con `auto=1`). |
| `GA_ESTABLE` / `estable` | `120` | frames que el contador de creditos debe estar quieto para dar la placa por lista (con `auto=1`). |
| `GA_COMPROBAR` | `90` | frames de gracia para comprobar que una moneda cobrada llegó de verdad al contador del juego; si no, se devuelve. |
| `GA_ANTIRREBOTE` | `8` | frames que se ignoran tras el flanco de una moneda del jugador (antirrebote del botón de MAME). |
| `GA_VELOCIDAD` / `velocidad` | `0` (sin freno) | velocidad del emulador durante el arranque tapado, en % (100 normal, 200 el doble...). |
| `GA_NEGRO` / `negro` | `1` | `0` para acelerar el arranque sin tapar la pantalla (para ajustar a ojo). |
| `GA_INDICADOR` / `indicador` | `0` | `1` para pintar `>> CARGANDO AL N%` mientras se acelera. |
| `GA_AUTO` / `auto` | `0` | `1` para que el arranque se alargue hasta detectar que la placa está lista, en vez de durar exactamente `segundos`. |
| `GA_AJUSTES` | `arranque.dat` (al lado del script) | ruta del fichero de ajustes por juego. |
| `GA_TURBO` / `turbo` | `1` | `0` para no tocar velocidad/frameskip/mute durante el arranque tapado. |
| `GA_FRAMESKIP` / `frameskip` | `11` | frameskip aplicado durante el arranque tapado (la mitad del *fast forward* que no está expuesta directamente). |
| `GA_ASENTAR` | `180` | frames que se deja asentar la RAM antes de empezar a contar (sólo cuando `ARRANQUE<=0`; con arranque tapado el asentamiento lo cierra el propio fin del arranque). |
| `GA_LIMPIAR` | `1` | `0` para no quitar los créditos no pagados que la máquina traiga puestos al arrancar. |
| `GA_BARRIDO` / `barrido` | `0` (apagado) | segundos dentro del arranque tapado en los que adelantar la limpieza, para juegos que repintan el rótulo largo de créditos al verlos cambiar (p.ej. Root Beer Tapper). |
| `GA_COBRO` / — | `meter` | `meter`: el monedero se descuenta al meter la moneda (contador físico). `jugar`: se descuenta cuando el juego se lleva el crédito. |
| `GA_CERROJO` / `cerrojo` | `1` | `0` para no montar el cerrojo del botón de moneda. |
| `GA_LIMITE` / `limite` | `0` (aprendido solo) | créditos que admite la placa; al llegar, se cierra el botón (además del cerrojo por monedero/arranque). |
| `GA_CONTADOR` / `contador` | `1` | `0` para no pintar el marcador «CREDITOS N» en pantalla (necesita dirección conocida). |
| `GA_MONEDA` | `COIN1` | token de entrada a tratar como "la moneda". |
| `GA_VERBOSO` | — | `1` para el log de diagnóstico por `print()`. |
| `GA_NVRAM` / `nvram` | `1` | `0` para apagar el guardado de NVRAM de esta partida (juegos que arrancan con créditos de la sesión anterior sin dirección conocida). |
| `GA_GRABAR` / — | — | activa el **modo grabación de vídeo** (lo usa `videos.sh`): segundo del clip. |
| `GA_GRABAR_DURA` / `_MARGEN` / `_ARCHIVO` / `_SKIP` | `12` / `2` / — / `11` | parámetros del modo grabación de vídeo. |
| `GA_GRABAR_TECLA` / `_ARCHIVO` | — | activa el **modo grabar mi partida con una tecla**. |

### 1.4 Recorrido de la ejecución

El script es un único chunk que se ejecuta de arriba abajo. No hay una
función `main()`: cada sección de código de nivel superior hace su trabajo
y, en varios puntos, `return` corta la ejecución si no hay nada que hacer
(por ejemplo, si la máquina no tiene entrada de moneda).

**Paso 1 — helpers y lectura de configuración (líneas ~82-314).**
`num(nombre, defecto)` lee una variable de entorno y la convierte a entero,
tolerando que `nombre` sea `nil` (hace falta porque algunos ajustes sólo
existen en `arranque.dat` y se llaman con `var=nil`; sin esa guarda,
`os.getenv(nil)` reventaría el script entero). A partir de ahí se calculan
todas las constantes locales (`PULSO`, `HUECO`, `TARIFA`, `MONEDERO`,
`COBRO`, `SINCRONIZAR`, etc.) leyendo el entorno.

**Paso 2 — recuperación tras un reinicio de placa (líneas ~183-192).**
Antes de tocar nada más, si ya existe la global `GA_ESTADO` con
`deshaceres`, se ejecutan todas esas funciones de deshacer, en orden
inverso, envueltas en `pcall`. Esto es lo primero que se comprueba porque
algunos juegos (Elevator Action) **reinician la placa durante su propio
arranque**, y MAME vuelve a lanzar el `-autoboot_script` desde cero. Las
variables globales de Lua sobreviven a ese reinicio, así que si no se
deshace lo de la ejecución anterior *antes* de empezar la nueva, la segunda
ejecución tomaría nota de un estado ya alterado (velocidad ya restaurada,
botón de moneda ya sin secuencia) como si fuera el estado "de fábrica", y
lo dejaría así para siempre al terminar. Ver la sección 1.6 para el
mecanismo completo de `deshaceres`.

**Paso 3 — localizar y cargar los módulos vecinos (líneas ~194-224).**
`MI_DIR` se calcula con `debug.getinfo(1, 'S').source`, que da la ruta del
propio fichero tal y como MAME lo abrió (con un `@` delante); un patrón
`'^@(.*[/\\])'` se queda con el directorio. `vecino(nombre)` hace
`pcall(dofile, MI_DIR .. nombre)` y, si falla o no devuelve una tabla,
lo registra en el log y devuelve `nil` — así un módulo roto o ausente no
tumba el script entero, sólo desactiva esa funcionalidad. Se cargan así
`tarifa.lua`, `monedero.lua`, `aviso.lua`, `memoria.lua`, `cerrojo.lua` y
`ajustes.lua`.

**Paso 4 — leer `arranque.dat` y resolver los ajustes de este juego
(líneas ~213-314).** `AJU.leer(...)` parsea el fichero completo;
`AJU.para(tabla, emu.romname(), os.getenv)` construye un "consultor" con la
precedencia ya resuelta para el juego concreto que está arrancando. A partir
de ahí, `ajuste(clave, var, defecto)` y `ajuste_frames(...)` son los dos
únicos puntos por los que se leen todos los parámetros de arranque
(velocidad, segundos, negro, indicador, contador, límite, auto, barrido,
frameskip, nvram, turbo).

**Paso 5 — la cuenta de lo que hay que insertar (líneas ~316-359).** Si
`GA_MONEDERO=1`, se lee el fichero del monedero con `MON.leer(BUZON)` y se
obtienen `SALDO` e `INSERTA`. Si `GA_CREDITOS` está puesto, manda sobre el
fichero. **La orden de insertar se consume en cuanto se lee**: si
`INSERTA > 0`, se vuelve a escribir el fichero con `inserta=0` inmediatamente
(`MON.escribir(BUZON, SALDO, 0)`), para que un segundo arranque del mismo
juego no repita el regalo. Finalmente, en modo `COBRO == 'meter'` (el modo
activo por defecto) y sin `GA_CREDITOS` explícito, `INSERTA` se fuerza a 0:
el jugador entra a la máquina sin nada y mete sus propios créditos con el
botón.

**Paso 6 — encontrar el campo de entrada de la moneda (líneas ~361-394).**
`buscar_moneda()` traduce el token (`COIN1` por defecto) a un tipo de
entrada con `ioport:token_to_input_type(TOKEN)` y recorre **todos** los
puertos y **todos** los campos comparando por `campo.type` (nunca por
nombre, porque `port.fields` se indexa por el nombre ya traducido al idioma
de la interfaz). Si no se encuentra — es lo normal en un ordenador o una
consola sin ranura de monedas —, se registra en el log y el script hace
`return`: **no hay nada más que hacer** en esa máquina.

**Paso 7 — resolver la tarifa vigente (líneas ~396-478).**
`tarifa_vigente()` busca el DIP con `T.buscar_dip()`; si `GA_TARIFA=off` o no
hay módulo `tarifa.lua`, se salta y vale 1 moneda = 1 crédito. Si
`GA_TARIFA=1c1c` (el defecto), se llama a `fijar_1c1c(dip, gratis)`, que dejará
el DIP en 1C/1C para los *próximos* arranques (MAME lo guarda en su `.cfg`,
pero **no** afecta a la partida en curso: la placa ya leyó la tarifa vieja al
arrancar). Con la tarifa ya conocida, se calcula `MONEDAS_POR`,
`CREDITOS_POR` y `GRATIS`, y de ahí `MONEDAS` — cuántas monedas simuladas
hacen falta para los créditos pedidos, redondeando siempre hacia arriba
(`math.ceil`), porque regalar un crédito de más es preferible a comerse uno.

**Paso 8 — construir `GA_ESTADO` (líneas ~480-519).** Aquí se crea la tabla
de estado **global** (no local) con todos los campos que va a usar el resto
del script durante toda la partida. Es la pieza central de todo el diseño;
ver la sección 1.6 para el motivo de que sea global.

**Paso 9 — definir las funciones de estado y el modo grabación
(líneas ~521-793).** Se definen (pero todavía no se llaman en bucle)
`insertar(e)`, `ya_arranco(e)`, el bloque `GRABAR`/`paso_grabacion()`, y el
bloque `TECLA`/`paso_tecla()`/`tecla_para()`. Ver secciones 1.7 y 1.8.

**Paso 10 — definir `por_frame()` (líneas ~794-1068).** La función que hace
todo el trabajo periódico. Ver la sección 1.9, la más larga de todas.

**Paso 11 — montar el vigilante del botón de moneda y el cerrojo
(líneas ~1071-1180).** Si `VIGILAR` y hay módulo `monedero.lua`, se obtiene
la secuencia física del botón (copiada con `emu.input_seq(...)`, nunca por
referencia) y se crea `GA_ESTADO.pulso_moneda` con `MON.pulsador(...)`. Si
`CERROJO` está activo, se crea `GA_ESTADO.cerrojo` con `CER.nuevo{...}`,
pasándole las funciones `bloquear`/`soltar` que de verdad tocan MAME
(`CAMPO:set_default_input_seq(...)`). Si hay monedero, se crea también
`GA_ESTADO.cuenta` con `MON.cuenta{...}`.

**Paso 12 — montar los contadores de START (líneas ~1182-1203).** Se
obtienen lectores crudos de `UI_CANCEL`, `START1` y `START2` con
`ioport:type_pressed(tipo)`, y pulsadores con antirrebote para los dos
STARTs (para la estimación cuando no hay dirección de RAM conocida).

**Paso 13 — montar la lectura de la RAM del juego, si se conoce
(líneas ~1205-1369).** Busca el juego en `creditos.dat` con
`MEM.entrada(...)`; si existe, resuelve el espacio de memoria (CPU normal, o
un *share* si `creditos.dat` lo marca así), monta las funciones de
traducción BCD si hace falta, construye `leer_ram`/`escribir_ram`, la
función de limpieza (`limpiar`), el contador `MEM.contador{...}` y, si
procede, el sincronizador por escritura `MEM.sincronizador{...}`. Ver
sección 1.10.

**Paso 14 — apagar la NVRAM si el ajuste lo pide (líneas ~1371-1383).**

**Paso 15 — montar el arranque tapado (líneas ~1385-1470).** Si
`ARRANQUE > 0`, se marca `GA_ESTADO.arranque = true`, se cierra el cerrojo
(`listo = false`) y, si `TURBO`, se guarda el estado actual de velocidad y
sonido y se aceleran, apuntando la función de deshacer en
`GA_ESTADO.deshaceres`.

**Paso 16 — montar el cuadro de aviso (líneas ~1497-1518).**

**Paso 17 — montar el pintor (líneas ~1520-1652).** `GA_ESTADO.pintor` es la
función que dibuja todo lo que se superpone al juego, y se registra **una
sola vez** con `emu.register_frame_done`, protegida por la global
`GA_PINTOR_PUESTO` (ver sección 1.6, tercer motivo del `GA_ESTADO` global).

**Paso 18 — atajo de salida y suscripción final (líneas ~1654-1680).** Si no
hay absolutamente nada que hacer (ni monedas que insertar, ni cuenta, ni
aviso, ni memoria, ni grabación), el script se sale sin suscribirse al
notificador de frame. Si hay algo, `GA_ESTADO.sub =
emu.add_machine_frame_notifier(por_frame)` engancha el bucle principal, y se
apunta cómo cancelar esa suscripción en `deshaceres`.

### 1.5 Funciones — detalle

- **`num(nombre, defecto)`** — lee `os.getenv(nombre)`, lo convierte con
  `tonumber` y lo trunca con `math.floor`; si `nombre` es `nil` o el valor no
  es numérico, devuelve `defecto`.

- **`log(fmt, ...)`** — sólo imprime si `VERBOSO`. Envuelve
  `string.format` en un `pcall`: si los argumentos no casan con el formato
  (un `%d` con un `nil`, por ejemplo), en vez de reventar imprime el
  mensaje sin formatear más una nota de error. Es deliberado porque este log
  se llama desde dentro del callback de frame, que es donde vive, entre
  otras cosas, la devolución de monedas — un `error()` ahí se llevaría por
  delante el resto del frame.

- **`vecino(nombre)`** — `dofile` protegido con `pcall` sobre un módulo
  situado en `MI_DIR`. Devuelve la tabla del módulo o `nil`.

- **`fijar_1c1c(dip, gratis)`** — si el juego está en modo gratis, no toca
  nada (log y sale). Si no, pide a `T.valor_1c1c(dip)` el valor de 1C/1C; si
  no existe esa opción, o si el DIP ya está en ese valor, no hace nada.
  Si hace falta cambiarlo, escribe `dip.campo.user_value = valor` — MAME lo
  persistirá en el `.cfg` del juego al salir, pero **esta partida sigue
  usando la tarifa que la placa ya leyó al arrancar**.

- **`tarifa_vigente()`** — devuelve `monedas_por_tanda, creditos_por_tanda,
  es_gratis`. Encapsula toda la lógica de leer el DIP, decidir si fijarlo a
  1C/1C, detectar partida gratis, y avisar si la tarifa tiene premio
  (`T.con_premio`).

- **`insertar(e)`** — máquina de estados que simula la inserción física de
  monedas. Recibe la tabla de estado `e` (siempre `GA_ESTADO`) y avanza un
  paso por llamada:
  - `'espera'`: cuenta `ESPERA` frames antes de empezar (para casos donde
    hace falta un margen extra).
  - `'pulso'`: mantiene `campo:set_value(1)` durante `PULSO` frames; al
    llegar, suelta con `set_value(0)`, decrementa `restantes` y pasa a
    `'hueco'`.
  - `'hueco'`: mantiene `set_value(0)` durante `HUECO` frames; si quedan
    monedas por meter vuelve a `'pulso'`, si no pasa a `'fin'` (soltando la
    moneda una vez más, "por si acaso" — comentario del propio código:
    *"garantiza soltar la moneda"*).

- **`ya_arranco(e)`** — decide si el arranque tapado ha terminado. Primero
  exige que hayan pasado al menos `ARRANQUE` frames. Si `FIJO` (o sea,
  `auto=0`, el modo por defecto), a partir de ahí ya vale `true`: la
  duración es exacta, decidida por el usuario. Con `auto=1`: si se llegó al
  tope `ARRANQUE_MAX`, se fuerza `true`. Si no hay `leer_ram` (juego sin
  dirección conocida), se espera hasta `ARRANQUE_SIN`. Si hay `leer_ram`, se
  usan dos reglas sobre `e.estable` (frames que el contador lleva sin
  cambiar) y `e.ultimo_ram` (su último valor visto): si está a cero y
  estable durante `ESTABLE` frames, listo; si lleva estable el triple de
  `ESTABLE` frames en *cualquier* valor (para juegos con NVRAM que nunca
  pasan por cero), también listo.

- **`paso_grabacion()`** — sólo existe si `GA_GRABAR` está en el entorno.
  Máquina de tres fases (`acelera` → `estabiliza` → `graba`) que usa
  `emu.time()` (segundos *emulados*, no frames, porque distintas placas
  corren a distinta frecuencia) para decidir cuándo cambiar de frase.
  En `'acelera'` pone `video.frameskip` al máximo (`GA_GRABAR_SKIP`, 11 por
  defecto) — solamente el *render* se salta, la emulación sigue avanzando a
  la misma velocidad interna —, hasta 2 s (`margen`) antes del punto pedido.
  En `'estabiliza'` pone `frameskip=0` para que el render se ponga al día
  antes de empezar a grabar, y al llegar al segundo exacto llama a
  `video:begin_recording(archivo, 'avi')`. En `'graba'`, al llegar a
  `inicio + dura`, llama a `video:end_recording()` y `machine:exit()`. Todo
  envuelto en `pcall` porque `begin_recording`/`end_recording` pueden fallar
  si la ruta no es escribible.

- **`tecla_para()`** / **`paso_tecla()`** — el modo "grabar mi partida con
  una tecla" (`GA_GRABAR_TECLA`). `paso_tecla()` resuelve el token de la
  tecla la primera vez con `input:code_from_token(...)`, y se protege contra
  un token mal escrito comprobando la vuelta con `code_to_token(...)`: si el
  código resuelto vuelve a traducirse como `'INVALID'`, se avisa y se
  desactiva el modo entero (`TECLA = nil`), porque `code_from_token` **no
  falla** con un texto sin sentido — devuelve silenciosamente un código que
  nunca se pulsa, y sin esta comprobación el fallo sería mudo: se juega media
  hora sin que se grabe nada. Cada llamada lee `input:code_pressed(codigo)` y
  detecta sólo el **flanco** de bajada→alta (comparando con `g.antes`, que
  arranca en `true` para que tener la tecla pulsada al lanzar el juego no
  cuente como un flanco). En el flanco: si ya estaba grabando, para
  (`tecla_para()`) y muestra "guardada" 3 s; si no, empieza una toma nueva
  numerada (`toma-N.avi`) con `video:begin_recording(...)`.

- **`por_frame()`** — ver sección 1.9.

- **`fin_del_arranque()`** — se llama una sola vez, cuando `ya_arranco()`
  devuelve `true`. Cierra el asentamiento del contador de memoria llamando
  a `e.memoria.asentar_ya()` (que es lo que dispara la limpieza de créditos
  no pagados en el momento justo, no a un número fijo de frames), restaura
  velocidad/frameskip/sonido guardados en `e.turbo`, y abre el cerrojo
  (`e.cerrojo.listo = true`).

- **`rotulo_derecha(contenedor, texto, color)`** — dibuja una caja con
  fondo y un texto pegado a la esquina superior derecha del contenedor de
  interfaz. Mide el ancho real del texto con
  `manager.ui:get_string_width(texto)` (con una caja fija de reserva si esa
  llamada fallara), para que el recuadro no sea más ancho de lo necesario.
  La usan el indicador de carga acelerada, el contador de créditos y el
  indicador de grabación.

### 1.6 Por qué `GA_ESTADO` (y otras dos globales) son globales a propósito

El propio código lo dice sin rodeos en el comentario de cabecera de la
sección 4: *"si estas variables fueran locales del chunk, el recolector de
basura podría llevarse la suscripción al notificador y los callbacks
dejarían de dispararse"*.

La explicación técnica: `emu.add_machine_frame_notifier(por_frame)` guarda
una referencia a la función `por_frame`, pero **no** necesariamente a nada
que esa función capture por *upvalue* de forma que Lua lo considere
alcanzable de manera obvia para el recolector si el chunk termina de
ejecutarse (el `-autoboot_script` corre una vez y termina; a partir de ahí
sólo sobreviven objetos alcanzables desde raíces globales o desde
estructuras que MAME retiene). Guardar el estado mutable en una tabla
**global** (`GA_ESTADO`, sin `local`) garantiza que es alcanzable desde la
tabla global de Lua durante toda la vida del proceso, sin depender de los
detalles internos de qué retiene qué el notificador.

Hay tres globales de este tipo en el fichero, cada una con su propio motivo:

- **`GA_ESTADO`** — todo el estado mutable de la partida en curso: fase de
  inserción, contador de memoria, cerrojo, cuenta, aviso, mensajes en
  pantalla... Global porque tiene que sobrevivir mientras dure la partida.
- **`GA_PINTOR_PUESTO`** — un booleano que evita registrar el callback de
  pintado más de una vez. Es necesario porque
  `emu.register_frame_done` **acumula** callbacks y no hay forma de
  quitarlos (`luaengine.cpp`, `register_function`, hace `add` en vez de
  `create_named`). El truco es registrar **un solo envoltorio, para
  siempre**, que en cada frame mira la `GA_ESTADO` *vigente* y llama a
  `GA_ESTADO.pintor()` — así, si la placa se reinicia y el script se
  relanza, el pintor sigue siendo el mismo objeto de MAME pero pinta según
  el estado nuevo.
- **Consecuencia directa: el mecanismo de `deshaceres`.** Como las
  globales de Lua sobreviven a un reinicio de la placa (comprobado con un
  contador, según el comentario del código), un juego como Elevator Action
  —que reinicia su propia placa durante el arranque— hace que MAME **relance
  el `-autoboot_script` entero** sin que el proceso de MAME termine. La
  segunda ejecución se encuentra `GA_ESTADO` todavía viva, con velocidad ya
  acelerada y el botón de moneda ya sin secuencia (porque la primera
  ejecución los dejó así a mitad de su propio arranque). Si la segunda
  ejecución tomara ese estado como "el original" para restaurarlo al final,
  el resultado sería el emulador para siempre sin freno y el botón de
  moneda para siempre muerto. La solución, al principio del fichero
  (paso 2 de la sección 1.4), es ejecutar **antes de nada** todas las
  funciones guardadas en `GA_ESTADO.deshaceres` (en orden inverso al que se
  añadieron) y vaciar la lista, de modo que la ejecución nueva parta de un
  estado limpio antes de anotar nada como "estado original".

  Detalle importante sobre cómo se construyen esas funciones de deshacer: se
  capturan **copias locales** de los valores a restaurar (por ejemplo, en el
  bloque del arranque tapado: `local t = GA_ESTADO.turbo` antes de definir
  la función), nunca una referencia a `GA_ESTADO` directamente. Es
  imprescindible, porque cuando la función de deshacer se ejecute (al
  principio de la *siguiente* ejecución), la global `GA_ESTADO` ya habrá
  sido reemplazada por la tabla de la ejecución nueva; si la función leyera
  `GA_ESTADO.turbo` en el momento de ejecutarse, en vez de en el momento de
  crearse, restauraría el estado equivocado.

  También hay que cancelar explícitamente la suscripción vieja al
  notificador de frame (`sub:unsubscribe()`), porque si no, el notificador
  de la ejecución anterior seguiría vivo y llamaría a `por_frame` **dos
  veces por frame**, ambas leyendo la `GA_ESTADO` nueva — no revienta, pero
  duplica todo el conteo.

### 1.7 El modo grabación de vídeo (`GA_GRABAR`)

Documentado en la sección 1.5 (`paso_grabacion`). Vive por completo dentro
de `por_frame()`, en una rama que sólo se activa si la variable de entorno
`GA_GRABAR` está puesta y es numérica. En la cabina y en las 344 pruebas de
`correr.sh`, esa variable no existe nunca, así que este código no se ejecuta
jamás en el uso normal — es exclusivo de `videos.sh`. La ventaja frente a
grabar desde el frame 0 con `-aviwrite`: el AVI final ya *es* el clip,
porque el frameskip acelera silenciosamente toda la carga y el arranque
sin escribir un solo fotograma de más al disco.

### 1.8 El modo "grabar mi partida con una tecla" (`GA_GRABAR_TECLA`)

Distinto del anterior: aquí no se acelera nada, no se tapa nada y el
emulador no sale solo. Es el jugador quien decide, pulsando una tecla
(`KEYCODE_PAUSE` por defecto), cuándo empieza y cuándo termina cada toma.
Usa la misma pareja de llamadas de MAME
(`begin_recording`/`end_recording`), y el AVI resultante lleva el sonido
dentro porque el gestor de sonido de MAME alimenta la grabación por su
cuenta.

Se registra un `emu.add_machine_stop_notifier` para cerrar limpiamente una
toma que quedara abierta si MAME termina a mitad de partida, y esa
suscripción también se apunta en `GA_ESTADO.deshaceres` por el mismo motivo
de siempre: si la placa se reinicia, sin cancelarla el notificador viejo se
sumaría al nuevo.

### 1.9 `por_frame()` paso a paso

Esta es la función que MAME llama una vez por fotograma emulado (vía
`emu.add_machine_frame_notifier`). Se ejecuta siempre en el mismo orden:

1. **Modos de grabación.** Si `GRABAR` existe, `paso_grabacion()`. Si
   `TECLA` existe, `paso_tecla()`. Estos dos no dependen de nada de lo que
   viene después y pueden coexistir con el resto (aunque en la práctica
   `GA_GRABAR` y `GA_GRABAR_TECLA` son mutuamente excluyentes por diseño:
   `TECLA` sólo se crea `if t and t ~= '' and not GRABAR`).

2. **Arranque tapado.** Si `e.arranque`, se incrementa
   `e.arranque_frames`. Si `barrido=N` está activo y todavía no se ha
   adelantado la limpieza, y ya se llegó a ese frame y se puede leer la RAM,
   se llama a `e.limpiar(valor)` ya mismo (en vez de esperar al final del
   asentamiento) — esto es lo que arregla el rótulo corrompido de Root Beer
   Tapper (ver comentario extenso al principio del fichero, sección
   `BARRIDO_PRONTO`). Si hay `leer_ram`, se lee el byte y se actualiza
   `e.estable`/`e.ultimo_ram` (cuántos frames lleva el contador quieto en el
   mismo valor). Si `ya_arranco(e)` es `true`, se llama a
   `fin_del_arranque()`.

3. **Comprobación de monedas pendientes (`e.pendiente`).** Cuando se cobra
   una moneda (más abajo, en el paso 5) se apunta en `e.pendiente` el valor
   del contador *antes* de cobrarla y cuántos créditos debería haber
   producido. Aquí, cada frame mientras haya una pendiente, se lee la RAM y
   se guarda el **máximo** visto (`p.visto`) — no el último —, porque si el
   jugador pulsa START mientras el plazo de gracia corre, el contador baja y
   un simple "último valor" haría creer que la moneda nunca llegó. Si
   `p.visto - p.antes >= p.creditos`, la moneda llegó de verdad y se limpia
   `e.pendiente`. Si no, se cuenta atrás `p.plazo`; al agotarse
   (`GA_COMPROBAR` frames después de cobrarla), se calcula cuántos créditos
   *no* llegaron. Caso especial: si no llegó ninguno y el contador no se
   movió en absoluto, y todavía no hay un `e.tope` aprendido, se asume que la
   placa está llena y se aprende `e.tope = p.antes` (con un mensaje que
   sugiere fijar `limite=N` en `arranque.dat` para no perder ni siquiera esa
   moneda la próxima vez). Si algo se perdió de verdad, se devuelve: al
   `e.cuenta` (sólo en modo `meter`, porque en modo `jugar` nunca se llegó a
   cobrar), al `e.aviso` (para que no cuente ese crédito como dentro de la
   máquina), y a `e.cerrojo.metidas`/`e.metidos` (para no dejar el contador
   de monedas del jugador artificialmente alto). Se pinta un mensaje
   («LA MAQUINA NO LA COGIO. CREDITO DEVUELTO»). Si la lectura de la RAM
   falla, **no se devuelve nada**: el error seguro es quedarse cobrado de
   más, nunca regalar.

4. **Inserción automática.** Si `e.fase` no es `'fin'` ni `'inactivo'`, se
   llama a `insertar(e)` (la máquina de estados de la sección 1.5).

5. **El botón de moneda del jugador.** Se comprueba
   `e.pulso_moneda.frame()`. Ojo: este detector lee siempre la **secuencia
   original** guardada al arrancar, así que dispara **también con el
   cerrojo echado** — es la única forma de poder explicarle al jugador por
   qué la moneda no hace nada. Si hay cerrojo y `e.cerrojo.moneda()`
   devuelve `false` (rechazada), se elige un mensaje según
   `e.cerrojo.motivo()` (`'arrancando'`, `'lleno'`, o el genérico "sin
   créditos"). Si se acepta:
   - Se avisa al aviso (`e.aviso.entra(CREDITOS_POR)`) y se suma a
     `e.metidos`.
   - Si hay una dirección **importada sin comprobar** (`e.a_prueba`) y
     todavía no tiene reloj puesto, se apunta el valor actual como
     referencia y se arma un contador de `GA_COMPROBAR` frames — ésta es la
     moneda con la que se prueba si la dirección importada es de verdad el
     contador de créditos (ver sección 1.10 y el propio comentario del
     código: con monedas de verdad no se inserta nada al lanzar, así que
     antes de este arreglo la comprobación siempre se hacía en el frame 1,
     comparando el valor consigo mismo, y descartaba **toda** dirección
     importada de forma automática).
   - Si `GA_COMPROBAR > 0` y hay lectura de memoria ya asentada, se registra
     (o se amplía, si ya había una) la entrada en `e.pendiente` descrita en
     el punto 3.
   - En modo `meter`, la moneda se cobra **aquí mismo**:
     `e.cuenta.consume(CREDITOS_POR)`.
   - Se prepara el mensaje corto en pantalla con el saldo actual del
     monedero.

6. **El cerrojo se actualiza `e.cerrojo.frame()`** — deliberadamente
   **después** de haber contado la moneda del punto 5, para que la última
   moneda que le quedaba al jugador entre y el cierre del cerrojo empiece
   justo en ese mismo frame (ni un frame antes, que la rechazaría sin
   necesidad; ni un frame después, que dejaría colarse una moneda de más).

7. **Los pulsadores de START1/START2** se leen aquí
   (`e.pulso_start1.frame()`, `e.pulso_start2.frame()`), y su resultado se
   guarda en `s1`/`s2` para usarlo más abajo.

8. **El sincronizador por escritura, si está activo (`e.sincro`).** Se
   llama a `e.sincro.frame()`. Mientras dure (`'pendiente'`), no se cuenta
   nada más ese frame: los cambios que produce la propia escritura no son
   del jugador. Si termina en `'rendido'` (no se pudo forzar el valor tras
   varios intentos) y todavía había monedas por meter (`e.restantes == 0`
   pero `MONEDAS > 0`, es decir: se había decidido no insertar monedas
   porque se iba a sincronizar), se vuelve al método clásico de simular
   monedas (`e.restantes = MONEDAS`, `e.fase = 'pulso'`/`'espera'`).

9. **Si no hay sincronizador, la dirección importada a prueba
   (`e.a_prueba`).** Se decide si "toca" comprobar: si se insertaron monedas
   automáticas, cuando `e.fase == 'fin'`; si fue una moneda del jugador, se
   cuenta atrás el reloj armado en el punto 5. Cuando toca, se compara el
   valor actual con el que había antes de la moneda: si subió, la dirección
   se acepta (`e.memoria.anterior = ahora`, el contador ya no volverá a
   pasar por esta rama porque `e.a_prueba` se pone a `nil`); si no subió, se
   descarta del todo (`e.memoria = nil`), y de aquí en adelante el juego
   vuelve a estimar por pulsaciones de START.

10. **Si hay memoria confirmada (`e.memoria`), se avanza su contador**
    (`e.memoria.frame()`), y si `consumido` ha subido desde la última vez
    que se miró (`e.consumido_visto`), la diferencia se cobra al monedero
    **sólo en modo `jugar`** (en modo `meter` ya se cobró al meter la moneda,
    y cobrar otra vez al gastarla sería cobrar dos veces).

11. **Si no hay memoria (ni confirmada ni a prueba) y hubo un START**, se
    estima: un crédito por `START1`, dos por `START2`, y se cobra al
    monedero (sólo en modo `jugar`) y al aviso.

12. **El mensaje corto en pantalla** cuenta atrás `e.mensaje_reloj` y se
    borra al llegar a cero.

13. **El cuadro de aviso.** `e.aviso.frame(e.leer_salir(), s1 or s2)`
    devuelve `nil`, `'bloquear'` o `'salir'`. Con `'bloquear'`, se llama a
    `manager.machine.uiinput:reset()` — el mecanismo exacto que "se come" la
    pulsación de la tecla de salir sin tocar ningún mapeo (ver sección 1.11
    y el comentario largo en el propio código, líneas 1055-1061). Con
    `'salir'`, se llama a `manager.machine:exit()`.

### 1.10 La lectura/escritura de la RAM del juego (sección "MEM")

Este bloque (paso 13 de la sección 1.4) es el puente entre `creditos.lua` y
`memoria.lua`. Busca el juego actual (`emu.romname()`) en `creditos.dat` con
`MEM.entrada(tabla, juego)`. La entrada especifica CPU, "espacio" y una o
varias direcciones.

**Resolución de shares.** El "espacio" en `creditos.dat` puede ser un
espacio normal de una CPU (`program`, `data`...) o un *share* de memoria,
escrito `<nombre>/share` — el mismo convenio que usa `hiscore.dat` de MAME y
que replica también `volcar.lua`. Se detecta partiendo la cadena con un
patrón `([^/]*)/?([^/]*)`, y si la segunda parte es `'share'`, se resuelve
con `manager.machine.memory.shares[nombre]` en vez de
`manager.machine.devices[cpu].spaces[espacio]`. Esto hace falta, por
ejemplo, para Missile Command: toda su memoria está detrás de un
*trampolín* (sin ningún tramo declarado `'ram'` en el mapa), y leer por el
espacio de la CPU dispara un efecto secundario (`load_madsel()`) que puede
corromper su vídeo, porque esa placa comparte memoria entre variables y
bitmap.

**BCD.** Si `entrada.bcd` es verdad, se instalan dos funciones de
traducción: `a_credito(b)` convierte un byte BCD (dos nibbles, cada uno
0-9) a su valor decimal (`alto*10 + bajo`), devolviendo el byte crudo sin
tocar si algún nibble pasa de 9 (señal de que la RAM aún no está
inicializada o la dirección no es la buena). `a_byte(n)` hace el camino
inverso al escribir, recortando a 0-99. **Es el único sitio del sistema**
por el que pasan todas las lecturas y escrituras de esa dirección — el
marcador en pantalla, el cuadro de aviso, el barrido y el sincronizador ven
siempre créditos, nunca bytes crudos.

**`GA_ESTADO.leer_ram`** queda como una función que envuelve
`esp:read_u8(entrada.dir)` con la traducción BCD si aplica.
**`GA_ESTADO.escribir_ram`** escribe en **todas** las copias
(`entrada.dirs`), no sólo en la primera: hay juegos (Q\*bert) que mantienen
varias copias del mismo contador y pintan desde una que no es la primera.

**La limpieza (`limpiar`).** Sólo se construye si `LIMPIAR` está activo y la
dirección está **comprobada** (nunca en una importada sin verificar: en esas
nunca se escribe, bajo ningún concepto). La función resta lo que el jugador
ya haya pagado en esta partida (`GA_ESTADO.metidos`) de lo que la máquina
trae puesto, y sólo escribe si sobra algo: *"lo que el jugador haya metido
mientras la placa se asentaba es suyo, ya se lo hemos cobrado: sólo se
quita lo que sobra por encima de eso"*.

**El contador (`MEM.contador`).** Se construye con
`asentar = (ARRANQUE > 0) and (ARRANQUE_MAX + ESTABLE + 120) or ASENTAR`.
Es decir: con arranque tapado activo, el asentamiento por *tiempo* se pone
deliberadamente **por detrás** del tope máximo del propio arranque tapado
— nunca se dispara solo, por delante, porque quien de verdad decide cuándo
asentar es `fin_del_arranque()` llamando a `asentar_ya()`. Sin esto, el
contador de frames del asentamiento podría dispararse a mitad del arranque
tapado y contaminar la detección de "la placa está lista" con su propia
escritura de limpieza.

**Dirección sin comprobar (`a_prueba`).** Si `entrada.comprobada` es falso
(viene de la colección de cheats), se arma `GA_ESTADO.a_prueba = { antes =
valor_actual, dir = entrada.dir }`, y **no** se usa la memoria como fuente
de verdad hasta que una moneda demuestre que ese byte sube (paso 9 de
`por_frame`, sección 1.9).

**El sincronizador por escritura.** Sólo se activa si `SINCRONIZAR`, la
partida no es gratis, la dirección está comprobada y hay monedero
(`HAY_MONEDERO`). Calcula cuánto escribir (`SALDO + INSERTA`, recortado a
`TOPE`) y construye `MEM.sincronizador{...}`; en ese caso se anula la
inserción de monedas simuladas (`GA_ESTADO.restantes = 0`,
`GA_ESTADO.fase = 'fin'`), porque el contador se pone a mano en vez de
simular pulsaciones.

### 1.11 Frenar la salida sin tocar mapeos

Esta pieza (paso 13 de `por_frame`, y el bloque de pintura) merece
explicarse aparte porque el mecanismo no es obvio. `creditos.lua` **no
puede** simplemente ignorar la pulsación de salir: eso dejaría que MAME
saliera de todas formas un frame después, cuando su propio código de UI
procesa la tecla. La solución encadena tres piezas de la API de MAME:

1. `manager.machine.ioport:type_pressed(tipo)` — lee la tecla **física**,
   en el momento en que corre el notificador de frame (justo después de
   `input_update()` dentro del propio MAME). Esto es lo que usa
   `GA_ESTADO.leer_salir()` para `UI_CANCEL`.
2. `manager.machine.uiinput:reset()` — pone **todos** los eventos de
   interfaz al estado `SEQ_PRESSED_RESET`.
3. El propio `check_ui_inputs()` de MAME corre **después** que el
   notificador de `creditos.lua`, dentro del render, y su guarda interna
   (*"si ya está en `SEQ_PRESSED_RESET`, no lo vuelve a poner a `true`
   mientras la tecla siga pulsada"*) hace que la pulsación **no llegue** a
   disparar la salida real de MAME ese frame.

Es decir: `creditos.lua` "se come" el evento de UI justo antes de que MAME
llegue a mirarlo, llamando a `reset()` cada frame que el cuadro de aviso
quiere seguir bloqueando la salida. En cuanto se deja de llamar a
`reset()` (porque el aviso decide `'salir'`, o porque no hay nada que
avisar), la tecla vuelve a funcionar exactamente igual que siempre — no
queda ningún rastro persistente, a diferencia de `set_input_seq`, que sí
escribe en el `.cfg` del juego.

### 1.12 Flujo de datos entre módulos (resumen)

```
                 (fichero .txt, sólo si GA_MONEDERO=1)
frontend  <───────────────────────────────────────────────  monedero.lua
                                                                  ▲  │
                                                          M.leer  │  │ M.escribir
                                                                  │  ▼
                                                            creditos.lua
                                                            │   │    │
                                        tarifa.lua  <───────┘   │    └──────► cerrojo.lua
                    (DIP, monedas↔créditos)                     │            (bloquear/soltar
                                                                 │             el botón físico)
                                                                 ▼
                                                          memoria.lua
                                                    (byte de RAM ↔ créditos,
                                                     BCD, sincronización)
                                                                 │
                                                                 ▼
                                                           aviso.lua
                                                    (dentro(), consume(),
                                                     frame() -> bloquear/salir)
```

`creditos.lua` es el único que decide **cuándo** llamar a cada función de
los demás módulos y con qué datos; ninguno de `monedero.lua`, `aviso.lua`,
`memoria.lua` o `cerrojo.lua` conoce la existencia de los otros ni de MAME.

### 1.13 API de MAME usada en `creditos.lua`

- `os.getenv`, `os.rename`/`io.*` (heredado de Lua estándar, disponible
  porque el autoboot corre con la librería completa).
- `emu.romname()` — nombre del set en marcha.
- `emu.time()` — segundos *emulados* transcurridos (usado en el modo
  grabación).
- `emu.input_seq(seq_o_nada)` — crea una copia independiente de una
  secuencia de entrada (o una secuencia vacía si se llama sin argumentos).
- `emu.add_machine_frame_notifier(fn)` — registra `fn` para que se llame
  una vez por fotograma emulado; devuelve un objeto con `:unsubscribe()`.
- `emu.add_machine_stop_notifier(fn)` — se llama cuando la máquina se
  detiene (usado para cerrar limpiamente una grabación abierta).
- `emu.register_frame_done(fn)` — registra `fn` para pintar, después de que
  el frame se ha renderizado; **acumula** callbacks sin forma de quitarlos.
- `manager.machine.ioport:token_to_input_type(token)` — traduce un token de
  texto (`'COIN1'`, `'START1'`...) al tipo interno; devuelve *tupla*
  `(tipo, jugador)`.
- `manager.machine.ioport.ports` — tabla de todos los puertos, indexada por
  etiqueta.
- `port.fields` — tabla de campos del puerto, indexada por **nombre
  traducido**.
- `campo.type` / `campo.type_class` — comparar por tipo, nunca por nombre.
- `campo:set_value(1|0)` — fuerza el valor digital del campo (es un OR con
  el estado físico real, ver más abajo).
- `campo:input_seq('standard')` — secuencia efectiva actual del campo,
  con `.length`.
- `campo:default_input_seq('standard')` — la secuencia *por defecto* (no la
  que esté activa ahora).
- `campo:set_default_input_seq('standard', seq)` — cambia la secuencia por
  defecto **sin** tocar el `.cfg` del juego.
- `campo.settings` — tabla `valor -> texto` de un DIP switch.
- `campo.user_value` — valor actual del DIP; se lee y se escribe, y MAME lo
  guarda en su `.cfg`.
- `manager.machine.input:seq_pressed(seq)` — lee si una secuencia de
  entrada está pulsada, a nivel físico.
- `manager.machine.ioport:type_pressed(tipo)` — lee la tecla física
  asociada a un tipo de entrada de interfaz (`UI_CANCEL`, `START1`...).
- `manager.machine.uiinput:reset()` — pone los eventos de interfaz a
  `SEQ_PRESSED_RESET`, "comiéndose" la pulsación de ese frame para el
  código de UI de MAME.
- `manager.machine:exit()` — pide a MAME que termine la máquina en marcha.
- `manager.machine.video.throttled` / `.throttle_rate` / `.frameskip` — se
  leen y se escriben para acelerar/desacelerar el emulador.
- `manager.machine.sound.system_mute` — se lee y se escribe para silenciar
  durante el arranque acelerado.
- `manager.machine.render.ui_container` — el contenedor de dibujo de la
  interfaz (coordenadas 0..1, no rota con la orientación del juego).
- `contenedor:draw_box(x0, y0, x1, y1, color_borde, color_relleno)` /
  `contenedor:draw_text(x, y | 'center', texto, color)`.
- `manager.ui:get_string_width(texto)` / `manager.ui.line_height` — medir un
  texto en las mismas coordenadas 0..1 del contenedor de interfaz.
- `manager.machine.options.entries['nvram_save']:value(false)` — apaga el
  guardado de NVRAM al salir, para esta partida.
- `manager.machine.devices[tag]` / `.spaces[espacio]` — acceso a un
  espacio de direcciones de un procesador concreto.
- `esp:read_u8(dir)` / `esp:write_u8(dir, valor)` — leer/escribir un byte.
- `manager.machine.memory.shares[nombre]` — un bloque de memoria
  compartido, con los mismos métodos `read_u8`/`write_u8`.
- `manager.machine.video:begin_recording(ruta, 'avi')` /
  `:end_recording()` — grabar un AVI a partir de este momento.
- `manager.machine.input:code_from_token(token)` /
  `:code_to_token(codigo)` / `:code_pressed(codigo)` — resolver y leer una
  tecla cruda del teclado, sin pasar por el ioport del juego.
- `manager.machine.screens` — tabla de pantallas; `scr:snapshot(ruta)` (no
  se usa en `creditos.lua` mismo, pero sí en los scripts de prueba que lo
  cargan).
- `debug.getinfo(1, 'S').source` — ruta del propio script en ejecución (con
  un `@` delante), para poder hacer `dofile` de los módulos vecinos.

---

## 2. `monedero.lua`

### 2.1 Propósito

Es la **contabilidad pura** del monedero compartido entre el frontend y
MAME: leer/escribir el fichero `creditos.txt`, y dos construcciones
reutilizables — un detector de pulsaciones con antirrebote, y una máquina
de saldo/consumo/devolución.

### 2.2 Cómo se invoca

No es un script de MAME: es una **biblioteca** que `creditos.lua` carga con
`dofile(MI_DIR .. 'monedero.lua')` y usa a través de la tabla `M` que
devuelve. **A propósito no llama a ninguna función de la API de MAME** —
ni `manager`, ni `emu`, nada —, así que se puede ejecutar con cualquier
intérprete Lua a secas; de ahí que `pruebas/prueba_monedero.lua` la pruebe
sin compilar ni arrancar MAME.

No tiene variables de entorno propias: todos sus parámetros (ruta, saldos,
frames de antirrebote) los recibe como argumentos de sus funciones, puestos
por quien la usa (`creditos.lua`).

### 2.3 Funciones

- **`M.leer(ruta)`** — abre el fichero con `io.open(ruta, 'r')`; si no
  existe, devuelve `nil`. Recorre línea a línea con `f:lines()` buscando
  `saldo N` o `inserta N` con un patrón (`'^%s*(%a+)%s+(%-?%d+)%s*$'`). Si
  una línea no casa con ese patrón pero es un número suelto
  (`'^%s*(%d+)%s*$'`), se interpreta como `inserta N` — es el formato viejo
  de un solo número, que se sigue aceptando porque es cómodo para probar a
  mano (`echo 3 > creditos.txt`). Si no se encontró ni `saldo` ni `inserta`
  en ningún sitio, devuelve `nil` (fichero vacío o basura). Si se encontró
  algo, devuelve `math.max(0, ...)` de los dos valores — nunca negativos —,
  con el que falte puesto a 0.

- **`M.escribir(ruta, saldo, inserta)`** — escribe a `ruta .. '.tmp'` con
  `io.open(..., 'w')`, y hace `os.rename(tmp, ruta)`. En POSIX ese
  renombrado es atómico: matar MAME a media escritura no puede dejar el
  fichero con contenido a medias, porque el fichero final o es el viejo
  completo o es el nuevo completo, nunca algo intermedio. Si el `rename`
  fallara, se borra el temporal y se devuelve `false`.

- **`M.pulsador(leer, hueco)`** — construye un detector de flancos con
  antirrebote. `leer` es una función que devuelve si el botón está pulsado
  *ahora* (nunca habla con MAME directamente: quien construye el pulsador
  decide qué función usar para leer, y eso es lo que permite sustituirla en
  las pruebas). El objeto devuelto tiene un campo `.frame()` que:
  - Cuenta atrás `p.espera` si es mayor que 0.
  - Lee el estado actual y calcula el flanco (`ahora and not p.antes`).
  - Si no hay flanco, devuelve `false`.
  - Si hay flanco pero `p.espera > 0` (todavía dentro de la ventana de
    antirrebote de la pulsación anterior), lo cuenta como `p.rebotes` y
    devuelve `false` sin contar la pulsación.
  - Si hay flanco fuera de la ventana, arma `p.espera = hueco`, incrementa
    `p.veces` y devuelve `true`.

  El objeto expone también `.veces` (pulsaciones válidas contadas) y
  `.rebotes` (flancos descartados por antirrebote), útiles para depurar.

- **`M.cuenta(op)`** — construye la máquina de saldo. `op.base` es el
  saldo de partida (incluyendo lo que ya se ha insertado en el juego);
  `op.guardar(n)` es la función que persiste el saldo (normalmente,
  escribir el fichero); `op.log` para diagnóstico.
  - `c.saldo()` devuelve `max(0, base - consumido)`.
  - `c.guardar_ahora()` fuerza un guardado inmediato del saldo actual — se
    usa nada más crear la cuenta, para que si el jugador sale sin llegar a
    jugar, el crédito recién insertado en el juego vuelva al monedero desde
    ya, en vez de quedar "cobrado" hasta que ocurra algún otro evento.
  - `c.consume(n)` suma `n` (truncado a entero, no negativo) a `consumido`,
    guarda el nuevo saldo y registra en el log.
  - `c.devuelve(n)` resta `n` de `consumido` (sin bajar de 0), guarda y
    registra. Existe porque el crédito se cobra **al meter la moneda**,
    antes de saber si el juego la recogerá de verdad; si la placa aún
    estaba arrancando y la tira, hay que devolverlo.

### 2.4 Flujo de datos

`creditos.lua` es el único cliente. Le pasa funciones que sí tocan MAME
(`entrada:seq_pressed(seq)` para el pulsador de moneda, el lector de
`START1`/`START2`) y funciones que tocan el fichero (`MON.escribir`) para
`guardar`. `monedero.lua` no sabe nada de MAME ni del fichero de créditos
más allá del formato de texto que él mismo define.

### 2.5 Trampas y decisiones no obvias

- **La regla de fondo, escrita en la cabecera del fichero:** *"el monedero
  paga por lo que se JUEGA, no por lo que se mete"* — `saldo = base -
  consumido`, y `consumido` sólo sube cuando el juego se lleva el crédito
  (o, en modo `meter`, cuando se mete la moneda — decisión posterior de
  Eloy documentada en `CLAUDE.md`, no en este fichero). El módulo en sí es
  agnóstico a esa política: sólo ofrece `consume`/`devuelve`, y es
  `creditos.lua` quien decide cuándo llamarlos según `GA_COBRO`.
- **Por qué el antirrebote tiene valores distintos en cada entrada (esto se
  ve en cómo lo usa `creditos.lua`, no en este fichero, pero conviene
  saberlo aquí): el pulsador que cuenta las monedas del jugador dentro de
  MAME usa 8 frames (~130 ms), mientras que el propio frontend (fuera de
  este repo Lua) usa 40 ms para las monedas reales de la chauchera — son
  entradas distintas con requisitos distintos, y `M.pulsador` es lo bastante
  genérico como para servir a las dos con sólo cambiar el parámetro
  `hueco`.
- **`c.devuelve` nunca deja `consumido` negativo**: `if c.consumido < 0 then
  c.consumido = 0 end`. Sin este recorte, devolver de más (que no debería
  pasar, pero el código no lo da por sentado) dejaría el saldo por encima
  de `base`, regalando créditos.

---

## 3. `tarifa.lua`

### 3.1 Propósito

Analiza el DIP switch de tarifa ("Coinage") de la máquina en marcha:
encuentra cuál es, interpreta su texto actual, y sabe calcular qué valor
hay que poner para conseguir 1 moneda = 1 crédito. Es la única pieza de
**hechos** sobre la tarifa; qué hacer con esos hechos (forzar 1C/1C,
compensar, o no tocar nada) es una decisión que toman `creditos.lua` y
`poner_1c1c.lua`, cada uno a su manera, cargando este mismo módulo con
`dofile` para no duplicar el análisis.

### 3.2 Cómo se invoca

Biblioteca cargada con `dofile`, tanto desde `creditos.lua` como desde
`poner_1c1c.lua`. A diferencia de `monedero.lua`/`aviso.lua`/`memoria.lua`,
**sí** llama directamente a `manager.machine.ioport`, porque su trabajo es
inherentemente inspeccionar el estado real de los DIP de la máquina en
marcha — no hay forma razonable de fingir eso sin montar una maqueta
completa de MAME, así que sus pruebas (`prueba_tarifa.lua`) sólo cubren las
dos funciones puras (`M.partir`, `M.con_premio`), no `M.buscar_dip` ni
`M.valor_1c1c` con un DIP real.

No tiene variables de entorno propias.

### 3.3 Funciones

- **`M.partir(texto)`** — interpreta el texto de un ajuste de DIP y
  devuelve `monedas, creditos, es_gratis` (o `nil` si el texto no se
  reconoce como una tarifa). Cubre tres formatos, en este orden:
  1. `"Free Play"` (sin distinguir mayúsculas) → `0, 0, true`.
  2. La forma larga más común, `"N Coin(s)/M Credit(s)"`
     (patrón `'(%d+)%s*coins?%s*/%s*(%d+)%s*credits?'`), tomando siempre
     el **primer tramo** de un texto compuesto como
     `"1 Coin/1 Credit, 5 Coins/6 Credits"` — el que aplica a la primera
     moneda.
  3. La forma compacta de Konami/Sega, `"A 1/1 B 1/1 C 1/1"`
     (patrón anclado `'^a%s+(%d+)%s*/%s*(%d+)'`) — sólo mira la ranura A,
     que es la que corresponde a `COIN1`.
  4. Un `"1/1"` pelado, por si acaso, como último recurso.

  Si nada casa, devuelve `nil` — y eso es exactamente lo que hace que
  `poner_1c1c.lua` y `tarifa_vigente()` sepan distinguir un ajuste de
  tarifa real de textos como `"Off"`, `"Upright"` o `"256 (Cheat)"`.

- **`M.buscar_dip()`** — recorre **todos** los puertos y **todos** los
  campos de la máquina buscando DIP switches (`campo.type_class ==
  'dipswitch'`) cuyos `campo.settings` (tabla valor→texto) contengan al
  menos un ajuste que `M.partir` reconozca como tarifa. Cada candidato
  encontrado se cuenta (`aciertos`). Como `pairs()` **no garantiza orden**,
  y hay placas con "Coin A" y "Coin B" (dos DIP de tarifa distintos), los
  candidatos se ordenan con `table.sort` — primero por número de aciertos
  descendente, luego por clave (`etiqueta/nombre`) alfabética — para que la
  elección sea **determinista** entre ejecuciones. Devuelve el primero (o
  `nil` si no hay ninguno), como una tabla con `clave`, `etiqueta`,
  `nombre`, `campo` y `aciertos`.

- **`M.ajuste_actual(dip)`** — simplemente
  `dip.campo.settings[dip.campo.user_value]`: el texto del ajuste que la
  máquina tiene puesto ahora mismo.

- **`M.con_premio(texto)`** — un texto "tiene premio" si contiene una coma.
  Los textos con premio son del estilo `"1 Coin/1 Credit, 2/3"`: la primera
  moneda da un crédito, pero acumular dos da tres. Sirve para avisar al
  usuario de que el contador del frontend puede no ser exacto en ese juego
  (`creditos.lua`) y para preferir la variante sin premio al fijar 1C/1C.

- **`M.valor_1c1c(dip)`** — recorre `dip.campo.settings` buscando ajustes
  que `M.partir` interprete como `1 moneda = 1 crédito` sin ser gratis.
  Entre los candidatos, prefiere **el que no tenga premio**
  (`not M.con_premio(texto)`) y, a igualdad, **el valor numérico más bajo**.
  De nuevo, esto es determinismo frente a `pairs()`: sin ordenar el
  criterio de desempate, un juego con varios ajustes `"1 Coin/1 Credit"`
  distintos (como `mwalk`, que tiene cuatro) podría elegir uno diferente en
  cada pasada. Devuelve `valor, texto, sin_premio`.

### 3.4 Flujo de datos

`creditos.lua` llama a `T.buscar_dip()`, `T.ajuste_actual(dip)`,
`T.partir(texto)`, `T.con_premio(texto)` y, si toca fijar la tarifa,
`T.valor_1c1c(dip)` seguido de una escritura directa a
`dip.campo.user_value`. `poner_1c1c.lua` hace exactamente la misma
secuencia, pero como programa independiente que se ejecuta una vez por
juego y termina.

### 3.5 Trampas y decisiones no obvias

- **Los textos vienen traducidos por MAME** a la interfaz configurada; el
  analizador espera inglés. De ahí que `creditos.lua` ofrezca
  `GA_TARIFA=off` como escape total quitando de en medio cualquier
  interpretación de DIP.
- **Nunca se compara con `==` un texto entero**: siempre se usan patrones,
  precisamente porque el mismo concepto se expresa de formas distintas
  según el fabricante (Namco/Taito vs. Konami/Sega).
- **El orden de `pairs()` no está garantizado en Lua**, y este módulo lo
  tiene en cuenta dos veces (en `buscar_dip` y en `valor_1c1c`) con un
  criterio de desempate explícito — un detalle fácil de pasar por alto que,
  sin él, produciría resultados que "a veces cambian solos" entre una
  ejecución y la siguiente exactamente con los mismos datos.

### 3.6 API de MAME usada

- `manager.machine.ioport.ports` — todos los puertos.
- `port.fields` — campos del puerto, indexados por nombre traducido.
- `campo.type_class` — para filtrar sólo los DIP switches
  (`'dipswitch'`).
- `campo.settings` — tabla `valor -> texto` de los ajustes posibles.
- `campo.user_value` — se lee (para saber el ajuste actual) y se escribe
  (para fijarlo); MAME lo persiste en el `.cfg` del juego.

---

## 4. `aviso.lua`

### 4.1 Propósito

Es el **cuadro de aviso** que se pinta cuando el jugador intenta salir
dejando créditos dentro de la máquina: decide si hay algo que avisar,
cuenta cuántos créditos hay (exactos si se conoce la dirección de RAM,
estimados si no), gestiona la máquina de estados de "frenar la salida /
esperar confirmación / dejar salir", y prepara las líneas de texto a
dibujar. No dibuja nada él mismo — eso lo hace `creditos.lua` con los datos
que este módulo le da.

### 4.2 Cómo se invoca

Biblioteca, cargada con `dofile` desde `creditos.lua` **si**
`AVISAR` (`GA_AVISO ~= '0'`, activo por defecto). No llama a ninguna
función de MAME: recibe datos (`op.entrado`, `op.espera`, `op.guarda`,
`op.se_pierden`, `op.dentro`, `op.log`) y, en cada frame, dos booleanos ya
resueltos por quien la llama (`salir`, `seguir`) en vez de leer teclas ella
misma. Por eso `pruebas/prueba_aviso.lua` la prueba sin MAME.

No tiene variables de entorno propias — los mismos conceptos (`GA_AVISO_ESPERA`,
`GA_AVISO_GUARDA`) los lee `creditos.lua` y se los pasa como `op.espera`/
`op.guarda`.

### 4.3 `M.nuevo(op)` — construcción y estado

Devuelve una tabla `a` con:

- `a.exacto` = `op.dentro` — la función (opcional) que da el número de
  verdad leído de la RAM. Si existe, la estimación se queda de reserva.
- `a.se_pierden` — si los créditos que se quedan dentro se pierden de
  verdad (cobro al meter / monedas de verdad) o no (cobro al jugar, con
  monedero).
- `a.entrado` — créditos que ya han entrado en la máquina (el del
  lanzamiento, si lo hay).
- `a.metido` — créditos que ha metido **el jugador** durante esta partida
  (distinto de `entrado`: el crédito del lanzamiento no cuenta como
  "metido por el jugador").
- `a.consumido` — lo que el juego se ha llevado, según la estimación.
- `a.espera` — frames que el cuadro aguanta sin respuesta antes de
  rendirse (mínimo 1, defecto 300).
- `a.guarda` — frames de antirrebote de la tecla de salir tras pintar el
  cuadro (mínimo 0, defecto 15).
- `a.estado` — `'jugando'` o `'avisando'`.

### 4.4 Funciones

- **`a.entra(n)`** — el jugador mete `n` créditos durante la partida (se
  llama desde `creditos.lua` en cada moneda aceptada). Suma a `a.entrado` y
  a `a.metido`.

- **`leido()`** (función local, no expuesta) — si hay `a.exacto`, la llama
  protegida con `pcall`; si tiene éxito y devuelve un número, lo trunca y
  lo recorta a no-negativo. Si `a.exacto` no existe, o falla, o no es un
  módulo confiable en este momento (ver más abajo), devuelve `nil`.

- **`a.dentro()`** — si `leido()` da un número, ese es el resultado. Si no,
  estima `entrado - consumido`, recortado a no-negativo.

- **`a.seguro()`** — `true` si `leido() ~= nil`, es decir, si el número que
  da `a.dentro()` viene de la RAM y no de una estimación.

- **`a.puede_quedar()`** — decide si hay *algo* que avisar. Con lectura
  exacta, es simplemente `leido() > 0`. **Sin ella**, es `a.metido > 0` —
  decisión explícita de Eloy documentada en el propio código: la
  estimación no puede distinguir un START que empieza partida de otro que
  el juego ignora por tener ya una partida en marcha, así que en una
  partida larga la estimación se iría a cero sola y el aviso se callaría
  teniendo créditos de verdad dentro. Entre "molestar de más" (el jugador
  pulsa salir dos veces) y "callarse de más" (el jugador pierde créditos
  pagados sin enterarse), se elige el primer error.

- **`a.consume(n)`** — resta de lo que queda por consumir, pero **nunca
  más de lo que hay disponible** (`tope = a.entrado - a.consumido`; si
  `tope <= 0`, no hace nada). Este tope es la pieza que arregla el "no
  siempre avisa": sin él, cada pulsación de START que el juego *ignora*
  (con la partida ya en marcha, todas) seguiría restando de la estimación
  y generando una deuda que se comía las monedas metidas después.

- **`a.frame(salir, seguir)`** — la máquina de estados central, se llama
  una vez por frame desde `creditos.lua`. Devuelve `nil` (nada que hacer),
  `'bloquear'` (comerse la tecla de UI y pintar el cuadro) o `'salir'`
  (confirmado, dejar salir de verdad).
  - Calcula el flanco de `salir` comparando con `a.salir_antes`.
  - En `'jugando'`: si hay flanco de salir, y el jugador metió monedas
    (`a.metido > 0`), y `a.puede_quedar()`, pasa a `'avisando'`, resetea
    `a.reloj`, registra en el log (con número exacto o con el mensaje
    genérico según `a.seguro()`), y devuelve `'bloquear'`. Si no se cumplen
    esas condiciones, devuelve `nil` — MAME sigue a lo suyo.
  - En `'avisando'`: incrementa `a.reloj`. Si hay un nuevo flanco de salir
    pero `a.reloj <= a.guarda`, se interpreta como **rebote de la tecla**,
    no como confirmación (se registra en el log y no se hace nada más ese
    frame). Si el flanco llega después de la guarda, se confirma la salida
    (`'jugando'`, devuelve `'salir'`). Si `seguir` es verdad (el jugador
    pulsó START), se cancela el aviso y se sigue jugando
    (`'bloquear'`, porque ese mismo frame aún hay que comerse la tecla si
    coincidiera). Si ya no puede quedar nada (`not a.puede_quedar()`), se
    quita el cuadro solo. Si se agotó `a.espera` sin respuesta, también se
    quita el cuadro **sin salir** — el comentario del código lo resume:
    *"ante la duda, la partida sigue"*.

- **`a.visible()`** — `a.estado == 'avisando'`.

- **`a.lineas(saldo)`** — construye el array de textos a pintar. La
  segunda línea afirma un número exacto («DEJAS N CREDITOS...») sólo si
  `a.seguro()`; si no, dice «PUEDE(N) QUEDAR...» o, si la estimación fuera
  cero (que puede pasar y aun así haber aviso, por `puede_quedar()`), el
  texto genérico sin número «PUEDEN QUEDAR CREDITOS DENTRO DE ESTA
  MAQUINA». La tercera línea depende de `a.se_pierden` y de si hay `saldo`
  (monedero): con `se_pierden`, avisa de pérdida real («SI SALES AHORA LOS
  PIERDES», con el saldo del monedero si lo hay); sin `se_pierden` y con
  saldo, tranquiliza («SOLO VALEN AQUI. TU MONEDERO NO SE TOCA: N»); sin
  saldo (modo manual, sin monedero), siempre avisa de pérdida porque no hay
  nada que prometer.

### 4.5 Flujo de datos

`creditos.lua` construye el objeto con `AV.nuevo{...}` pasándole
`se_pierden` (calculado según `HAY_MONEDERO` y `COBRO`), `entrado` (0 si es
partida gratis, si no `INSERTA`), `espera`/`guarda` de las variables de
entorno, y `dentro` — una función que envuelve `GA_ESTADO.memoria.dentro()`
pero devuelve `nil` mientras `GA_ESTADO.a_prueba` exista (dirección
importada aún no verificada). En cada frame, `creditos.lua` llama a
`a.entra(n)` cuando se cuenta una moneda, a `a.consume(n)` cuando se
detecta consumo (por memoria exacta o por estimación de START), y a
`a.frame(leer_salir(), s1 or s2)` una vez por frame, actuando sobre el
resultado.

### 4.6 Trampas y decisiones no obvias

- **El antirrebote de la tecla de salir (`a.guarda`) es la pieza que
  arregló el "a veces no avisa" de verdad.** Un microinterruptor (la tecla
  física, o el botón del mueble mapeado a `UI_CANCEL`) rebota al pulsarse:
  una sola pulsación humana puede generar dos flancos en unos pocos
  milisegundos. Sin la guarda, el primer flanco pintaba el cuadro y el
  segundo (el rebote) lo confirmaba tres frames después — el jugador veía
  que "no avisó" cuando en realidad avisó y se contestó solo.
- **`a.consume` con tope es indispensable en los juegos sin dirección de
  RAM conocida.** Sin el tope, aporrear START durante una partida ya
  empezada (que el juego ignora, medido) generaba una deuda de consumo que
  se comía las monedas metidas *después*, dejando el aviso mudo aunque el
  jugador acabara de pagar créditos de verdad.
- **`a.puede_quedar()` decide con criterios distintos según haya o no
  lectura exacta**, y eso es intencional: con lectura exacta, un cero es un
  cero de verdad y no hay que molestar; sin ella, un cero de la estimación
  no significa nada fiable, así que se avisa igual mientras el jugador haya
  metido algo.
- **Nunca se afirma un número sin lectura exacta.** `a.lineas` distingue
  explícitamente "DEJAS N CREDITOS" (afirmación, sólo con `a.seguro()`) de
  "PUEDEN QUEDAR..." (posibilidad, con la estimación). Decir "DEJAS 0
  CREDITOS" cuando el cuadro se muestra precisamente porque no se sabe si
  hay 0 o más sería, en palabras del propio código, "mentira y además
  absurdo".

---

## 5. `memoria.lua`

### 5.1 Propósito

Todo lo relacionado con **leer y escribir el contador de créditos en la RAM
del juego, cuando se conoce su dirección**: parsear `creditos.dat`, llevar
la cuenta de entradas/consumos observando cómo cambia ese byte, y el
sincronizador que fuerza el valor del monedero directamente en la RAM.

### 5.2 Cómo se invoca

Biblioteca cargada con `dofile` desde `creditos.lua`. Como `monedero.lua` y
`aviso.lua`, no llama a la API de MAME: recibe una función `leer` (y, para
el sincronizador, también `escribir`) que sí la usan, y así se puede
probar con `pruebas/prueba_memoria.lua` sin MAME de por medio.

No tiene variables de entorno propias — los parámetros que en `creditos.lua`
vienen de `GA_ASENTAR`, `GA_TOPE`, etc. se los pasa `creditos.lua` como
campos de la tabla de opciones.

### 5.3 Funciones

- **`M.entrada(ruta, juego)`** — abre `creditos.dat`, ignora líneas que
  empiecen por `#`, y busca (con el patrón
  `'^%s*([%w_%-]+)%s+@([^,]+),([^,]+),([%x+]+)'`) la línea cuyo nombre casa
  con `juego`. El cuarto grupo capturado son una o varias direcciones
  hexadecimales separadas por `+` (`b60+bbd+1100` para Q\*bert, que
  mantiene tres copias del contador); se parten con
  `dirs:gmatch('%x+')` y se convierten con `tonumber(d, 16)`.
  Devuelve una tabla con:
  - `cpu`, `espacio` — tal cual aparecen en la línea (p.ej. `:maincpu`,
    `program`).
  - `dir` — la primera dirección (la que se **lee**).
  - `dirs` — la lista completa (donde se **escribe**).
  - `comprobada` — `false` si la línea contiene la subcadena `(cheat)`
    (viene de la colección de cheats de MAME, importada sin verificar
    ejecutando el juego); `true` si no.
  - `bcd` — `true` si la línea contiene la palabra suelta `bcd` al final
    (comprobado con un patrón de fronteras de palabra,
    `'%f[%w]bcd%f[%W]'`, para no confundirse con un nombre de juego que
    *contenga* "bcd" como subcadena, p.ej. un `bcdfalso` de prueba).

  Si no se encuentra el juego, devuelve `nil`.

- **`M.contador(op)`** — construye un objeto que sigue la evolución del
  byte de créditos frame a frame. Campos de configuración:
  `op.leer` (función), `op.max_salto` (créditos por moneda plausibles,
  defecto 4), `op.asentar` (frames de espera antes de empezar a contar),
  `op.al_asentar` (callback al terminar de asentarse — la limpieza),
  `op.log`.
  - **`c.frame()`** — lee el byte (protegido con `pcall`; si falla o no es
    número, no hace nada). Mientras `not c.asentado`: sólo actualiza
    `c.anterior` y cuenta atrás `c.espera`; al llegar a 0, marca
    `c.asentado = true`, llama a `c.al_asentar(v)` si existe, y **relee**
    el valor después de esa llamada (porque `al_asentar` puede haber
    escrito en la RAM para limpiar créditos no pagados, y ese cambio no
    debe contarse como "el juego se llevó un crédito"). Ya asentado,
    calcula el delta `d = v - c.anterior`: si es 0, nada; si está entre 1 y
    `max_salto`, se suma a `c.entrado`; si está entre -1 y -`max_salto`, se
    resta (en valor absoluto) a `c.consumido`, con log; si el salto es
    mayor (en cualquier signo) que `max_salto`, se cuenta como "raro"
    (`c.raros`) y se ignora del todo — es la protección contra un reset de
    placa que pone el contador a cero de golpe sin que sea una partida
    jugada.
  - **`c.asentar_ya()`** — fuerza el fin del asentamiento inmediatamente,
    sin esperar a que se agote `c.espera`: pone `c.espera = 0` y llama a
    `c.frame()` una vez más. La usa `fin_del_arranque()` en `creditos.lua`,
    que sabe mejor que este módulo cuándo la RAM ya es de fiar (el fin del
    arranque tapado).
  - **`c.dentro()`** — `nil` si `not c.asentado` (todavía no se sabe:
    mejor no inventar un número), si no `c.anterior` (o 0).

- **`M.sincronizador(op)`** — construye el objeto que fuerza el valor del
  monedero directamente en la RAM, en vez de simular monedas. Parámetros:
  `op.leer`, `op.escribir`, `op.valor` (lo que se quiere dejar puesto),
  `op.intentos` (defecto 6), `op.cada` (cada cuántos frames se reintenta,
  defecto 20), `op.log`.
  - **`s.frame()`** — devuelve `'pendiente'`, `'hecho'` o `'rendido'`, y una
    vez que llega a uno de los dos últimos estados se queda ahí para
    siempre (no vuelve a intentar nada). Sólo actúa cada `op.cada` frames.
    Cada vez que actúa: lee el valor actual; si ya coincide con
    `s.valor`, pasa a `'hecho'`. Si no, y ya se agotaron los intentos,
    pasa a `'rendido'`. Si no, incrementa `s.hechos` y escribe
    (protegido con `pcall`).

### 5.4 Flujo de datos

`creditos.lua` llama a `MEM.entrada(...)` una vez al arrancar para saber si
el juego actual tiene dirección conocida. Con ella, construye
`GA_ESTADO.leer_ram`/`escribir_ram` (aplicando la traducción BCD, que vive
en `creditos.lua`, no en `memoria.lua` — este módulo trabaja siempre con el
número ya traducido a "créditos", nunca con el byte crudo), y pasa esas
funciones a `MEM.contador{...}` y, si procede, a `MEM.sincronizador{...}`.
El resultado de `contador.dentro()` alimenta tanto el marcador en pantalla
como el `op.dentro` que recibe `aviso.lua`.

### 5.5 Trampas y decisiones no obvias

- **El asentamiento (`asentar`) existe porque, arrancando en el frame 0
  para que el cerrojo exista desde el principio, la RAM del juego todavía
  es basura** (medido: el byte de créditos de Pac-Man valía 176 antes de
  que la placa terminara su test). Sin este margen, el primer valor leído
  se tomaría como referencia real y contaminaría toda la cuenta posterior.
- **`al_asentar` puede escribir en la RAM, y por eso se relee después.**
  Si no se releyera, la escritura de limpieza (poner a 0 lo que sobra) se
  contaría como si el juego se hubiera "llevado" esos créditos —
  `c.consumido` subiría por algo que no fue una partida jugada.
- **Los saltos grandes se ignoran a propósito** (`c.raros`), no se
  interpretan como consumo ni como entrada. Un reset de placa (o cualquier
  anomalía) pone el contador a un valor muy distinto de golpe, y contarlo
  cobraría o regalaría créditos por algo que no fue el jugador.
- **El sincronizador se rinde con dignidad**: tras agotar los intentos,
  `'rendido'` no es un error silencioso — `creditos.lua` lo comprueba
  (paso 8 de `por_frame`, sección 1.9) y, si procede, vuelve al método
  clásico de simular monedas. Es decir, este módulo no decide el plan B;
  sólo informa con precisión de que su plan A no funcionó.

### 5.6 API de MAME usada

Ninguna, directamente. Todo el acceso a memoria (`read_u8`/`write_u8`) lo
hace `creditos.lua` al construir las funciones `leer`/`escribir` que le
pasa a este módulo.

---

## 6. `cerrojo.lua`

### 6.1 Propósito

Implementa la lógica de **cuándo el botón de moneda debe dejar de
responder**: sin monedero disponible, mientras la placa arranca, o cuando
la máquina ya tiene todos los créditos que admite. No toca MAME
directamente: recibe las funciones `bloquear`/`soltar` que sí lo hacen.

### 6.2 Cómo se invoca

Biblioteca cargada con `dofile` desde `creditos.lua`, si `CERROJO`
(`GA_CERROJO ~= '0'`, activo por defecto) y se pudo leer la secuencia por
defecto del campo de moneda. No llama a la API de MAME: recibe `op.bloquear`
y `op.soltar` ya cerradas sobre `CAMPO:set_default_input_seq(...)`. Probado
sin MAME en `pruebas/prueba_cerrojo.lua`.

No tiene variables de entorno propias.

### 6.3 `M.nuevo(op)` — construcción y campos

- `ilimitado` — si es verdad, no hay tope de monedas por monedero (modo
  monedas de verdad, sin `HAY_MONEDERO`); el cerrojo sólo sigue existiendo
  para las otras dos razones de cierre (arranque, máquina llena).
- `limite` — monedas que el jugador puede meter (su saldo al lanzar), sólo
  relevante si no es ilimitado.
- `metidas` — cuántas ha metido ya en esta partida.
- `echado` — `nil` al principio (todavía no se ha decidido nada, así el
  primer `frame()` siempre dispara el bloqueo o la suelta explícitamente,
  en vez de asumir un estado de partida).
- `listo` — `false` mientras la placa arranca; segunda razón de cierre.
- `lleno` — función (por defecto siempre `false`) que dice si la máquina ya
  tiene el tope de créditos; tercera razón de cierre.
- `bloquear`/`soltar` — las funciones inyectadas que tocan MAME de verdad.

### 6.4 Funciones

- **`c.disponible()`** — `math.huge` si `ilimitado`; si no,
  `max(0, limite - metidas)`.

- **`c.moneda()`** — se llama en cada pulsación **detectada** del botón
  (incluso con el cerrojo echado — es intencional, ver 6.5). Si
  `c.echado` o `not c.listo`, cuenta el rechazo (`c.rechazadas`) y devuelve
  `false`. Si no, cuenta la moneda (`c.metidas += 1`) y devuelve `true`.
  Nótese que **no** consulta aquí `c.lleno()` para rechazar — esa condición
  sólo se evalúa en `c.frame()`, y si `c.echado` ya está puesto por estar
  llena, la rama de `c.echado` la cubre igualmente.

- **`c.frame()`** — se llama una vez por frame. Calcula si hace falta
  bloquear (`not c.listo`, o `c.disponible() <= 0`, o `c.lleno()`), y sólo
  actúa (llamando a `bloquear()`/`soltar()` y registrando en el log) si el
  resultado **cambia** respecto al frame anterior — no en cada frame. El
  mensaje de log distingue las tres causas (arrancando / llena /
  sin créditos) y, en el caso ilimitado, evita formatear `%d` sobre
  `math.huge`, que en Lua 5.4 revienta un `string.format`.

- **`c.motivo()`** — para poder explicarle al jugador *por qué* no pasa
  nada: devuelve `'arrancando'`, `'lleno'`, `'sin creditos'` o `nil` (todo
  bien).

- **`c.cuantas()`** — texto para el log del arranque: "las que quiera" si
  es ilimitado, o el número si no.

- **`c.soltar_todo()`** — se llama al terminar la partida (equivalente a
  la limpieza final): si el cerrojo estaba echado, lo suelta
  incondicionalmente. Es idempotente (si ya estaba suelto, no hace nada
  otra vez).

### 6.5 Flujo de datos

`creditos.lua` construye el cerrojo con:
```lua
CER.nuevo{
  ilimitado = not HAY_MONEDERO,
  limite   = SALDO,
  lleno    = function() ... end,   -- consulta e.memoria.dentro() con cautela
  bloquear = function() CAMPO:set_default_input_seq('standard', vacia) end,
  soltar   = function() CAMPO:set_default_input_seq('standard', orig) end,
  log = log,
}
```
En `por_frame()`, el detector de la moneda del jugador
(`GA_ESTADO.pulso_moneda`) llama primero a `e.cerrojo.moneda()`: si
devuelve `false`, se elige el mensaje según `e.cerrojo.motivo()`; si
devuelve `true`, se procesa la moneda normalmente (aviso, cuenta,
sincronización). Y, ya procesada la moneda de ese frame,
`e.cerrojo.frame()` se llama para reevaluar el estado del bloqueo — a
propósito **después**, para que la última moneda disponible entre y el
cierre empiece en ese mismo frame.

### 6.6 Trampas y decisiones no obvias

- **`c.moneda()` se llama siempre, incluso con el cerrojo ya echado.** Esto
  es deliberado: el detector de flanco de la moneda (en `creditos.lua`) usa
  la **secuencia original**, copiada al arrancar, no la secuencia efectiva
  del campo (que el cerrojo pone a "vacía"). Así, aunque el botón físico no
  tenga ningún efecto sobre MAME (porque `set_default_input_seq` lo dejó
  sin secuencia), el script sigue **detectando** que el jugador lo pulsó, y
  puede explicarle por qué no ha pasado nada.
- **`bloquear()`/`soltar()` sólo se llaman en el cambio de estado**, nunca
  en cada frame — importante para no ensuciar el log ni volver a llamar a
  `set_default_input_seq` innecesariamente 60 veces por segundo.
- **La comprobación de que el bloqueo "surtió efecto" no vive en
  `cerrojo.lua`, sino en la función `bloquear` que le inyecta
  `creditos.lua`** (ver sección 1.4, paso 11): tras llamar a
  `set_default_input_seq`, se relee `CAMPO:input_seq('standard').length` y,
  si sigue sin ser cero, se avisa una sola vez (`avisado`) de que el
  cerrojo no ha surtido efecto — porque el juego (o el `.cfg` del usuario)
  tiene una secuencia propia cargada en `live().seq`, que `seq()` devuelve
  por delante de `defseq()`.
- **El caso "sin monedero" (`ilimitado = true`) sigue montando el
  cerrojo**, aunque no haya ningún límite de monedas que aplicar: la
  *única* razón para montarlo en ese caso es que el cerrojo también cierra
  el botón mientras la placa arranca (`listo = false`), que es justo el
  agujero que dejaba entrar créditos gratis a un jugador que pulsara la
  moneda durante el test de RAM/ROM de la placa.

---

## 7. `ajustes.lua`

### 7.1 Propósito

Parsea `arranque.dat` (nombre de set + pares `clave=valor`) y ofrece un
"consultor" con la precedencia ya resuelta: variable de entorno > línea del
juego > línea `defecto` > valor interno de `creditos.lua`. Es la pieza que
permite que **casi todos** los parámetros de arranque de `creditos.lua`
(velocidad, segundos de arranque tapado, nvram, barrido, contador,
límite...) se configuren por juego sin tocar código ni variables de
entorno.

### 7.2 Cómo se invoca

Biblioteca cargada con `dofile` desde `creditos.lua`. No es un
`-autoboot_script`; no llama a la API de MAME en absoluto — sólo usa
`io.open` y patrones de texto, así que se prueba entera sin MAME
(`pruebas/prueba_ajustes.lua`). Los "GA_*" que aparecen en la tabla de la
sección 1.3 con equivalente en `arranque.dat` no los lee este fichero: los
lee `creditos.lua` a través de las funciones `a.valor`/`a.frames` que este
módulo expone, pasándole `os.getenv` como argumento.

### 7.3 Formato del fichero (`arranque.dat`)

```
defecto  velocidad=0 segundos=5 max=30
pacman   segundos=7
simpsons velocidad=2 segundos=15 fijo=1
```

- Una línea por juego (o la especial `defecto`, que vale para los que no
  tengan línea propia).
- Comentarios con `#` hasta fin de línea; se recortan antes de analizar
  nada más.
- Los valores se guardan en **segundos** dentro del fichero; los que
  representan tiempo se convierten a frames al consultarlos con
  `a.frames(...)` (a 60 Hz por defecto). Los que no son tiempos (banderas,
  porcentajes) se consultan con `a.valor(...)` y se quedan tal cual.

### 7.4 Funciones

- **`M.leer(ruta)`** — abre el fichero; si no existe, devuelve una tabla
  vacía (`{ defecto={}, juegos={}, avisos={} }`) y un segundo valor con el
  mensaje de error, sin reventar. Por cada línea no vacía (tras quitar
  comentario y espacios de los bordes):
  - Extrae el primer token como `nombre` y el resto como pares
    `clave=valor` con `linea:gmatch('(%w+)%s*=%s*([%w%.%-]+)')`; cada valor
    se intenta convertir a número, y si no es numérico se guarda como
    cadena (por ejemplo, para un ajuste de texto que no exista todavía,
    aunque hoy todos los ajustes que usa `creditos.lua` son numéricos).
  - Si `nombre` contiene un `=` (señal de una línea corrupta donde el
    separador entre el nombre y el primer `clave=valor` no era un
    espacio — pasó de verdad, con un `?` literal), se apunta en
    `r.avisos` **en vez de** guardarse como un juego nuevo: sin este aviso,
    esa línea se interpretaría como un "juego" cuyo nombre es el texto
    entero, y sus ajustes reales no se aplicarían nunca, en silencio.
  - Si el nombre es `'defecto'`, sus ajustes van a `r.defecto`. Si no, van a
    `r.juegos[nombre:lower()]` — **en minúsculas**, para que el nombre del
    set en `arranque.dat` no dependa de cómo se haya escrito.

  Importante para quien mantiene el fichero de la cabina: **este parser en
  Lua 5.5 no puede reasignar la variable de control del `for` (`cruda`)**
  porque en esa versión es `const`; el código ya la respeta usando una
  variable nueva (`linea`) para la versión recortada, precisamente por eso
  (comentario explícito en el código, y detalle repetido en `CLAUDE.md`
  sobre el mismo error en el plugin `data` de MAME).

- **`M.para(tabla, juego, entorno)`** — construye el consultor para un
  juego concreto. `entorno` es una función `nombre -> valor|nil` (se le
  pasa `os.getenv`, o una función de mentira en las pruebas). Devuelve una
  tabla `a` con:
  - `a.propios` — los ajustes de la línea de este juego (o `{}` si no
    tiene).
  - `a.defecto` — los de la línea `defecto`.
  - `a.hay_linea` — si el juego tiene línea propia (no se usa en
    `creditos.lua` hoy, pero queda disponible).
  - **`a.valor(clave, var, defecto)`** — si `var` no es `nil` y la
    variable de entorno correspondiente tiene un valor numérico, gana ella
    (segundo valor de retorno: `'entorno'`). Si no, mira `a.propios[clave]`
    (`'juego'`); si no, `a.defecto[clave]` (`'defecto'`); si no, el
    `defecto` interno pasado como argumento (`'interno'`).
  - **`a.frames(clave, var, defecto_frames, hz)`** — misma precedencia,
    pero: la variable de entorno se toma **tal cual, en frames** (para no
    romper las pruebas y usos antiguos que ya trabajaban en frames), y el
    valor del fichero (en segundos, propio o por defecto) se multiplica
    por `hz` (60 por defecto) y se redondea (`math.floor(v*hz + 0.5)`).

### 7.5 Flujo de datos

`creditos.lua` llama una vez a `AJU.leer(ruta)` y una vez a `AJU.para(tabla,
emu.romname(), os.getenv)`, y a partir de ahí todos los `ajuste(...)` y
`ajuste_frames(...)` de `creditos.lua` son delgados envoltorios sobre
`AJUSTES.valor(...)`/`AJUSTES.frames(...)`.

### 7.6 Trampas y decisiones no obvias

- **Los tiempos se piensan en segundos y se ejecutan en frames**, y la
  conversión vive exclusivamente aquí — es la única razón de ser de
  `a.frames` frente a `a.valor`.
- **Una variable de entorno que fija un tiempo se interpreta en frames, no
  en segundos**, aunque el fichero use segundos. Es una asimetría
  deliberada: las pruebas y los usos antiguos (antes de que existiera
  `arranque.dat`) ya pasaban frames por entorno, y cambiar esa unidad
  habría roto todos los escenarios existentes sin avisar.
- **Un nombre de juego con `=` dentro no se descarta en silencio: se
  avisa** (`r.avisos`). Es la corrección de un fallo real ya vivido: un
  editor dejó `pacman?arranque=5` con un carácter extraño en vez de un
  espacio, y ninguno de los ajustes de ese juego se aplicaba nunca, sin que
  nada lo indicara.
- **`segundos=0` desactiva la ventana entera, velocidad incluida** — esto
  no lo impone `ajustes.lua` (que simplemente devuelve 0 frames si eso es
  lo que dice el fichero), sino que es una consecuencia que `creditos.lua`
  detecta y de la que avisa explícitamente en el log (`ARRANQUE <= 0` con
  velocidad distinta de 100%).

### 7.7 API de MAME usada

Ninguna. Sólo `io.open`, `string.gmatch`/`match`/`gsub`, `tonumber`.

---

## 8. `buscar_creditos.lua`

### 8.1 Propósito

Es la herramienta que **encuentra** en qué dirección de RAM guarda un juego
concreto su contador de créditos, para poder añadir la línea correspondiente
a `creditos.dat`. El método general (por qué tres monedas y no dos, por qué
un solo START, la prueba funcional final, los filtros de ambigüedad) está
documentado a fondo en `docs/direcciones-ram.md`; aquí sólo se explica qué
hace **este script** como programa.

### 8.2 Cómo se invoca

Es un `-autoboot_script` de MAME, pero de un solo uso: se lanza una vez por
juego (normalmente desde `buscar_creditos.sh`, que recorre la lista
completa de sets), imprime **una línea** con el resultado por `print()`, y
termina la máquina con `manager.machine:exit()`. No se usa nunca en la
cabina en marcha — no tiene ni concepto de "monedero" ni de "aviso al
salir": su única salida es esa línea de texto.

Variable de entorno: `GA_BUSCA_ESPERA` (defecto `45` frames) — cuánto se
espera entre cada paso del guion (pulsar, esperar, comprobar) para dar
tiempo a que la RAM refleje el cambio.

### 8.3 Recorrido de la ejecución

1. Calcula `juego = emu.romname()` y define `decir(txt)` para imprimir
   siempre con el prefijo `CREDITOS juego=<juego> ...`, que es lo que el
   script de shell que recorre la lista completa sabe parsear.
2. Recopila **todos** los procesadores con espacio `'program'`
   (`manager.machine.devices`), no sólo `:maincpu`, y los ordena con
   `:maincpu` primero (si el contador vive en dos sitios, se prefiere el de
   la CPU principal).
3. Si no hay ningún procesador con espacio de programa, imprime
   `estado=sin-cpu` y sale.
4. Construye la lista de **bloques de RAM** a vigilar: recorre
   `sp.map.entries` de cada CPU, quedándose con los tramos cuyo
   `read.handlertype` o `write.handlertype` sea `'ram'` (con un tope de
   256 KiB por tramo, para no vigilar bloques absurdamente grandes), y de
   paso anota en `base_de_share` la dirección de arranque de cualquier
   *share* referenciado desde el mapa. Luego recorre
   `manager.machine.memory.shares` y añade como bloque cualquier *share*
   del que se conozca su dirección base (los que no aparecen en ningún
   mapa de ninguna CPU no se pueden traducir a una dirección útil para
   `creditos.dat`, así que se descartan).
5. Busca los campos de entrada `COIN1` y `START1` con `campo_de(token)`
   (idéntico patrón que `buscar_moneda()` de `creditos.lua`: por tipo, no
   por nombre). Si falta cualquiera de los dos, sale con
   `estado=sin-moneda` / `estado=sin-start`.
6. Define `instantanea()` — una foto completa de todos los bytes de todos
   los bloques vigilados, como una tabla `"bloque|offset" -> valor` — y
   `traducir(clave)` para volver de esa clave a una dirección real más
   CPU/share.
7. El guion (`GUION`) es una secuencia fija de 5 pasos: moneda, moneda,
   moneda, "marcar" (sin botón), START. Una máquina de estados dirigida por
   `GA_BUSCA = emu.add_machine_frame_notifier(...)` avanza un paso cada
   `ESPERA` frames (esperando primero a que se suelte cualquier botón que
   se hubiera pulsado, con un pulso fijo de 8 frames). En cada transición
   de paso se toma una nueva `instantanea()` y se filtran los `deltas`
   candidatos según la etapa:
   - `'primera'`: cualquier byte cuya subida esté entre 1 y `MAX_DELTA` (4)
     se convierte en candidato, y esa subida se recuerda como su "crédito
     por moneda".
   - `'sube'` (dos veces): sólo sobreviven los candidatos cuya subida en
     esta moneda coincide **exactamente** con la de la anterior.
   - `'marcar'`: a todos los candidatos supervivientes se les escribe el
     mismo valor distintivo (`ESCRIBO = 7`).
   - `'responde'`: tras el único START, sólo sobreviven los candidatos cuyo
     valor bajó a `ESCRIBO-1` o `ESCRIBO-2` (uno o dos créditos gastados) —
     es la prueba funcional: demuestra que el juego de verdad *lee* ese
     byte para decidir si empieza la partida, no que simplemente cambió de
     valor por casualidad.
8. Al terminar el guion, se filtran los `deltas` supervivientes exigiendo
   que la **foto inicial** de ese byte fuera 0 (la placa arranca sin
   créditos; lo que empezó en otro valor es otra cosa), se eliminan
   duplicados exactos (mismo byte visto por dos vías — mapa y share — no es
   ambigüedad), y se ordenan (con las direcciones que parecen de vídeo o de
   color al final, por si acaso, y si no por dirección numérica).
   - Si no queda ninguno: `estado=ninguno-responde`.
   - Si quedan más de 4, o pertenecen a más de una CPU distinta:
     `estado=demasiados candidatos=...` (algo se coló, mejor no
     apuntar nada).
   - Si no: se imprime la línea final con `cpu`, `espacio=program`, las
     direcciones unidas por `+` (todas las copias que respondieron, porque
     el juego puede mantener varias a la vez y pintar desde cualquiera),
     `creditos_por_moneda` y `copias` (cuántas direcciones distintas
     confirmaron).
9. Sea cual sea el resultado, `manager.machine:exit()` termina la máquina.

### 8.4 API de MAME usada

- `emu.romname()`.
- `emu.add_machine_frame_notifier(fn)`.
- `manager.machine.devices` — todos los dispositivos de la máquina, para
  encontrar los que tienen `.spaces['program']`.
- `dev.spaces['program']` / `sp:read_u8(dir)` / `sp:write_u8(dir, v)`.
- `sp.map.entries` — tramos del mapa de memoria de un espacio, con
  `.address_start`, `.address_end`, `.read.handlertype`,
  `.write.handlertype`, `.share`.
- `manager.machine.memory.shares` — tabla de *shares* de memoria por
  nombre, cada uno con `.size` y `read_u8`/`write_u8`.
- `manager.machine.ioport:token_to_input_type(token)` / `.ports` /
  `port.fields` / `campo.type` / `campo:set_value(1|0)`.
- `manager.machine:exit()`.

---

## 9. `volcar.lua`

### 9.1 Propósito

Lee de la RAM el bloque de bytes que `hiscore.dat` de MAME declara para un
juego (dirección + longitud) y lo imprime en hexadecimal por `print()`.
Sirve para **rescatar** la tabla de puntuaciones de fábrica de un juego que
nadie ha jugado todavía, porque el plugin `hiscore` de MAME sólo escribe su
fichero `.hi` cuando la tabla en RAM **cambia** respecto a como estaba al
arrancar — un juego virgen no genera nunca ese fichero, y sin datos no hay
ni forma de deducir el formato de la tabla ni de tener la referencia "de
fábrica" para descartar nombres ficticios más adelante (ver `puntajes.py`,
fuera del alcance de este documento).

### 9.2 Cómo se invoca

`-autoboot_script` de un solo uso, pensado para lanzarse a mano o desde un
script externo (`puntajes.py --fabrica`, no documentado aquí) con estas
variables de entorno:

- `GA_D_BLOQUES` — especificación de qué volcar, formato
  `"cpu,espacio,dir_hex,largo_hex;cpu,espacio,dir_hex,largo_hex;..."`
  (varios bloques separados por `;`, para juegos cuya tabla de
  puntuaciones está repartida en más de un sitio).
- `GA_D_FRAME` — en qué frame volcar (defecto `2400`, para dar tiempo a
  que la placa termine de arrancar y, si el plugin `hiscore` está activo,
  a que reponga la tabla de fábrica en la RAM).

### 9.3 Recorrido de la ejecución

Un único `emu.add_machine_frame_notifier` cuenta frames; al llegar
exactamente a `CUANDO` (no antes ni después — comparación de igualdad, no
de "mayor o igual"), recorre cada especificación en `GA_D_BLOQUES`
separada por `;`, la parte con un patrón en cuatro grupos
(`cpu`, `espacio`, `dir`, `largo`), y resuelve el espacio de memoria: si el
segundo campo es del tipo `"<nombre>/share"`, usa
`manager.machine.memory.shares[nombre]`; si no, usa
`manager.machine.devices[':' .. cpu].spaces[espacio]` — el mismo convenio
que ya vimos en `memoria.lua` y que copia literalmente el que usa el
plugin `hiscore` de MAME (`init.lua:129`, según el comentario). Lee byte a
byte con `sp:read_u8(base+i)` y los concatena en hexadecimal de dos
dígitos. Imprime una única línea `[volcado] <hex...>` de todos los bloques
concatenados, hace `io.stdout:flush()` (para que la salida no se quede en
el búfer si algo mata el proceso justo después) y sale con
`manager.machine:exit()`.

### 9.4 API de MAME usada

- `emu.add_machine_frame_notifier(fn)`.
- `manager.machine.memory.shares[nombre]` / `manager.machine.devices[tag]`
  / `.spaces[espacio]` / `sp:read_u8(dir)`.
- `manager.machine:exit()`.

---

## 10. `poner_1c1c.lua`

### 10.1 Propósito

Pasada de configuración de un solo uso: deja el DIP de tarifa de un juego
en 1 moneda = 1 crédito, de una vez, para que **desde el primer arranque**
(no sólo desde el segundo, como hace la compensación de `creditos.lua`
dentro de una partida) el número de créditos que ve el frontend sea exacto.

### 10.2 Cómo se invoca

`-autoboot_script` de un solo uso, normalmente lanzado desde
`poner_1c1c.sh` recorriendo la lista completa de juegos. Carga
`tarifa.lua` con `dofile` (resolviendo `MI_DIR` con
`debug.getinfo(1, 'S').source`, igual que `creditos.lua`) y reutiliza
íntegramente su análisis — no repite ninguna lógica de interpretación de
DIP.

No tiene variables de entorno propias.

### 10.3 Recorrido de la ejecución

1. `T.buscar_dip()`. Si no hay DIP de tarifa: `estado=sin-dip` y termina
   (el chunk simplemente hace `return`, no hay `manager.machine:exit()`
   explícito en este script — MAME sigue corriendo la máquina
   normalmente tras el autoboot, a diferencia de `buscar_creditos.lua` y
   `volcar.lua`, que sí fuerzan la salida).
2. `T.ajuste_actual(dip)` da el texto actual; si `T.partir(antes)` dice que
   es partida gratis, se respeta sin tocar nada:
   `estado=respeto-gratis`.
3. `T.valor_1c1c(dip)`; si no hay opción de 1C/1C en este juego,
   `estado=sin-opcion`.
4. Si el DIP ya está en ese valor, `estado=ya-estaba`.
5. Si no, se escribe `dip.campo.user_value = valor` y se informa
   `estado=cambiado`, con el texto de antes y de después.

Cada rama termina llamando a `decir(estado, antes, ahora)`, que construye
una línea `1C1C juego=<juego> estado=<estado> antes=[...] ahora=[...]`
(los campos `antes`/`ahora` son opcionales, sólo se añaden si se pasan).

### 10.4 Flujo de datos

Es un consumidor directo de `tarifa.lua`, con exactamente la misma
secuencia de llamadas que usa `fijar_1c1c()` dentro de `creditos.lua`, pero
como programa autónomo en vez de como parte de la lógica de arranque de
cada partida.

### 10.5 Trampas y decisiones no obvias

- **No toca las partidas en modo gratis.** Si alguien puso el juego en
  `Free Play` a propósito, este script lo respeta explícitamente
  (`estado=respeto-gratis`) en vez de sobreescribirlo.
- **El cambio no afecta a la partida en la que se ejecuta este mismo
  script** (la placa ya leyó la tarifa vieja al arrancar), pero sí a
  **todos los arranques siguientes**, porque MAME persiste `user_value` de
  un DIP en el `.cfg` del juego al salir.

### 10.6 API de MAME usada

Ninguna directamente (`emu.romname()` para el nombre del juego); todo lo
demás pasa por `tarifa.lua`, que sí llama a `manager.machine.ioport`.

---

## 11. Los scripts de `pruebas/`

Todos los `prueba_*.lua` de este apartado son programas de consola
independientes: cargan el módulo correspondiente con `dofile('../X.lua')`,
ejecutan un puñado de casos con datos inventados (nunca arrancan MAME), y
terminan con `os.exit(0)` si todo fue bien o `os.exit(1)` si algo falló —
es lo que permite que `correr.sh` los encadene y sume "N ok, M fallos" sin
depender de un framework de pruebas.

- **`prueba_ajustes.lua`** — 12 bloques de comprobaciones sobre
  `ajustes.lua`: lectura del fichero, tolerancia a un fichero inexistente,
  precedencia entorno/juego/defecto/interno, conversión segundos→frames
  (y que la variable de entorno NO se convierta), valores no numéricos
  (banderas), tolerancia a basura en el fichero, insensibilidad a
  mayúsculas en el nombre del juego, el aviso por línea sin separador
  válido, la bandera `nvram`, los dos parámetros de ajuste fino
  (`velocidad`/`segundos`), `negro=0` y el caso `segundos=0`, y el
  ajuste `indicador`.

- **`prueba_aviso.lua`** — 10 bloques (más `7b` y `7c` como sub-casos)
  sobre `aviso.lua`: la cuenta básica de lo que hay dentro, que un START
  ignorado por el juego no pueda gastar un crédito de más, que entrar a
  mirar y salir no moleste, que sin créditos dentro no se frene la salida,
  que la primera salida con monedas metidas sí se frene y la segunda (tras
  la guarda de antirrebote) confirme, que START cancele el aviso, que si
  nadie contesta no se salga, que el crédito gastado con el cuadro puesto
  lo cierre solo (sólo con lectura exacta), que sin dirección conocida el
  aviso no se pueda "escapar" callándose, que el rebote de la tecla de
  salir no cuente como confirmación, que el texto sea gramaticalmente
  correcto en singular/plural y coherente con `se_pierden`, que con
  dirección de memoria el número sea exacto y sobreviva a una lectura que
  falla, y que el texto dependa de si el crédito se cobra al meter o al
  jugar.

- **`prueba_cerrojo.lua`** — 10 bloques sobre `cerrojo.lua`: que con
  monedero la moneda pase y se descuente, que al agotar el monedero se
  eche el cerrojo, que bloqueado se rechace toda moneda adicional (y se
  cuenten los rechazos), que sin monedero se bloquee desde el primer
  frame, que `bloquear`/`soltar` sólo se llamen en el cambio de estado (no
  en cada frame), que al terminar se suelte pase lo que pase y no se
  suelte dos veces, que límites raros (negativos, con decimales, ausentes)
  no lo tumben, que mientras la máquina arranca (`listo=false`) el botón
  esté cerrado aunque haya monedero de sobra, que arrancar sin monedero
  cierre igual por el motivo de arranque, y que el modo `ilimitado` sólo
  cierre durante el arranque y nunca por falta de créditos.

- **`prueba_memoria.lua`** — 9 bloques sobre `memoria.lua`: leer la tabla
  de `creditos.dat` (con comentarios, varios juegos, marca `(cheat)`, marca
  `bcd` con y sin falso positivo por subcadena, y varias copias separadas
  por `+`), que el contador reparta subidas y bajadas correctamente
  (incluyendo saltos de más de un crédito), que un reset de placa (salto
  grande) no se cobre y quede apuntado como "raro", que una lectura que
  falla no tumbe nada y que `dentro()` devuelva `nil` (no 0) cuando no se
  puede leer, que el sincronizador escriba el monedero en el juego y no
  siga trabajando una vez hecho, que si la placa machaca el valor se
  reintente y finalmente se rinda, que una lectura que revienta durante la
  sincronización tampoco lo tumbe, que la placa se deje asentar antes de
  contar (sin contar como consumo lo que pasa durante el asentamiento), y
  que al asentarse se limpien los créditos no pagados sin que esa limpieza
  se cuente como consumo.

- **`prueba_monedero.lua`** — comprobaciones sobre `monedero.lua`: leer y
  escribir la cuenta, que el fichero sea legible por un humano, formatos
  raros (número suelto, sólo saldo, negativos que se recortan, basura que
  se descarta, un fichero cortado a medio escribir del que se salva lo
  legible), que no queden temporales tirados tras escribir, que el
  pulsador cuente flancos y no frames, que el monedero pague por lo que se
  juega y no por lo que se mete (el caso íntegro del "jugador despistado"
  que aporrea la moneda sin que le cueste nada hasta que juega), que la
  cuenta nunca quede negativa, que se puedan devolver créditos cobrados de
  más (sin bajar de cero ni pasar de la base), y que el antirrebote del
  pulsador descarte los rebotes de contacto y cuente sólo las pulsaciones
  reales espaciadas.

- **`prueba_tarifa.lua`** — no usa el arnés `ok`/`igual` de los demás:
  imprime `ok`/`FALLO` directamente por cada caso de una tabla de casos
  fijos. Comprueba `M.partir` contra 19 textos distintos (las tres formas
  reconocidas, `Free Play`, y una lista de textos que **no** deben
  reconocerse como tarifa: `Off`, `Upright`, `"256 (Cheat)"`, `None`, un
  texto de servicio, un número suelto, y las variantes con premio de
  `mwalk`), y `M.con_premio` contra 4 casos. Como se explicó en la sección
  3.2, **no** prueba `M.buscar_dip` ni `M.valor_1c1c`, porque esas dos
  necesitan un `campo` de verdad de MAME.

- **`rescate.lua`** (en `pruebas/`) — no es una prueba unitaria sino el
  disparador de una **prueba de integración** (`rescate.sh`, fuera del
  alcance de este documento): en el frame `GA_D_FRAME` (defecto 1800), para
  cada bloque de `GA_D_BLOQUES` (mismo formato que `volcar.lua`), lee todo
  el bloque, cambia **el último byte** (nunca el primero, que suele ser el
  dígito más significativo y daría una puntuación absurda) alternando entre
  1 y 2, y vuelve a leer todo el bloque para imprimir `antes=` y `despues=`
  en hexadecimal. Cambiar ese byte es precisamente lo que hace que el
  plugin `hiscore` de MAME considere que la tabla "cambió respecto a la de
  fábrica" y decida escribir su fichero `.hi` al salir — o sea, reproduce
  a propósito el disparador real de una partida jugada, sin tener que jugar
  de verdad.

- **`integracion/estado_final.lua`** — no es una prueba en el sentido de
  `ok`/`FALLO`: es un arnés que carga `creditos.lua` de verdad
  (`dofile(MI_DIR .. '../../creditos.lua')`) y, en el frame
  `GA_EF_FRAME` (defecto 1500), imprime el estado del emulador
  (`throttled`, `throttle_rate`, `system_mute`) y cuántos códigos tiene la
  secuencia efectiva de `COIN1`. Se usa para verificar, en un juego que
  reinicia su propia placa durante el arranque (Elevator Action), que el
  mecanismo de `deshaceres` (sección 1.6) deja el emulador con freno normal
  y el botón de moneda con su secuencia intacta al terminar — en vez del
  "sin freno para siempre y botón muerto para siempre" que producía el
  fallo original.

- **`integracion/mame_con_captura.lua`** — el envoltorio que usan las
  pruebas de integración de más alto nivel (`aviso_mame.sh`,
  `integracion.sh`, no documentados aquí) para lanzar MAME con
  `creditos.lua` de verdad y, además: sacar una captura de pantalla en un
  frame concreto (`GA_SNAP`/`GA_SNAP_FRAMES`, usando
  `scr:snapshot(destino)`); **fingir** una moneda del jugador en frames
  concretos (`GA_PRUEBA_MONEDA`), sustituyendo
  `GA_ESTADO.pulso_moneda.leer` por una función que además pulsa la entrada
  real con `set_value` (para que el juego conceda el crédito de verdad, no
  sólo para que nuestra contabilidad se entere); y fingir la tecla de
  salir y el botón de START (`GA_PRUEBA_SALIR`, `GA_PRUEBA_START`)
  sustituyendo `GA_ESTADO.leer_salir`/`leer_start1`. Es el mecanismo que
  permite probar dentro de MAME de verdad sin tener a nadie delante de un
  teclado — con la limitación explícita, anotada en el propio comentario,
  de que sustituir la función de lectura **no** es lo mismo que una
  pulsación física real (para eso hace falta inyectar la tecla a más bajo
  nivel, como se hizo aparte con XTEST para probar el antirrebote de la
  tecla de salir, documentado en `CLAUDE.md`).

---

## 12. Apéndice: chuleta de la API Lua de MAME

Resumen de todas las llamadas de la API de MAME que aparecen en estos
scripts, en un solo sitio, para no tener que ir fichero por fichero:

**Ciclo de vida y frames**
- `emu.romname()` — nombre del set en marcha.
- `emu.time()` — segundos *emulados* transcurridos.
- `emu.add_machine_frame_notifier(fn)` → objeto con `:unsubscribe()`;
  llama a `fn` una vez por fotograma **emulado** (no de reloj de pared).
- `emu.add_machine_stop_notifier(fn)` — se llama cuando la máquina se
  detiene.
- `emu.register_frame_done(fn)` — llama a `fn` tras renderizar cada frame;
  **acumula** suscripciones sin forma de quitarlas (hay que registrar un
  único envoltorio permanente, protegido con una global, y variar lo que
  ese envoltorio hace por dentro).
- `emu.input_seq(seq_opcional)` — crea una copia independiente de una
  secuencia de entrada, o una vacía si no se pasa nada.
- `manager.machine:exit()` — termina la máquina en marcha.
- `debug.getinfo(1, 'S').source` — ruta (con `@` delante) del propio script
  en ejecución; con un patrón se saca el directorio para `dofile` de los
  módulos vecinos.

**Entradas (ioport)**
- `manager.machine.ioport:token_to_input_type(token)` → *tupla*
  `(tipo, jugador)`. Traduce texto (`'COIN1'`, `'START1'`, `'UI_CANCEL'`...)
  a un identificador interno de tipo de entrada.
- `manager.machine.ioport.ports` — todos los puertos de la máquina,
  indexados por etiqueta interna (p.ej. `:IN0`).
- `port.fields` — campos de un puerto, indexados por **nombre ya
  traducido** al idioma de la interfaz (por eso nunca se busca por nombre,
  siempre por `campo.type`).
- `campo.type` / `campo.type_class` — el tipo de entrada; `type_class`
  distingue, entre otros, `'dipswitch'`.
- `campo:set_value(1|0)` — fuerza el valor digital. **Es un OR con el
  estado físico real** (`m_digital_value || seq_pressed(seq())` en el
  código C++ de MAME): `set_value(1)` fuerza a pulsado, pero
  `set_value(0)` **no** bloquea el mando físico si alguien lo tiene pulsado
  de verdad. Para bloquear un control de verdad hace falta vaciar su
  secuencia de entrada, no su valor.
- `campo:input_seq('standard')` — secuencia **efectiva** ahora mismo, con
  `.length` (cuántos códigos la componen; 0 = sin secuencia = no puede
  activarse nunca).
- `campo:default_input_seq('standard')` — la secuencia **por defecto**
  configurada (distinta de la efectiva si el `.cfg` del juego o del
  usuario trae una propia).
- `campo:set_default_input_seq('standard', seq)` — cambia la secuencia por
  defecto. **No** se persiste en el `.cfg` del juego (a diferencia de
  `set_input_seq`/`set_type_seq`, que sí lo hacen y por eso no se usan para
  el cerrojo). `seq()` (la efectiva) cae en `defseq()` **sólo si** la
  secuencia activa es la de por defecto; si el juego trae una secuencia
  propia cargada en `live().seq`, cambiar el defecto no tiene ningún
  efecto visible — de ahí que el cerrojo compruebe siempre que "surtió
  efecto" releyendo la longitud tras aplicarlo.
- `campo.settings` — tabla `valor_numérico -> texto` de las opciones de un
  DIP switch.
- `campo.user_value` — el valor actualmente puesto en un DIP; se lee y se
  escribe, y MAME lo persiste en el `.cfg` del juego al salir.
- `manager.machine.input:seq_pressed(seq)` — si una secuencia de entrada
  concreta está pulsada a nivel físico ahora mismo.
- `manager.machine.ioport:type_pressed(tipo)` — atajo para leer
  directamente la tecla física asociada a un *tipo* de entrada de interfaz
  (se usa para `UI_CANCEL`, `START1`, `START2`).
- `manager.machine.uiinput:reset()` — pone todos los eventos de UI en
  `SEQ_PRESSED_RESET`; el código de MAME que procesa esos eventos, que
  corre **después** en el mismo frame, no los vuelve a marcar como
  pulsados mientras la tecla física siga pulsada. Es el mecanismo para
  "tragarse" una pulsación de UI sin tocar ningún mapeo.
- `manager.machine.input:code_from_token(token)` /
  `:code_to_token(codigo)` / `:code_pressed(codigo)` — leer una tecla
  **cruda** del teclado (o cualquier dispositivo), sin pasar por el
  ioport del juego ni por la UI de MAME. `code_from_token` no falla con un
  token inválido: hay que comprobar la vuelta con `code_to_token` para
  detectar un error de escritura.

**Memoria**
- `manager.machine.devices[tag]` — un dispositivo de la máquina (una CPU,
  normalmente) por su etiqueta (p.ej. `:maincpu`).
- `dev.spaces[espacio]` — un espacio de direcciones de ese dispositivo
  (`'program'`, `'data'`...).
- `sp:read_u8(dir)` / `sp:write_u8(dir, valor)` — leer/escribir un byte.
- `sp.map.entries` — los tramos declarados del mapa de memoria de ese
  espacio: cada uno con `.address_start`, `.address_end`,
  `.read.handlertype`/`.write.handlertype` (`'ram'`, `'rom'`,
  `'delegate'`, `'port'`...) y `.share` (el nombre del *share* que ocupa
  ese tramo, si lo hay).
- `manager.machine.memory.shares` — tabla de bloques de memoria
  compartidos por nombre; cada uno con `.size` y los mismos
  `read_u8`/`write_u8`. Algunos contadores de créditos (Missile Command)
  sólo son accesibles así, porque su CPU no expone ese tramo como `'ram'`
  en el mapa.

**Vídeo y sonido**
- `manager.machine.video.throttled` — si el emulador respeta el reloj real
  (se lee y se escribe).
- `manager.machine.video.throttle_rate` — el factor de velocidad cuando
  `throttled` está activo (1.0 = normal, 2.0 = el doble...).
- `manager.machine.video.frameskip` — cuántos fotogramas se saltan de
  render por cada uno que se pinta (0 = todos; el máximo, 11, es "la otra
  mitad" del *fast forward*, que emula todo pero pinta poco).
- `manager.machine.sound.system_mute` — silenciar/activar el sonido.
- `manager.machine.video:begin_recording(ruta, 'avi')` /
  `:end_recording()` — empezar/terminar una grabación de vídeo (con
  sonido incluido) a partir del fotograma actual, sin tener que grabar
  desde el arranque.
- `manager.machine.screens` — tabla de pantallas de la máquina;
  `scr:snapshot(ruta)` guarda una imagen fija del contenido de **esa
  pantalla** (no incluye ninguna capa de interfaz dibujada aparte).
- `manager.machine.render.ui_container` — el contenedor de dibujo de la
  interfaz de MAME, en coordenadas 0..1 **sin rotar** con la orientación
  del juego (a diferencia del contenedor de una pantalla concreta, que sí
  rota — por eso el texto superpuesto se pinta aquí y no sobre la
  pantalla).
- `contenedor:draw_box(x0, y0, x1, y1, color_borde, color_relleno)` /
  `contenedor:draw_text(x, y, texto, color)` (con `x` = `'center'` para
  centrar horizontalmente) — primitivas de dibujo, colores en formato
  `0xAARRGGBB`.
- `manager.ui:get_string_width(texto)` / `manager.ui.line_height` — medir
  un texto en las mismas coordenadas 0..1 del contenedor de interfaz, para
  ajustar el tamaño de una caja de fondo al contenido real.

**Opciones de MAME**
- `manager.machine.options.entries['nvram_save']:value(false)` — apaga el
  guardado de NVRAM al salir, para la partida en curso (no afecta a la
  carga de una NVRAM ya existente).

---

*Fin del documento.*
