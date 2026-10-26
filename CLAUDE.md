# Sistema de créditos para cabina arcade (GroovyMAME + Attract-Mode Plus)

Contexto traspasado desde otra sesión. Todo lo marcado como **verificado** se
comprobó ejecutando código y mirando capturas de pantalla reales, no de memoria.

**Mapa del proyecto: `docs/ESTRUCTURA.md`** — qué hay en cada directorio, quién
lee qué fichero de configuración y las trampas de sincronización. Este documento
(`CLAUDE.md`) es el *por qué* de cada decisión; `docs/ESTRUCTURA.md` es el
*dónde*.

**Toda la documentación del proyecto vive en `docs/`** (2026-09-13): el mapa
(`ESTRUCTURA.md`), el funcionamiento a fondo de cada script
(`docs/lua.md`, `docs/sh.md`, `docs/py.md`), la explicación detallada de cómo se
localizan las direcciones de RAM de créditos y puntajes
(`docs/direcciones-ram.md`), y los informes técnicos (`puntajes.md`,
`INFORME-CREDITOS-NVRAM.md`). `docs/README.md` es el índice. Sólo `CLAUDE.md`
sigue en la raíz, porque es lo que Claude Code carga como instrucciones del
proyecto. Los `.md` de la raíz y de `extlibs/`, `util/`, `src/`,
`config/modules/` y `config/layouts/` son de Attract-Mode Plus (upstream) y no se
tocan.

## Decisión de Eloy (2026-08-29): monedas de verdad — ES LO QUE HAY AHORA

El flujo de la cabina es el de una recreativa de toda la vida:

1. El jugador **elige el juego** en el frontend. Sin créditos, sin nada.
2. **Mete monedas en la máquina y juega.** Las monedas entran directamente en
   el emulador, como en una placa real.

**El plugin del frontend está desactivado** y `creditos.lua` corre en modo
monedas de verdad (`GA_MONEDERO` apagado por defecto). De todo el sistema sólo
quedan en pie las dos piezas que Eloy quiso conservar, y siguen probadas:

- **El arranque tapado**: pantalla en negro y emulador acelerado mientras la
  placa hace su test, con detección de cuándo está lista de verdad y ajustes por
  juego en `arranque.dat`. Ver «El arranque tapado».
- **El aviso al salir con créditos dentro**: como ahora son monedas de verdad,
  esos créditos son dinero perdido, así que el cuadro avisa de la pérdida.
  Pendiente de Eloy: cambiar la confirmación por una combinación de botones que
  se enseñe en pantalla; por ahora sigue siendo pulsar salir dos veces.

**Nada de lo anterior se ha borrado.** El sistema completo del monedero
compartido (cerrojo, cobro al meter, devolución, contador físico) está en la
rama **`monedero-frontend`** (la parte del frontend) y en
**`creditos-monedero-frontend`** (la de MAME, que era un repo aparte hasta que
se fundieron el 2026-09-03).
Encenderlo otra vez son dos interruptores: `GA_MONEDERO=1` y activar el plugin.
Sus pruebas siguen pasando, porque los escenarios lo piden explícitamente.

Dos cosas que quedan sueltas con este flujo, por si se quieren retomar:

- **`contador_arduino.py` y el contador físico se quedan sin nada que enseñar**, porque ya
  no hay monedero. La evolución natural sería que mostrara los créditos que hay
  **dentro del juego**, que para los juegos de `creditos.dat` se leen de la RAM.
- **La tarifa del DIP ahora decide dinero de verdad.** Sigue forzada a 1 moneda
  = 1 crédito (`GA_TARIFA`); si se quiere otra cosa, es ahí.

## Modo manual y monedero compartido (históricos, apagados)

Dos diseños anteriores, hoy superados por «monedas de verdad» (ver arriba):

- **Modo manual** (2026-08-24): el plugin del frontend desactivado, se entra sin
  créditos y el jugador mete monedas con el botón. El razonamiento sigue siendo
  bueno: la ranura de MAME funciona en el 100% de los juegos, mientras que pasar
  créditos desde el frontend solo es exacto donde se conoce la dirección de RAM.
- **Monedero compartido / visible en el Arduino** (2026-08-28): el plugin guarda
  los créditos, el Arduino los enseña, el jugador los mete pulsando la moneda y el
  cerrojo bloquea el botón al llegar a 0. Cobraba al **meter** (`GA_COBRO=meter`),
  porque el contador físico hacía visible el gasto.

El sistema completo (cerrojo, cobro al meter, devolución, contador físico) se
conserva en las ramas **`monedero-frontend`** (frontend) y
**`creditos-monedero-frontend`** (MAME). Se reactiva con `GA_MONEDERO=1` y el
plugin encendido; sus pruebas siguen pasando.

## Objetivo

Emular la experiencia de una recreativa de monedas:

1. En el frontend (Attract-Mode Plus), un botón añade créditos y se ven en pantalla.
2. Al elegir juego, se lanza GroovyMAME insertando automáticamente esos créditos.
3. Opcional: bloquear controles mientras entran las monedas.

## Son DOS lenguajes, no uno

| Pieza | Lenguaje | Estado |
|---|---|---|
| Plugin de Attract-Mode Plus | **Squirrel** (`.nut`) | **escrito y probado con maqueta** |
| Inserción de monedas en MAME | **Lua** | **funcionando y verificado en pantalla** |

Attract-Mode NO usa Lua. Es un error fácil de cometer.

## Estado actual

- [x] GroovyMAME compilado: `~/Dev/arcade/groovymame_src/mame` (417 MB)
- [x] Avisos de emulación eliminados (ver más abajo)
- [x] Inserción de créditos funcionando y verificada con captura
- [x] Plugin Squirrel escrito: `config/plugins/Creditos.nut` (sin commitear)
- [x] Tarifa 1C/1C resuelta: `poner_1c1c.sh` + compensación automática
- [x] Dependencias de AM+ instaladas — 8 de 8
- [x] **AM+ compilado**: `attractplus` v3.2.3, 44 MB, en la raiz del repo
- [x] **Plugin probado dentro de AM+ de verdad**, con capturas: marcador encima
      del layout, monedas llegando a MAME y select bloqueado sin creditos
- [x] **Monedero compartido**: el monedero paga por partida jugada, no por
      moneda metida, y el frontend recoge el saldo bueno al volver
- [x] **Cuadro de aviso** al salir dejando creditos dentro, verificado en
      pantalla (`aviso.lua`)
- [x] **Creditos leidos y escritos en la RAM del juego** en los que estan en
      `creditos.dat` (10 de 19, verificados en pantalla): el frontend y el juego marcan el mismo numero.
      `buscar_creditos.sh` encuentra la direccion ejecutando el juego, y
      `importar_cheats.py` saco otras 4.958 de la coleccion de cheats de MAME

Sobre SFML, la preocupacion era infundada: **AM+ 3.2.3 compila su propia SFML
3.0.1 desde `extlibs/SFML`** (en el Makefile, `USE_SYSTEM_SFML=1` esta
comentado, linea 57). La 2.6.1 del sistema no se usa. Lo confirma
`./attractplus --version`: `SFML 3.0.1`.

Compilar, unos 2 minutos con 12 nucleos:

```bash
cd ~/Dev/arcade/attractplus
PATH=/usr/lib/ccache:$PATH mold -run make -j10
```

## Cómo se pasan los créditos al juego: el monedero

El frontend no puede poner variables de entorno al emulador: AM+ lanza con
`fork()` + `execvp()` (`src/fe_util.cpp:1696-1734`) y no hay API para tocar el
entorno del hijo. Solución: un fichero compartido, `$HOME/.attract/creditos.txt`,
que **leen y escriben las dos partes**:

```
saldo 4        <- lo que le queda al jugador
inserta 1      <- lo que MAME mete en la partida al arrancar
```

```
botón de moneda -> Creditos.nut cuenta en fe.nv -> al lanzar escribe el fichero
-> creditos.lua mete "inserta" y va descontando de "saldo" las monedas que el
jugador mete durante la partida -> al volver, el plugin lee "saldo"
```

- `inserta` se consume **en cuanto se lee** (MAME lo pone a 0), o un segundo
  arranque regalaría créditos.
- Las dos partes escriben a un temporal y renombran: en POSIX el renombrado es
  atómico, así que matar MAME a media escritura no deja la cuenta a medias.
- Si el fichero no se puede leer al volver, el plugin **deja el contador como
  estaba**. Devolver 0 ahí sería la peor respuesta posible.
- `Transition.ToGame` es el sitio correcto para escribir: `pre_run()` lo dispara
  (`src/fe_present.cpp:1789`) y justo después viene el `execvp`
  (`src/main.cpp:390`). Para leer, `Transition.FromGame`.
- El fichero lleva **créditos, no monedas**. La conversión a monedas la hace
  `creditos.lua`, que es el único que puede leer el DIP de tarifa del juego ya
  cargado. El plugin no toca tarifas: si compensara también, se descontaría dos
  veces. (Ese error estuvo escrito y se quitó.)
- Nada de generar un `.lua` por lanzamiento, como ya decía este documento.

Ficheros en `creditos/`: `creditos.lua`, `monedero.lua`
(la cuenta), `tarifa.lua` (el DIP), `poner_1c1c.lua` + `.sh` (pasada única),
`groovymame.cfg` (emulador de ejemplo), `README.md`, `pruebas/`.

## Los créditos que se quedan dentro del juego

Averiado y corregido en dos pasadas, 2026-08-23 y 2026-08-24.

**Primer agujero.** Con el modo «Todos» el plugin metía el monedero entero en la
partida: quien insertaba 5 créditos, jugaba una y salía, perdía los 4 restantes.
El modo por defecto es ahora «Solo el coste».

**Segundo agujero, el que dolía de verdad.** El monedero cobraba al *meter* la
moneda. Un jugador que entra a Pac-Man y se pone a pulsar la moneda creyendo que
acumula créditos para otros juegos se vaciaba el monedero y encima lo perdía al
salir. La regla es ahora:

> **El monedero paga por lo que se JUEGA, no por lo que se mete.**

**Ojo: el monedero compartido del 2026-08-28 (hoy apagado) invertía esta regla a
propósito** (cobrar al meter), porque el contador físico hacía visible el gasto.
Ver «Modo manual y monedero compartido (históricos, apagados)» antes de tocar
nada aquí.

Meter una moneda dentro de la partida sólo mueve un crédito del monedero a la
máquina; lo que descuenta es pulsar START, que es cuando el juego se lo lleva.
Así, `saldo = base - consumido`, con `base` = saldo al lanzar + lo insertado.
Las monedas que el jugador mete durante la partida se cancelan solas en esa
cuenta: si no las gasta, siguen siendo suyas.

Detalle deliberado del reparto de responsabilidades: **el plugin cobra el
crédito del lanzamiento nada más lanzar, y `creditos.lua` lo devuelve si no se
gastó**. Si el script Lua no llegara a ejecutarse, la cuenta queda cobrada, que
es el error seguro. Nunca al revés.

Lo que **no tiene solución general**: los créditos que quedan dentro de la
máquina al salir. MAME no tiene un concepto de «créditos», viven en la RAM del
juego y la dirección cambia con cada placa. Ya no cuestan dinero al jugador,
pero se quedan ahí; de eso avisa el cuadro de la sección siguiente.

Sí tiene solución **juego a juego**, y es la de la sección «Dónde guarda cada
juego sus créditos».

**El botón de moneda al llegar a 0: resuelto** (2026-08-28). Antes, con el saldo
a cero, seguir pulsando la moneda daba créditos gratis, porque la entrada la lee
MAME directamente. Ahora hay cerrojo, ver «El cerrojo del botón de moneda».

## El contador físico de la cabina (Arduino) — fundido en `moneyBank.py`

El `contador_arduino.py` + `Arcade.ino` originales (que enseñaban el `saldo` del
monedero por el puerto serie) se **fundieron en `moneyBank.py` +
`arduino/cabina/cabina.ino`** el 2026-10-05: un solo demonio y un solo sketch,
porque abrir el puerto reinicia la placa y dos demonios se la reiniciarían.
Ver «El monedero como servicio». Lecciones que siguen valiendo y costaron una
iteración cada una:

- Se **reabre el fichero en cada lectura** (el monedero se reemplaza entero con
  `rename`; con el descriptor abierto se leería el viejo para siempre).
- El **puerto se abre una sola vez** (abrirlo reinicia la placa, de ahí los 3 s
  de espera antes del primer envío).
- `lastCredit = None` al reconectar (la placa reinició mostrando 0 y el saldo no
  cambió: sin esto el contador se congela tras un tirón de cable).
- Solo se apunta el crédito si el envío devolvió `True`.
- El registro **no repite el mismo error** pero anota `recuperado` al arreglarse.

## El monedero como servicio: `arduino/moneyBank.py` (2026-10-02)

El demonio NUEVO del monedero (distinto del `contador_arduino.py`): lee
`~/.attract/monedero_switch` —que escribe `creditos.lua` (`1` juego en marcha,
`0` menú/arranque)— y enciende o apaga por el puerto serie el **relé del
monedero**, para que la ranura sólo acepte monedas dentro de una partida. Lo
escribe Eloy; **no se toca desde aquí**, sólo se lee y se despliega.

Arranca solo con la cabina mediante un **servicio de usuario de systemd**
(`monedero.service`), que lo instala `instalar.sh` con la tarea **`monedero`**
(marcada por defecto sólo en GroovyArcade). La tarea: instala `pyserial`, mete al
usuario en el grupo del puerto serie (`uucp` en Arch, `dialout` en el resto),
escribe `~/.config/systemd/user/monedero.service` con rutas absolutas de la
máquina, lo activa y pone `enable-linger` para que viva desde el arranque sin
login interactivo.

**Fundido con `contador_arduino.py` el 2026-10-05**, a petición de Eloy: un solo
demonio y un solo sketch (`arduino/cabina/cabina.ino`). Tenía que ser así: el
puerto lo abre un solo proceso, y abrirlo **reinicia la placa**, así que dos
demonios se la reiniciarían el uno al otro. Como los dos mandaban un número a
secas, cada mensaje lleva ahora una letra delante: **`M0`/`M1`** para el relé y
**`C<n>`** para el saldo de `creditos.txt`, que enseña el display de 7 segmentos
(un dígito, clavado en 9). Se manda sólo lo que cambia, y todo otra vez al
reconectar. El relé pasó del **pin 2 al 9**, porque el 2 es ahora el segmento A
del display (pines 2-8). El display es de ánodo común (`ANODO_COMUN 1`).

**El display enseña los créditos de DENTRO del juego, no el saldo.** El primer
intento mandaba el `saldo` de `creditos.txt`, y con monedas de verdad ese fichero
**no existe**: Eloy jugaba con 3 créditos y el display no se movía. Ahora
`creditos.lua` escribe `~/.attract/creditos_juego` (un número, atómico, sólo al
cambiar; `GA_CREDITOS_JUEGO=off` lo apaga) con `e.aviso.dentro()` — el mismo
número del cuadro de salida: exacto en los juegos de `creditos.dat`, estimado por
monedas y START en el resto. El demonio lo manda mientras MAME corre; en el menú
manda el `saldo` si hay monedero, y si no, 0. Verificado en Pac-Man metiendo tres
monedas desde Lua: el fichero sube 0→1→2→3.

Dos cosas comprobadas que importan:

- **El `pgrep -x mame` del demonio sí acierta en la cabina**: el `.cfg` del
  emulador lanza `@MAMEDIR@/mame`, o sea un binario de basename `mame`, no
  `groovymame`. Si algún día se cambiara el ejecutable a `groovymame`, el relé se
  quedaría apagado durante las partidas y habría que ajustar el demonio.
- Los logs del demonio (`arduino/logYYYY-MM-DD_HH:MM:SS.txt`) van ignorados por
  git (`.gitignore`), y el `WorkingDirectory` del servicio es `arduino/`, así que
  es donde caen.

## El arranque tapado, y el agujero del jugador pillo

Encontrado por Eloy el 2026-08-28 probando la cabina: *«si soy pillo y empiezo a
pulsar el botón de créditos apenas comienza, el plugin regala créditos»*. Tenía
razón y el diagnóstico también era suyo: **la culpa era del retardo**.

**El agujero.** Con `-autoboot_delay 6`, durante esos seis segundos
`creditos.lua` **todavía no existe**: no hay cerrojo, no hay contador de
monedas, y la entrada de moneda la lee MAME directamente. Todo lo pulsado ahí
era gratis y además invisible para la cuenta.

**El arreglo de fondo: `-autoboot_delay 0`.** Ese retardo era un requisito del
diseño viejo, cuando el script **insertaba** las monedas y la placa aún estaba
en su test de RAM/ROM. En el diseño de la hucha no se inserta nada, así que el
motivo desapareció. Comprobado arrancando en el frame 0: encuentra COIN1, lee el
DIP de tarifa, monta el cerrojo y localiza la dirección de la RAM. **Todo
funciona sin esperar.**

Pero arrancar en el frame 0 destapa dos cosas nuevas, y las dos hay que tratar:

**1. La RAM del juego todavía es basura.** Sin esperar, el byte de los créditos
de Pac-Man leía 176. De ahí `GA_ASENTAR` (180 frames): mientras se asienta, el
contador **sólo toma nota, no cuenta**, y `dentro()` devuelve `nil` en vez de un
número inventado — importa, porque si no el cuadro de salida anunciaría «DEJAS
176 CREDITOS DENTRO».

Al terminar el asentamiento se hace un **barrido**: los créditos que la máquina
traiga puestos y no estén pagados se quitan (`GA_LIMPIAR`). Cubre lo que la
NVRAM guardó de la sesión anterior y cualquier moneda que se colara. Una
recreativa arranca sin créditos. **Sólo se escribe en direcciones comprobadas**:
en las importadas de la colección de cheats nunca.

Cuidado con el barrido: **lo que el jugador haya metido mientras la placa se
asentaba es suyo** y ya se le cobró, así que sólo se quita lo que sobra por
encima de `GA_ESTADO.metidos`. Hay una prueba para eso (`6d`).

**2. La placa ignora las monedas mientras arranca.** Esto es lo que vio Eloy con
su idea de acelerar el arranque, y es un segundo agujero, del signo contrario:
cobrarle al jugador un crédito que el juego tira a la basura. De ahí el
**arranque tapado**:

- El cerrojo tiene una segunda razón para estar echado (`cerrojo.listo`), y
  pulsar la moneda ahí sale con «ESPERA, LA MAQUINA ESTA ARRANCANDO».
- La pantalla se pone **en negro y sin ningún texto**. **Verificado con
  captura.**
- El emulador va sin freno (`video.throttled = false`) y mudo
  (`sound.system_mute`), así que el arranque dura un suspiro de tiempo real.
  `GA_TURBO=0` lo desactiva. Los ajustes se guardan y se restauran.

### Cuándo termina el arranque: NO puede ser un plazo fijo

Eloy volvió con el fallo el 2026-08-28: con la ventana fija de 4 segundos, en un
juego que tarda más el cerrojo se abría antes de tiempo y las monedas volvían a
perderse. Tenía razón — cada placa tarda lo suyo.

**Medido**, trazando el byte `4e6e` de Pac-Man frame a frame (y con el
notificador en una global, que si no **el recolector de basura se lleva la
suscripción** y la traza se corta en el frame 90 sin avisar):

| frames | contador | qué pasa |
|---|---|---|
| 1-90 | 3, 10, 1, 8, 15, 144, 112… | test de RAM, patrones |
| 90-250 | **176, quieto** | sigue arrancando |
| 250+ | **0** | la placa terminó |

Lo importante es la fila del medio: **«lleva un rato quieto» NO sirve como señal
de que esté lista.** La RAM sin inicializar también está quieta, y con esa regla
el botón se abría en el frame 302 con la placa a medias. La señal buena es que
el contador esté **a CERO** y se quede: para Pac-Man, listo en el frame 370
(250 + 120 de confirmación), y cuadra con la medición.

Segunda regla, para juegos con NVRAM que arrancan con créditos de la sesión
anterior y nunca pasan por cero: quieto **mucho** más rato (3×). El plazo es
largo a propósito, porque la meseta de 176 de Pac-Man dura 160 frames y no debe
colarse por ahí.

Y una trampa que costó una pasada: **el propio barrido contaminaba la
detección.** Escribía 0 en el frame 180 y entonces «lleva 120 frames a cero» era
mentira, nuestra. Por eso el asentamiento del contador ya no va por frames
cuando hay arranque tapado: lo cierra `fin_del_arranque()` llamando a
`memoria.asentar_ya()`, y el contador de frames se queda sólo como red **por
detrás** del tope, nunca por delante.

En juegos sin dirección conocida no hay nada que mirar y sólo queda el reloj
(`GA_ARRANQUE_SIN`, 900 frames). Se espera bastante más a propósito: con el
emulador sin freno no cuesta tiempo real, y cobrar por una moneda que el juego
tira es peor que un arranque largo.

### La red de verdad: si la moneda no llega, se devuelve

Ninguna detección es perfecta, así que hay una segunda red que no depende de
adivinar cuándo arranca la placa: **al cobrar una moneda se apunta el valor del
contador, y si en `GA_COMPROBAR` frames (90) no ha subido, se devuelve el
crédito** (`monedero.lua`, `c.devuelve`).

Se cobra primero y se devuelve después, y no al revés, por el mismo motivo que
en el lanzamiento: si algo se cae por el camino, el error seguro es tener
cobrado de más, nunca regalar créditos. Y si no se puede leer la RAM no se
devuelve nada, por lo mismo.

Detalle: se guarda el **máximo** visto del contador, no el último. Si el jugador
le da a START durante ese segundo y medio, el contador baja, y sin eso
creeríamos que la moneda nunca llegó.

**Verificado en MAME** (escenario `6g`): moneda en el frame 200 con la placa aún
arrancando, monedero 5 → 4 al cobrarla → 5 otra vez a los 90 frames.

API verificada: `manager.machine.video.throttled`, `.throttle_rate` y
`manager.machine.sound.system_mute` **se leen y se escriben** desde Lua
(`luaengine.cpp:2199-2200` y `:2219-2225`).

**Probado reproduciendo el agujero** (`aviso_mame.sh`, escenarios 6c a 6e):
pulsar la moneda en los frames 5, 25, 45 y 65 con el monedero a cero da cuatro
rechazos, cero entradas y el barrido limpia la máquina; con el monedero lleno,
pulsar durante el arranque tampoco cuesta nada.

Efecto secundario en las pruebas: los frames simulados van 360 más adelante que
antes, porque el script ya no espera 6 segundos.

## El rebote de la chauchera

Encontrado por Eloy el 2026-08-29: *«al presionar el botón de créditos como
loco, a veces da más créditos de los que debería»*. Su primera idea fue mover la
gestión del botón a un backend en C o Python. **No era un problema de
arquitectura, era rebote de contactos**, y se habría ido con él al backend.

Una chauchera es un microinterruptor mecánico: al cerrar, sus contactos abren y
cierran varias veces durante unos milisegundos. El plugin muestrea una vez por
fotograma (`feVM.tick()`, `main.cpp:1308`), así que ese rebote se lee como
varias pulsaciones completas y una moneda da tres créditos.

El arreglo es antirrebote por tiempo, pero **con valores distintos en cada lado,
porque las dos entradas son cosas distintas** (aclarado por Eloy el 2026-08-29):

| | entrada | qué es | valor |
|---|---|---|---|
| Frontend | chauchera | **monedas de verdad** | 40 ms |
| MAME | botón de créditos | lo pulsa una persona | 8 frames (~130 ms) |

- **Plugin**: `moneda( ttime )` descarta un crédito si han pasado menos de
  `antirrebote` ms desde el anterior, y lo anota en el log. Ojo con `ttime`: al
  recargar el layout vuelve atrás, y eso se detecta para no comerse la siguiente
  moneda de verdad.
- **`monedero.lua`**: `M.pulsador(leer, hueco)` ignora flancos durante `hueco`
  frames.

**Por qué 40 ms y no 150 en el frontend.** Ahí no se trata de limitar el ritmo:
entran monedas de verdad y todas tienen que contar. Y hay una trampa —
**muchas chaucheras mandan varios pulsos por moneda** (una de 500 puede mandar
cinco, separados unos 100 ms). Un antirrebote de 150 ms se comería cuatro de los
cinco. 40 ms mata el rebote de contactos, que dura menos de 20 ms, y deja pasar
el tren entero. Hay prueba para eso (`23b`).

En el botón de MAME sí interesa el plazo largo: ahí lo pulsa una persona y no
hay monedas físicas que perder.

Lo que sí acertaba la idea del backend: hoy la lógica vive en dos sitios. Si
algún día se quiere un único dueño, **el sitio bueno es el Arduino**, no un
proceso más — un microcontrolador muestrea a kilohercios y ve el rebote entero.
Pero eso es un proyecto de cableado, no un parche para este fallo.

## Ajustes de arranque por juego (`arranque.dat`)

`ajustes.lua` + `arranque.dat`, pedidos por Eloy el 2026-08-29 y **rectificados
por él el 2026-09-01**: son dos parámetros y sólo dos, y **no dependen de
`creditos.dat`**.

```
defecto  velocidad=0 segundos=5
frogger  velocidad=200 segundos=2
mwalk    nvram=0 segundos=10
```

- **`velocidad`** — a qué velocidad corre el emulador mientras carga, en
  **porcentaje**: `100` normal, `200` el doble, `1000` diez veces, `0` sin
  freno. Se aplica a `video.throttle_rate` (verificado: `rate=2.0` durante el
  arranque y `1.0` después).
- **`segundos`** — cuánto dura eso. **Son segundos DEL JUEGO** (frames de
  emulación), no de reloj de pared, y es la confusión natural de este ajuste:
  acelerar el emulador no tapa más carga, tapa la misma en menos espera. Con
  `segundos=5 velocidad=500` la pantalla está en negro **un segundo real**.
  Por eso el log enseña los dos: `5.0 s de juego, emulador al 500% -> unos 1.0 s
  de espera real`. `arranque` se sigue aceptando como sinónimo.

  Medido en Simpsons, 5 s de juego según la velocidad: 100% → 5,7 s reales;
  200% → 3,2 s; 500% → 1,7 s; sin freno → 1,0 s.

  **Y `segundos=0` desactiva el ajuste entero**, velocidad incluida: la
  velocidad se aplica *durante* esa ventana, y sin ventana no hay nada. Eloy
  cayó ahí el 2026-09-01 poniendo 0 segundos precisamente «para ver el cambio de
  velocidad». Ahora el script lo avisa por el log.
- **`negro=0`** — acelera igual pero **no tapa la pantalla**. Es la forma de ver
  el efecto de la velocidad mientras se ajusta un juego. Medido en Tapper con
  `segundos=10`: 14,9 s reales al 100% y 3,7 s al 500%.
- **`indicador=1`** — pinta `>> CARGANDO AL 300%` arriba a la derecha mientras
  la emulación va acelerada. Apagado por defecto: en una cabina no pinta nada,
  es para ajustar. **Verificado con captura** en los tres estados: sobre el
  juego con `negro=0`, sobre la pantalla negra, y desaparecido al terminar.
- `nvram=0` — ese juego no guarda su NVRAM (ver la sección de la NVRAM).
- `auto=1` — **opcional y apagado**: en vez de usar los segundos tal cual, se
  alarga solo hasta detectar que la placa está lista.

**El error de diseño que Eloy corrigió**, y conviene no repetirlo: yo hice la
detección automática **por defecto**, y la única señal que tenía para saber si
la placa estaba lista era el contador de créditos del juego — que vive en
`creditos.dat`. Eso acopló el ajuste fino de la carga con la tabla de créditos,
que son cosas distintas. Ahora la duración la pone el usuario y la detección es
un extra que hay que pedir.

**Los tiempos del fichero van en SEGUNDOS**, que es como piensa una persona;
dentro se pasan a frames. **Las variables de entorno siguen en frames**, que es
como estaban antes y como las usan las pruebas — cambiarlo habría roto todos los
escenarios sin avisar.

Precedencia: **entorno > línea del juego > línea `defecto` > valor interno**.

Para saber cuánto necesita un juego: lanzarlo con `GA_VERBOSO=1` y mirar
«arranque terminado en el frame N»; entre 60 son los segundos.

**No hace falta Python ni C para esto.** El script ya lee dos ficheros `.dat`
con `io` de Lua, y `emu.romname()` da el nombre del set. Un proceso más sólo
añadiría un modo de fallo.

## El cerrojo también sin monedero, y los créditos de la NVRAM

Tres fallos que trajo Eloy el 2026-08-29 probando la cabina con monedas de
verdad.

**1. Q*bert con 52 créditos.** Pulsar el botón de moneda mientras el juego
carga los acumulaba. La causa: el cerrojo sólo se montaba **si había monedero**,
y en el flujo nuevo no lo hay. Ahora se monta siempre, con `ilimitado = true`
cuando no hay monedero: no aplica ningún límite, pero sí tiene el botón **cerrado
mientras la placa arranca**, que es lo único que hacía falta. Prueba `9b`.

**2. Tapper arrancaba con 8 créditos.** Su dirección estaba en `creditos.dat`
marcada `# (cheat)`, o sea importada de la colección, y **en las importadas
nunca se escribe** — así que el barrido no podía limpiar lo que su NVRAM
guardaba de la sesión anterior.

Se comprobó a mano, que es lo que faltaba para ascenderla: la NVRAM traía 6,
escribir 0 en `e011` se queda puesto, y una moneda lo sube 0→1. Con la marca
`(cheat)` quitada, el barrido funciona: `trae 8 credito(s) y solo 0 estan
pagados: quito el resto`, y el arranque siguiente empieza en 0.

Ojo con el detector de «placa lista» en estos juegos: el contador de Tapper vale
8 **desde el frame 3** y nunca pasa por cero, así que la regla del cero no sirve
y entra la segunda, la de «quieto mucho rato» (3×`GA_ESTABLE`). Termina en el
frame 363. Por eso esa segunda regla existe.

**Y una advertencia para el resto de juegos importados:** cualquier otro con
NVRAM y dirección `(cheat)` tendrá el mismo problema. La comprobación es la de
arriba y se hace en un minuto: escribir 0, meter una moneda y ver si sube.

**3. New Rally-X «no muestra el puntaje»: no es nuestro.** Comprobado:
`-verifyroms` dice `romset nrallyx is good`, el driver es `status="good"`, el
parche de avisos sólo toca dos ficheros de `ui/` (que no pueden cambiar el
bitmap del juego), y capturando **sin nuestro script** el marcador **parpadea**:
en blanco en el frame 1800 y con los `00` en el 1810. Es el modo atracción
normal de Namco.

## Juegos que reinician la placa: el script se ejecuta dos veces

Encontrado por Eloy el 2026-08-29 en Elevator Action: *«el emulador no vuelve a
su clock original y no permite agregar créditos»*. Los dos síntomas, una sola
causa.

**Elevator Action reinicia la placa durante el arranque, y MAME vuelve a
ejecutar el `-autoboot_script`.** Medido: dos «encontrado COIN1» en el mismo
lanzamiento. Y lo que lo hace venenoso: **las globales de Lua SOBREVIVEN al
reinicio** (comprobado con un contador).

Así que la segunda ejecución guardaba como «estado original» lo que había
dejado la primera:

| | throttled | mute | secuencia de la moneda |
|---|---|---|---|
| **Antes del arreglo** | `false` (sin freno) | `true` | **0 códigos** (botón muerto) |
| **Después** | `true` | `false` | **3 códigos** |

O sea: al terminar su arranque restauraba «sin freno» y «moneda bloqueada»,
para siempre.

**El arreglo:** `GA_ESTADO.deshaceres`, una lista de funciones que sabe deshacer
todo lo que la ejecución tocó (velocidad, silencio, secuencia de la moneda,
suscripción al notificador). Si al arrancar ya existe un `GA_ESTADO`, se
ejecutan **antes de tomar nota de nada**.

Tres detalles que costaron pensarlos:

- **Las funciones de deshacer capturan copias locales**, no `GA_ESTADO`: cuando
  se ejecutan, la global ya es la de la ejecución siguiente.
- **Hay que cancelar el notificador viejo** (`sub:unsubscribe()`, expuesto en
  `luaengine.cpp:987`). Si no, `por_frame` correría **dos veces por frame** sobre
  el estado nuevo, porque lee `GA_ESTADO` en cada llamada.
- **`emu.register_frame_done` ACUMULA callbacks** y no hay forma de quitarlos
  (`luaengine.cpp`, `register_function`: hace `add`, no `create_named`). Por eso
  el pintor se registra una sola vez, con un envoltorio que llama al del estado
  vigente.

Prueba permanente: `aviso_mame.sh`, escenario 10, con `estado_final.lua`.

## Los créditos que la NVRAM guarda entre sesiones

Traído por Eloy el 2026-08-29 en un fichero de roms problemáticas: Michael
Jackson con 9 créditos, Root Beer Tapper con 9, y en Tapper *«el texto de la
parte inferior se ve distorsionada y mal escrita»*.

**El origen es el mismo en los tres: la NVRAM del juego guarda los créditos** y
la sesión siguiente arranca con ellos. Verificado con capturas: Moonwalker
enseña `CREDITS 7` en su pantalla de título, y sin su fichero de NVRAM arranca
en `CREDIT 0`.

**El texto distorsionado también era nuestro, y es la parte interesante.** El
barrido escribe 0 en el contador **después** de que el juego haya pintado su
mensaje largo (`CREDIT 6 PRESS 1 OR 2 PLAYER`); al quedarse en el corto
(`INSERT COIN`) su rutina de dibujo no borra lo que sobra y quedan restos.

**Lo que NO se puede hacer: adelantar el barrido.** Lo intenté — barrer en cada
frame del arranque — y rompe la placa: los patrones del test de RAM de Pac-Man
(3, 10, 1, 8, 15…) caen en el rango que se barría, así que le machacábamos el
byte, el test se reiniciaba en bucle y el juego no empezaba hasta el frame 302
en vez del 14. **Nunca escribir en la RAM de una placa que se está
autoprobando.** El síntoma en las pruebas fue indirecto y feo: monedas dadas por
perdidas y devueltas.

**La solución: `nvram=0` por juego en `arranque.dat`.** `creditos.lua` apaga la
opción `nvram_save` de MAME desde Lua (`options.entries['nvram_save']:value(false)`,
verificado). El juego deja de guardar su NVRAM, así que el arranque siguiente es
de fábrica: sin créditos y sin artefacto.

- **El precio: ese juego tampoco conserva sus puntuaciones.** Por eso va por
  juego y no para todos.
- **Hay que borrar el fichero viejo una vez** (`~/.mame/nvram/<juego>/nvram`):
  `nvram=0` evita **guardar**, no cargar.
- Puestos así: `mwalk`, `tapper`, `rbtapper`.

**Y una advertencia: tener NVRAM no significa guardar créditos.** Dig Dug la
usa sólo para la puntuación y arranca en `CREDIT 0`. No apagarla a lo bruto.

De la auditoría de `~/.mame/nvram`, siguen sin cubrir (no están en
`creditos.dat` y no se han comprobado): `ncv2`, `simpsons`, `spaceinv`. Si
alguno arranca con créditos, la receta es la de arriba.

**Un fallo silencioso de `arranque.dat` que costó encontrar.** El fichero se
había corrompido y el separador era un `?` literal en vez de un espacio
(`pacman?arranque=5`). El parser lo tomaba como el nombre del juego, así que
**ninguno de sus ajustes se aplicaba, sin decir nada**. Ahora `ajustes.lua`
avisa de las líneas cuyo nombre contiene un `=`.

## El cerrojo falla en los juegos con mapeo propio de la moneda

Visto el 2026-09-01 en Simpsons. El log lo canta, porque `bloquear()` comprueba
que surtió efecto:

```
AVISO: el cerrojo no ha surtido efecto (la secuencia sigue con 1 codigos).
```

La causa está en `ioport_field::seq()`: devuelve `m_live->seq[tipo]` **si no es
la de por defecto**, y sólo entonces cae en `defseq()`. `set_default_input_seq`
toca `defseq`, así que **no manda cuando el juego tiene una secuencia propia
cargada de su `.cfg`**.

De las roms instaladas, tienen mapeo propio de COIN1: `kungfum`, `pacman`,
`simpsons`. Curiosamente en Pac-Man el cerrojo sí funciona (3 códigos → 0):
su `newseq` es un `JOYCODE` y sin joystick presente MAME no lo aplica, así que
queda la de por defecto. En Simpsons sí está activa (`JOYCODE_1_SELECT`).

Arreglarlo con `set_input_seq` **no es aceptable**: escribe `"NONE"` en el
`.cfg` y ese fichero se guarda antes de los notificadores de salida, así que
salir durante el arranque dejaría la moneda muerta para ese juego.

La salida buena es quitar el mapeo por juego (`Input (this Machine)` en MAME) y
dejar el general, que es el que la cabina usa de todas formas.

## Ms. Pac-Man se pasaba los niveles sola: el Rack Test

Traido por Eloy el 2026-09-06: *«a penas entras, pasa al ready y el nivel se
pasa»*. No era nuestro codigo ni la emulacion: era un **interruptor de la placa
guardado en el `.cfg` del juego**.

La placa de Pac-Man lleva un `Rack Test (Cheat)` que avanza de nivel solo, para
que el tecnico pruebe las pantallas sin jugarlas. En `pacman.cpp:1575` esta en
**`:IN0`, mascara `0x10`** -- pegado a COIN1 (`0x20`) -- y se declara
`PORT_DIPNAME`, asi que **MAME lo guarda en el `.cfg`**:

```xml
<port tag=":IN0" type="DIPSWITCH" mask="16" defvalue="16" value="0" />
```

`0x10` es Off y `0x00` es On, o sea que ese `value="0"` lo tenia **encendido**.

**Medido en la cabina**, metiendo moneda y START desde Lua y sin tocar el mando,
trazando el byte del nivel (`4e13`):

| | frame 720 | 840 | 1680 | 1920 | 2160 |
|---|---|---|---|---|---|
| con el `.cfg` viejo | 0 | **1** | **2** | **3** | **4** |
| corregido | 0 | 0 | 0 | 0 | 0 |

Corregido, las vidas (`4e14`) bajan 3-2-1-0 como debe: Ms. Pac-Man se muere sola
por no moverse, que es lo correcto.

**Arreglarlo es poner el valor de fabrica**, no borrar la linea: al salir limpio
MAME reescribe el `.cfg` y **la quita el solo**, porque ya no difiere del
defecto. El fichero paso de 951 a 835 bytes sin tocarlo mas.

Dos cosas que conviene saber:

- **Se enciende con F1 y se queda.** El campo lleva `PORT_CODE(KEYCODE_F1)` y
  `PORT_TOGGLE`, asi que un F1 despistado con un teclado enchufado lo deja
  puesto para siempre. En una cabina es un fallo mudo y dificil de atribuir.
- **Lo tienen mas juegos**: `pengo`, `jrpacman` y `schick`, en mascaras
  distintas (`0x20`, `0x40`, `0x80`). De los `.cfg` de la cabina solo `mspacman`
  estaba tocado; los otros tres `DIPSWITCH` guardados (`missile`, `wboy`,
  `dlair`) son tarifa y ajustes legitimos.

Al buscarlo se descarto lo nuestro leyendo el codigo, y merece la pena por que:
`tarifa.lua` y `poner_1c1c.lua` solo escriben el DIP cuyos textos parsean como
tarifa, y `Off`/`On` no parsea; y el barrido de `creditos.lua` solo escribe en
`4e6e`.

## El cerrojo del botón de moneda

`cerrojo.lua`, pedido por Eloy el 2026-08-28: *«una vez ingresado en el juego se
pueden agregar créditos infinitos»*. La regla es ahora:

> Durante una partida el jugador puede meter **tantas monedas como créditos
> tenía en el monedero al lanzar** (`SALDO`). Ni una más.

Cuando se acaban, el botón deja de responder y aparece abajo
«SIN CREDITOS. VUELVE AL MENU PARA ANADIR». `GA_CERROJO=0` lo desactiva.

**Cómo se bloquea sin arriesgar el botón**, que es lo delicado. Hay dos APIs y
sólo una sirve:

- `campo:set_input_seq('standard', vacía)` escribe `"NONE"` en
  `live().cfg[seqtype]` (`luaengine_input.cpp:343`), y eso **se guarda en el
  `.cfg` del juego** (`ioport.cpp:2859-2894`). Peor aún: **el `.cfg` se guarda
  ANTES que los notificadores de salida** (`machine.cpp:440` frente a `:480`),
  así que restaurar al salir **no llega a tiempo**. Salir con el cerrojo echado
  dejaría el botón muerto para siempre. **No usar.**
- `campo:set_default_input_seq('standard', vacía)` llama a `set_defseq`, que
  toca `m_seq` y **no toca `live().cfg`**. Y `seq()` cae en `defseq()` cuando la
  secuencia viva es la de por defecto (`ioport.cpp`, `ioport_field::seq`). Es la
  buena.

**Verificado dentro de MAME**, no leído: la secuencia efectiva pasa de 3 códigos
a 0 al bloquear y vuelve a 3 al soltar; `set_value` sigue funcionando (o no
podríamos insertar los créditos del lanzamiento); y saliendo con el cerrojo
echado **a propósito**, el `.cfg` de Pac-Man no tiene ni un `NONE` y queda
idéntico. Aun así el `bloquear()` **comprueba que surtió efecto** y avisa por el
log si no: si un juego trae secuencia propia en `live().seq`, `defseq` no manda.

**El detector de moneda guarda una copia de la secuencia** (`emu.input_seq(...)`,
copia explícita). Dos motivos: si fuera una referencia se vaciaría justo al
bloquear, y teniéndola aparte se detecta la pulsación rechazada y se puede
explicar al jugador por qué no pasa nada.

El cerrojo se ajusta **después** de contar la moneda del frame, para que la
última que le queda al jugador entre y el bloqueo empiece en ese mismo frame.

## Dónde guarda cada juego sus créditos

Idea de Eloy, sacada del plugin `hiscore` de MAME: si no hay concepto general de
crédito, se localiza la dirección una vez por juego y se apunta en una tabla.
`buscar_creditos.lua` + `.sh` la encuentran solos, con el método de un buscador
de trucos, y escriben `creditos.dat` con el mismo espíritu que `hiscore.dat`:

```
pacman @:maincpu,program,4e6e
```

**Cómo se barre la RAM.** Del mapa de memoria de la CPU:
`sp.map.entries`, quedándose con las entradas cuyo `read.handlertype` o
`write.handlertype` sea `'ram'` (`luaengine_mem.cpp:705-718`), más todos los
`manager.machine.memory.shares`. Hacen falta las dos fuentes: la RAM de trabajo
de Pac-Man no es un share, y la de Simpsons no aparece como `ram` en el mapa
porque va detrás de un delegate.

**La secuencia, y por qué es así** (tres intentos hasta dar con ella):

1. Foto de la RAM.
2. Moneda → los bytes que suben entre 1 y 4 son candidatos, y su subida queda
   fijada como «créditos por moneda» de ese candidato.
3. Moneda, y otra vez moneda → tienen que subir **lo mismo**. Con sólo dos
   monedas aparecían falsos positivos y la respuesta **cambiaba entre pasadas**
   (centiped y mwalk daban direcciones distintas cada vez).
4. START → el que baja es el contador.

**Un solo START.** Probé a verificar con un segundo START y salió mal: con la
partida ya en marcha el juego lo ignora y no gasta crédito, así que el filtro
descartaba hasta al candidato bueno. Los 6 juegos pasaron a «sin candidatos».

**La prueba funcional, que es la que de verdad decide.** Se escribe el mismo
número en todos los candidatos y se pulsa START: sólo baja el que el juego mira.
Tiene que bajar **exactamente 1 o 2**; «que baje» a secas no vale, porque una
placa inicializando su RAM lo pone a cero y parece que responde.

Sin ella, Q*bert quedaba apuntado en `b60`, un byte que el juego no lee: la
pantalla marcaba `CREDITS 0` mientras el log decía «sincronizados 4». Lo
descubrí mirando las capturas, no los logs.

**Juegos con varias copias.** Si responden varios candidatos son copias que el
juego mantiene a la vez, y puede pintar desde cualquiera: se apuntan todas
(`qbert @:maincpu,program,b60+bbd+1100`) y se escribe en todas.

**Nada de `soft_reset`** para volver al modo de atracción antes de la prueba:
relanza el propio script de autoboot desde cero.

**Dos filtros más que resuelven ambigüedades:**

- La placa arranca **sin créditos**, así que el contador vale 0 en la primera
  foto. Lo que empieza en otro número es otra cosa (así se resolvió `elevator`,
  donde competían `3be=18`, `80a2=2` y `c7be=18`).
- Varios candidatos **con el mismo valor** son espejos: la copia que el juego usa
  para pintar el marcador. Vale cualquiera (`popeye`, `qbert`).
- Si los valores difieren de verdad, se declara **ambiguo y no se apunta nada**.
  Una dirección equivocada es peor que ninguna: sin entrada se vuelve a estimar.

**Se barre la RAM de TODOS los procesadores**, no sólo `:maincpu`. Y los
*shares* se traducen a la dirección que ve la CPU (buscando la entrada del mapa
que los referencia): al principio se apuntaba el desplazamiento dentro del
share, y eso metió direcciones falsas en la tabla (`popeye` salía `15d` cuando
es `8fdd`).

**Rendimiento:** de las 24 roms salen 9. Los Namco (digdug, mappy, nrallyx)
siguen sin salir ni barriendo todas las CPU: su contador no está en la RAM de
ningún procesador sino en el chip de E/S.

Con la dirección, `creditos.lua` deja de estimar: lo que sube es lo que entra y
lo que baja es lo que el juego se ha llevado. Los saltos grandes se ignoran a
propósito (un reset de placa pone el contador a cero de golpe y eso no es una
partida que haya que cobrar).

## Sincronizar por escritura, en vez de simular monedas

Idea de Eloy: si el plugin `hiscore` **escribe** en la RAM al arrancar, nosotros
también podemos. Con la dirección conocida, `creditos.lua` pone el monedero
directamente en el contador del juego (`esp:write_u8`) y los dos números pasan a
ser el mismo. Se quitan de en medio tres fuentes de error: los pulsos de moneda
que se pierden, la espera de arranque y la tarifa del DIP.

Dos cuidados, copiados de lo que hace hiscore:

- **Verificar que el valor se quedó puesto.** Si la placa aún estaba
  inicializando su RAM, su propio código lo machaca. Se reintenta unas veces y,
  si no hay manera, **se vuelve a insertar monedas**.
- **Tope** (`GA_TOPE`, por defecto 9): escribir 99 donde el contador sólo llega
  a 9 puede confundir al juego.

`GA_SINCRONIZAR=0` lo desactiva.

Ojo con las pruebas: al escribir el monedero entero en el juego, cualquier
escenario que no fije `GA_ARCHIVO` acaba leyendo el monedero **de verdad**
(`$HOME/.attract/creditos.txt`) y el resultado depende de lo que hubiera jugado
el usuario. Pasó, y por eso `aviso_mame.sh` da a cada escenario su propio
fichero.

## La colección de cheats de MAME como base de datos

Idea de Eloy, y funcionó. `importar_cheats.py` (acepta carpeta, `.zip` y `.7z`).
La colección de Pugsy para MAME 0.279 (`CheatCollection/cheat.7z`, 181.841
ficheros) trae para miles de juegos un cheat *Infinite Credits* cuya acción
apunta al contador:

```xml
<cheat desc="Infinite Credits">
  <script state="run"><action>maincpu.pb@4E6E=09</action>
```

**Resultado: 4.958 juegos añadidos**, y comprobación cruzada de regalo — de los
que yo había medido ejecutando, los cinco que la colección también trae
coinciden exactos (`pacman 4E6E`, `dkong 6001`, `asteroid 0070`, `popeye 8FDD`,
`elevator 80A2`). Dos métodos independientes que convergen.

**Las importadas se ganan la confianza; no se les da.** Hay cheats de créditos
infinitos que parchean el código en vez de escribir el contador, así que:

- Se marcan `(cheat)` en `creditos.dat` y **nunca se escribe en ellas** (escribir
  en el byte equivocado puede corromper la partida).
- Se prueban **por comportamiento**: se insertan las monedas de siempre y se
  mira si el byte sube. Si sube, se pasa a leerlo; si no, se descarta y se
  vuelve a estimar. Verificado en los dos sentidos: `tapper` (`e011`) sube 0→3 y
  se acepta; una dirección falsa metida a mano no se mueve y se rechaza.

**Trampa que costó un intento:** comprobarlas mirando si el contador vale 0 al
arrancar **no vale**. Hay placas con NVRAM que guardan los créditos de la sesión
anterior — `tapper` arrancaba marcando 5 de una prueba previa y la descartaba
por buena. De ahí que la comprobación sea por comportamiento y no por valor.

El sitio devuelve 403 a las descargas automáticas (Cloudflare): el fichero hay
que bajarlo a mano.

## El cuadro de aviso al salir con créditos dentro

`aviso.lua`. Si el jugador va a salir dejando créditos **que metió él**, la
primera pulsación de la tecla de salir no sale: pinta un cuadro y espera. Salir
otra vez sale; START sigue jugando; si nadie contesta en 5 s el cuadro se va y
**no** se sale (ante la duda, la partida sigue). `GA_AVISO=0` lo desactiva.

La condición «que metió él» importa: entrar a mirar un juego y salir no debe
molestar, y el crédito del lanzamiento no cuenta. El texto tampoco dice ya que
se pierdan, porque con la regla nueva no se pierde nada: dice dónde están y
recuerda el saldo del monedero.

La pieza que de verdad evita el malentendido no es el cuadro sino el **mensaje
en el momento**: al meter una moneda dentro del juego aparece abajo
«CREDITO PARA ESTE JUEGO. MONEDERO: N» durante dos segundos y medio. El cuadro
al salir es la segunda red.

**Cómo se frena la salida sin tocar mapeos.** Esto es lo delicado y se resolvió
leyendo el código, con tres piezas que encajan:

1. `manager.machine.ioport:type_pressed(tipo)` lee la tecla **física** en el
   momento en que corre nuestro notificador de frame
   (`src/emu/video.cpp:282`, justo después de `input_update()`).
2. `manager.machine.uiinput:reset()` pone todos los eventos de interfaz en
   `SEQ_PRESSED_RESET` (`src/emu/uiinput.cpp:157`).
3. El `check_ui_inputs()` de MAME corre **después** que nosotros, ya dentro del
   render (`src/frontend/mame/ui/ui.cpp:970`), y su guarda
   `if (!pressed || m_seqpressed[code] != SEQ_PRESSED_RESET)`
   (`uiinput.cpp:95`) **no** vuelve a poner el evento a true mientras la tecla
   siga pulsada. O sea: nuestro `reset()` se come esa pulsación.

Nada persiste: en cuanto dejamos de llamar a `reset()`, la tecla funciona igual
que siempre. Es mucho mejor que `set_typeseq`, que MAME **guarda en su `.cfg`**
y puede dejar un botón muerto para siempre.

`uiinput:pressed()` **no** sirve para detectar la pulsación: no consume el
evento y además lee el estado que dejó el `check_ui_inputs()` del frame
anterior, o sea que se detectaría un frame tarde, cuando MAME ya ha salido.

**Dónde se pinta.** En `manager.machine.render.ui_container`, coordenadas 0..1
(`luaengine_render.cpp:1126-1200`), desde un callback de
`emu.register_frame_done()`. Al principio se usó `pantalla:draw_text()`, que
pinta en el contenedor de la pantalla: **en un juego vertical como Pac-Man el
texto sale tumbado**, porque ese contenedor se rota con el juego. El de la
interfaz es donde MAME pinta sus menús y siempre se lee derecho.

**Ojo al verificar:** `pantalla:snapshot()` guarda el bitmap del juego y **no
incluye la capa de interfaz**, así que el cuadro no sale en esas capturas. Para
verlo hay que capturar la ventana: MAME en segundo plano bajo `xvfb-run` y
`import -window root`, y **sin `-nothrottle`**, o la partida termina antes de
que llegues a capturar.

**Cuántos créditos hay dentro:** exacto en los juegos que están en
`creditos.dat`; en los demás se estima con los botones de START (1 jugador = 1
crédito, 2 jugadores = 2). Vale para las placas clásicas, pero un juego que cobre
dos créditos por partida deja la cuenta corta. Tokens verificados: `START1` =
tipo 7, `START2` = 8, `UI_CANCEL` = 172.

## Parche de avisos en GroovyMAME (sin commitear)

Dos ficheros modificados en `~/Dev/arcade/groovymame_src`, 22 líneas:

- `src/frontend/mame/ui/ui.cpp` — en `display_startup_screens()`, `show_gameinfo`
  y `show_warnings` forzados a `false`.
- `src/frontend/mame/ui/info.cpp` — al final del constructor de
  `machine_static_info`, se limpian los flags de avisos. Es el único punto de
  origen: de ahí se propaga a pantalla de arranque, entrada «Warning Information»
  del menú, textos `Status: NOT WORKING` / `Sound: Imperfect` del selector, y los
  colores rojo/amarillo.

- `src/frontend/mame/ui/ui.cpp` — en `set_startup_text()`, `messagebox_text` se
  vacía. Es el único sitio por el que pasan los tres mensajes de carga:
  `Initializing...` (`emu/machine.cpp:171`) y `Loading Machine (N%)` /
  `Loading Complete` (`emu/romload.cpp:647`). Se deja el `frame_update()` de
  después, que es lo que mantiene la pantalla viva mientras cargan las ROMs.

Los filtros del selector (`WORKING`, `MECHANICAL`, `BIOS`) leen `driver->flags`
directamente, así que siguen funcionando. **Verificado**: Q*bert (sonido
imperfecto) arranca directo al juego sin pantalla de aviso.

**Cómo se verificó lo de los mensajes de carga**, porque la captura NO sirve: la
carga desde disco local dura tan poco que bajo Xvfb sale negra con parche y sin
él, o sea que no prueba nada (lo comprobé compilando las dos versiones). Lo que
sí prueba es instrumentar la función un momento:

```
[PRUEBA] MAME queria mostrar [Initializing...];      messagebox queda []
[PRUEBA] MAME queria mostrar [Loading Machine (0%)]; messagebox queda []
```

## El scraper de artes no funciona: la clave de API está muerta

Probado el 2026-08-30. AM+ 3.2.3 trae una clave pública de thegamesdb.net
incrustada (`scraper_gamesdb.cpp:697`) y el servidor la rechaza:

```
$ curl "https://api.thegamesdb.net/v1/Platforms?apikey=035b376c..."
HTTP 403 — {"status":"Invalid API key was provided."}
```

De ahí toda la cascada del log: `Platform :Arcade (-1)`, `Unable to get platform
information` y los 19 juegos sin emparejar. **No es un fallo de configuración de
la cabina.**

**Resuelto el 2026-09-01, y sin depender de thegamesdb.** AM+ ya traía otro
scraper que sirve mucho mejor para una recreativa: `general_mame_scraper`
(`scraper_net.cpp:176`) baja de **adb.arcadeitalia.net** marquesinas, capturas,
flyers y ruedas, **por nombre de set y sin clave de API**.

El problema era el enrutado: `scrape_artwork()` elige scraper según el
`info_source` del emulador (`scraper_general.cpp`), y con `listxml` se iba
derecho a thegamesdb. **Parche de una rama del `switch`**: con un emulador de
MAME se prueba primero el scraper de MAME y luego thegamesdb como respaldo.

Verificado ejecutando `./attractplus --scrape-art groovymame`:

```
 - Scraping http://adb.arcadeitalia.net [marquee]
 - Scraping http://adb.arcadeitalia.net [snap]
 - Scraping http://adb.arcadeitalia.net [wheel]
```

...y con captura del frontend: la marquesina de Ms. Pac-Man arriba y la captura
del juego a la derecha.

Dos detalles del mecanismo, por si hay que tocarlo:

- Las imágenes van a `<config>/scraper/<emulador>/<tipo>/<set>.png`, y
  `internal_get_best_artwork_file` (`fe_settings.cpp:4676`) mira ahí **sola**:
  no hay que configurar ninguna ruta de artwork.
- El sitio redirige `http`→`https`, y AM+ lo sigue porque pone
  `CURLOPT_FOLLOWLOCATION` (`fe_net.cpp:110`). Con `curl` a pelo hay que usar
  `-L` o se recibe un 301 vacío.

De las 20 roms se bajaron 79 de 80 imágenes (falta la rueda de `spaceinv`).

La otra salida, si algún día se quiere thegamesdb: **una clave propia** (gratis,
se pide en su foro) en `Configure > General`, ajuste `thegamesdb_key`. Aun así
el emparejamiento por título con nombres de set (`nrallyx`, `rbtapper`) sería
flojo.



## Los vídeos de muestra (`videos.sh`)

No hay de dónde bajarlos, así que `videos.sh` los graba con MAME (`-aviwrite`),
recorta y comprime a h264 en `<config>/scraper/<emu>/snap/<juego>.mp4` (AM+
prefiere el vídeo a la imagen fija). Lo que costó y sigue valiendo:

- **El punto del gameplay NO se detecta por imagen; lo elige un humano** mirando
  una hoja de contactos (`--hojas` → rellenar `hojas/tiempos.txt` → `--desde`).
  Las heurísticas de movimiento/brillo fallaban (el título de Mario parpadea más
  que su demo). **Las variantes NO comparten el timing de su base.**
- Se graba **arrancando con `creditos.lua`** (como la cabina) para que valgan los
  ajustes de `arranque.dat`; el negro del arranque entra en el AVI pero el clip
  empieza en `video=`, que cae después.
- El salto por juego vive en `arranque.dat`: `video=N` (manda), `videodura=N`, y
  `videomas=N` (desfase sobre `segundos=`, así el vídeo se mueve si se retoca la
  carga).
- **Grabación acelerada** (`GA_GRABAR`, `begin_recording`/`end_recording`): se
  acelera la carga con frameskip y se graba el AVI SOLO de la ventana del clip
  (robotron 95 s → 7 s; fidelidad idéntica al pixel, el frameskip no rompe el
  determinismo). Aislado por `GA_GRABAR`: sin esa variable la cabina y `correr.sh`
  van por el camino normal.
- Proporción: se amplía en dos pasos (entero con `neighbor`, luego la corrección
  no entera con `lanczos`). `AMPLIAR=0` lo desactiva. `-nothrottle` grabando
  ahorra la mitad del tiempo (el AVI sale idéntico).

Cobertura: ~52 juegos con vídeo de gameplay; el resto a imagen fija (atracción
sin demo jugable). Detalle a fondo: `docs/sh.md`. Ver también «Grabar MI partida
con una tecla» (`grabar.sh`).

## API Lua de MAME (verificada en el código fuente)

```lua
emu.add_machine_frame_notifier(fn)          -- callback por frame
emu.register_prestart(fn)
manager.machine.ioport:token_to_input_type("COIN1")   -- devuelve TUPLA (tipo, jugador)
manager.machine.ioport.ports                -- tabla indexada por etiqueta
port.fields                                 -- tabla indexada por NOMBRE TRADUCIDO
campo.type / campo.type_class               -- comparar por type, nunca por nombre
campo:set_value(1)                          -- pulsar
pantalla:snapshot("/ruta/absoluta.png")     -- método de screen_device
```

Añadido en esta sesión, todo comprobado ejecutándolo:

```lua
campo.type_class == 'dipswitch'      -- para distinguir los DIP
campo.settings                       -- tabla VALOR -> TEXTO del ajuste
campo.user_value                     -- se lee Y se escribe; MAME lo guarda en su .cfg
emu.romname()                        -- nombre del set en marcha
debug.getinfo(1,'S').source          -- ruta del propio script, para dofile de al lado
```

Memoria y entradas, para leer los créditos y frenar la salida:

```lua
cpu.spaces['program']:read_u8(dir)              -- leer la RAM del juego
sp.map.entries                                  -- tramos del mapa de memoria
  e.address_start / e.address_end
  e.read.handlertype / e.write.handlertype      -- 'ram', 'rom', 'delegate', 'port'…
manager.machine.memory.shares                   -- share:read_u8(i), share.size
manager.machine.ioport:type_pressed(tipo)       -- tecla FÍSICA, antes que la UI
campo:input_seq('standard')                     -- secuencia del botón
manager.machine.input:seq_pressed(seq)          -- lee el botón físico, no set_value
manager.machine.uiinput:reset()                 -- se come la pulsación de UI del frame
manager.machine.render.ui_container             -- dibujar sin que rote con el juego
emu.register_frame_done(fn)                     -- el sitio para superponer cosas
```

- `-autoboot_script fichero.lua` existe (`src/emu/emuopts.cpp:230`).
- `-autoboot_delay N` espera N segundos emulados antes de ejecutarlo (`src/frontend/mame/mame.cpp:347`).
- El autoboot corre con la librería estándar de Lua completa: `os.getenv` e `io` funcionan.
- Plugins: directorio con `init.lua` + `plugin.json`. Referencias que hacen algo
  parecido: `plugins/inputmacro/` y `plugins/autofire/`.

### `set_value` es un OR, no una sobrescritura

`src/emu/ioport.cpp:1242`:

```cpp
bool curstate = m_digital_value || machine().input().seq_pressed(seq());
```

Consecuencia importante: `set_value(1)` fuerza el input a encendido, pero
**`set_value(0)` NO bloquea el mando físico**. Para desactivar controles hay que
usar `campo:set_default_input_seq("standard", secuencia_vacía)`, que es la
vía segura (ver «El cerrojo del botón de moneda»). El nombre real de la API del
`ioport` es `set_type_seq`, no `set_typeseq` (`luaengine_input.cpp:179`), pero
ésa sí escribe en el `.cfg`.

## Trampas descubiertas midiendo (esto costó varias iteraciones)

**La espera de arranque es crítica.** Con `-autoboot_delay 3` las monedas se
perdían en silencio: entraban 1 de 3, o ninguna, porque la placa aún hacía su
test de RAM/ROM. **Usar 6 o más.** El log del script decía «3 créditos
insertados» tan tranquilo mientras la pantalla mostraba `CREDIT 0` — no fiarse
de los mensajes, verificar con captura.

**El ancho de pulso importa poco.** 4 y 8 frames funcionan igual. Por defecto 8.

**MONEDAS NO SON CRÉDITOS.** `~/.mame/cfg/pacman.cfg` tiene
`<port tag=":DSW1" type="DIPSWITCH" mask="3" defvalue="1" value="2" />`, o sea
el DIP de tarifa en **1 moneda = 2 créditos**. Por eso 3 monedas daban `CREDIT 6`
y 1 moneda daba `CREDIT 2`. No es un bug del script. **Ya resuelto**, ver abajo.

**LA PLACA LEE LA TARIFA AL ARRANCAR.** Poner el DIP a 1C/1C por Lua durante la
partida **no** afecta a esa partida: medido con Pac-Man, seguía dando
`CREDIT 6`. Pero MAME **sí** guarda el cambio en su `.cfg`, y el arranque
siguiente ya salía `CREDIT 3`. De ahí la solución en dos tiempos: `creditos.lua`
compensa las monedas de la partida en curso *y* deja el DIP a 1C/1C para las
próximas; `poner_1c1c.sh` hace esa pasada de antemano para que hasta el primer
arranque sea exacto. No fiarse de que un `set` de DIP surta efecto ya.

**Ojo con `pairs()` sobre `settings`.** No garantiza orden, y hay juegos con
varios ajustes cuyo texto empieza igual: `mwalk` tiene cuatro que leen
`1 Coin/1 Credit`, uno de ellos con premio (`1 Coin/1 Credit, 2/3`, o sea la
segunda moneda regala crédito). Sin ordenar, cada pasada elegía otro. Hay que
elegir determinista y preferir la tarifa **sin premio**.

**Los textos de los DIP están traducidos.** El analizador espera inglés y cubre
los tres formatos vistos: `1 Coin/2 Credits`, el compacto de Konami/Sega
`A 1/1 B 1/1 C 1/1` (Frogger) y los de premio con coma (Sega System 18).
Escape: `GA_TARIFA=off`.

**Hay hardware sin DIP de tarifa.** De las 24 roms, 7 no lo llevan (qbert,
tapper, simpsons, profpac, rbtapper, mapacman, ncv2): ahí una moneda es un
crédito y punto. 16 ya venían en 1C/1C; el único desviado era pacman.

**No todos los juegos tienen `COIN1`** (consolas, ordenadores). El script lo
detecta y sale limpiamente.

**GroovyMAME revienta con `SIGFPE` bajo Xvfb** — Switchres calculando modelines
contra un display virtual. Se evita con `-noswitchres`. En CRT real no debería pasar.

## Cómo probar

ROMs en `/usr/share/games/mame/roms` (24 sets: pacman, dkong, qbert, frogger,
asteroid, spaceinv…). Prueba con captura, que es la única forma fiable:

```bash
cd ~/Dev/arcade/groovymame_src
Xvfb :99 -screen 0 800x600x24 & 
GA_CREDITOS=3 GA_VERBOSO=1 DISPLAY=:99 ./mame pacman \
  -rompath /usr/share/games/mame/roms -video soft -sound none -nothrottle \
  -noswitchres -window -resolution 640x480 -seconds_to_run 14 \
  -autoboot_script creditos/creditos.lua -autoboot_delay 6
```

Para matar Xvfb sin suicidarse: `pkill -f "[X]vfb :99"` (con corchete, si no el
patrón coincide con el propio comando). Más simple aún: **`xvfb-run -a ./mame …`**,
que levanta y tira el display él solo y evita el baile de `DISPLAY=:99`.

Para pasadas donde no hace falta ver nada (por ejemplo cambiar DIP) basta
`-video none`, que es mucho más rápido.

Un script Lua auxiliar puede sacar la captura desde dentro:

```lua
for tag, scr in pairs(manager.machine.screens) do scr:snapshot('/ruta.png') break end
```

## El script de créditos

`creditos/creditos.lua`, configurable por entorno:

| Variable | Por defecto | Qué hace |
|---|---|---|
| `GA_CREDITOS` | – | créditos a insertar; manda sobre el fichero |
| `GA_ARCHIVO` | `$HOME/.attract/creditos.txt` | fichero del monedero |
| `GA_TARIFA` | `1c1c` | `1c1c`, `auto` (sólo compensa), `off` (ignora los DIP) |
| `GA_VIGILAR` | 1 | `0` para no llevar la cuenta durante la partida |
| `GA_AVISO` | 1 | `0` para no avisar al salir con créditos dentro |
| `GA_ARRANQUE` | 300 | frames MÍNIMOS de arranque tapado (pantalla negra, moneda cerrada) |
| `GA_ARRANQUE_MAX` | 1800 | tope de ese arranque |
| `GA_ARRANQUE_SIN` | 900 | arranque en juegos sin dirección conocida |
| `GA_ESTABLE` | 120 | frames que el contador debe estar a cero para darlo por listo |
| `GA_LIMPIAR` | 1 | `0` para no quitar los créditos que la máquina trae puestos |
| `GA_COMPROBAR` | 90 | frames de gracia para ver si la moneda llegó; si no, se devuelve |
| `GA_ANTIRREBOTE` | 8 | frames que se ignoran tras una moneda, contra el rebote |
| `GA_VELOCIDAD` | 0 | velocidad al arrancar, en % (100 normal, 0 sin freno) |
| `GA_AUTO` | 0 | `1` para alargar el arranque hasta detectar que la placa está lista |
| `GA_AJUSTES` | `arranque.dat` | fichero de ajustes por juego |
| `GA_TURBO` | 1 | `0` para no acelerar el emulador durante el arranque |
| `GA_ASENTAR` | 180 | frames que se deja asentar la RAM antes de contar |
| `GA_LIMPIAR` | 1 | `0` para no quitar los créditos que la máquina trae puestos |
| `GA_MONEDERO` | – | `1` para el monedero compartido con el frontend; apagado = monedas de verdad |
| `GA_COBRO` | `meter` | `meter` cobra la moneda al meterla (contador físico); `jugar` cobra al gastarla |
| `GA_CERROJO` | 1 | `0` para no limitar las monedas del jugador a su monedero |
| `GA_MENSAJE` | 150 | frames que dura el aviso al meter una moneda |
| `GA_PULSO` | 8 | frames con la moneda pulsada |
| `GA_HUECO` | 8 | frames entre monedas |
| `GA_ESPERA` | 0 | frames extra de espera |
| `GA_MONEDA` | COIN1 | token de entrada |
| `GA_VERBOSO` | – | `1` para diagnóstico |

Guarda su estado en la global `GA_ESTADO` a propósito: si fueran locales del
chunk, el recolector de basura podría llevarse la suscripción al notificador.

Los dos módulos vecinos, `tarifa.lua` (el DIP) y `monedero.lua` (la cuenta), se
cargan con `dofile`. La ruta se saca de `debug.getinfo(1,'S').source` —
**verificado** que funciona en el contexto de `-autoboot_script`, igual que `os`,
`io` y `dofile`. `monedero.lua` no habla con MAME a propósito: recibe funciones
para leer el botón y guardar, así que su contabilidad se prueba con `lua` a
secas.

## API de Attract-Mode Plus (leída en el código de este repo)

Sacado del código fuente, no de la memoria del modelo. Lo que además se ha
confirmado ejecutando está en la sección siguiente:

- **Los plugins corren ANTES del layout** (`src/fe_vm.cpp:1763-1790`), así que
  sus objetos quedan *debajo*. Para dibujar encima: crear el objeto en
  `Transition.StartLayout` y poner `zorder = 2147483647`, como hace
  `config/plugins/FPSMonitor/plugin.nut:44`.
- **`min()` y `max()` devuelven FLOAT** (`src/sq_math.cpp:74-80`). No son de
  Squirrel: los añade AM+ al root table (`fe_vm.cpp:648`). Usarlos en un
  contador deja «CREDITOS 3.00000» en pantalla. Comparar enteros a mano.
- Directorio de configuración en Linux: **`$HOME/.attract/`**
  (`src/fe_settings.cpp:54-60`), no `.attractplus`.
- Squirrel **3.0.7** con las librerías blob, io, math, string y system
  (`fe_vm.cpp:631-635`): hay `file()`, `close()`, `getenv()`, `remove()`.
- `fe.nv` persiste solo; se guarda al salir, al cambiar de layout y tras cada
  pulsación. `fe.nv.rawin("clave")` para ver si ya existe.
- `fe.overlay.is_up` dice si hay un menú del frontend abierto. Imprescindible
  antes de comerse la señal `select`, que dentro de un menú sirve para
  confirmar.
- Los `args` del emulador pasan por `wordexp()` **sin `WRDE_NOCMD`**
  (`fe_util.cpp:1721`): la expansión del shell funciona ahí.
- Claves válidas del `.cfg` de un emulador: `src/fe_info.cpp:1088`.
- `UserConfig` admite `is_input=true` (pide una tecla), `options="a,b"`,
  `order`, `help`, `is_function`, `per_display`. Ver `KonamiCode.nut`, que es la
  mejor referencia de estilo del repo.

## Attract-Mode Plus, ya verificado ejecutándolo

Con AM+ compilado, esto ya no es lectura de código sino medición:

- **Los plugins corren antes del layout: confirmado en pantalla.** El layout de
  prueba pinta un rectángulo opaco a pantalla completa y el marcador se ve
  encima. Sin `zorder` máximo y sin crearlo en `Transition.StartLayout`,
  quedaría tapado.
- **El `ttime` de una transición cuenta desde que empieza la transición**, no
  desde que arrancó el layout. En `tick()` sí es tiempo de layout. Mezclarlos
  hizo que diagnosticara mal un fallo que no existía.
- **El reloj del frontend sigue corriendo durante la partida.** Al volver del
  juego da un salto de todo lo que duró, así que cualquier temporizador propio
  hay que resincronizarlo en `Transition.FromGame`.
- La señal `screenshot` guarda `screen*.png` **en el directorio de
  configuración** (`src/main.cpp:781`). Es la forma de sacar capturas del
  frontend sin herramientas externas.
- `fe.list.index` se puede asignar, y `fe.get_game_info( Info.Name, desfase )`
  lee los títulos vecinos: así se selecciona un juego concreto sin teclado.
- Estructura del directorio de configuración:
  `<cfg>/config/attract.cfg`, `<cfg>/config/plugins.cfg`, `<cfg>/emulators/*.cfg`,
  `<cfg>/romlists/*.txt`, y los datos (`layouts/`, `plugins/`, `modules/`…) en la raíz.
- `plugins.cfg` se escribe con tabuladores:

  ```
  plugin	Creditos
  	enabled	yes
  	param	senal	custom1
  ```

- **`name` NO es una clave válida** en el `.cfg` de un emulador: el nombre sale
  del nombre del fichero. AM+ lo avisa por consola y sigue.
- `--config <dir>` y `--build-romlist <emu>` permiten montar una instalación de
  pruebas aparte, sin tocar `~/.attract`.

## Cómo se prueba el plugin

`creditos/pruebas/correr.sh` — 84 comprobaciones del
plugin, 24 del analizador de tarifas, 46 del monedero, 53 del cuadro de aviso,
46 de la lectura y escritura en memoria, 23 de los ajustes por juego, 37 del
cerrojo de la moneda y 7 del importador de cheats, y no
necesita AM+ compilado ni emulador.

Truco: `extlibs/squirrel` no depende de nada externo, así que se compila un
intérprete mínimo (`sqhost.cpp`, ~50 líneas) con las **mismas fuentes de
Squirrel 3.0.7 que usa AM+**, y el plugin se ejecuta contra `maqueta.nut`, una
imitación de la API. La maqueta reproduce a propósito las asperezas reales
(min/max en float, config siempre en cadenas, plugin antes del layout).

Se comprobó que las pruebas sirven de algo rompiendo el plugin a mano: 5 de 6
mutaciones las detectan. La que no: quitar el `close()` del buzón, porque
Squirrel cierra el fichero por conteo de referencias al salir del ámbito.

Y una prueba de integración de verdad, `pruebas/integracion.sh`, que reproduce
la avería de los créditos perdidos: tres monedas, una partida con una moneda
extra metida por el camino, y comprobar que al volver queda exactamente un
crédito. La moneda «del jugador» se finge sustituyendo la función que el
vigilante usa para leer el botón (por eso `monedero.lua` no habla con MAME) y
pulsando además la entrada de verdad, para que el juego conceda el crédito. Más
en detalle, `pruebas/integracion.sh`: arranca AM+
bajo Xvfb en un directorio de configuración temporal, con el plugin activado,
lanza GroovyMAME y vuelve. Un layout de prueba dispara las señales, porque bajo
Xvfb no hay quien pulse botones. Comprueba cuatro cosas sin criterio humano:
el marcador encima del layout (midiendo píxeles), los créditos llegando a MAME,
que la moneda metida durante la partida se descuenta, y que con lo que queda se
juega otra partida.

Y `pruebas/aviso_mame.sh`, 56 comprobaciones dentro de MAME: frenar, confirmar,
cancelar con START, rendirse solo, no molestar al que sólo entra a mirar,
`GA_AVISO=0`, el caso del jugador despistado (cuatro monedas metidas en la
partida, una jugada, monedero de 10 a 9) y que los créditos se lean de la RAM
cuando el juego está en `creditos.dat`. La tecla de salir se finge sustituyendo la
función que la lee; **límite de esa simulación**: no es una pulsación real, así
que en el caso «no avisar» sólo se comprueba que no frenamos la salida.

Lo que **no** cubre: el mando físico de la cabina y el CRT.

## La sesión es Wayland, y eso rompe el modo pantalla completa

Encontrado el 2026-09-02 con el CRT de escritorio (HDMI + adaptador a VGA), a
raíz de esto:

```
X Error of failed request:  BadMatch
  Major opcode of failed request:  139 (RANDR)
  Minor opcode of failed request:  21 (RRSetCrtcConfig)
```

Parece un problema de resolución del CRT y **no lo es**. Son dos causas
independientes, y ninguna es la pantalla:

**1. Se lanzó con `sudo`.** Root no tiene `~/.attract`, así que AM+ arrancó con
la configuración por defecto e ignoró la cabina entera (`Config file not found:
/root/.attract/attract.cfg`). Y todos los errores de PulseAudio/ALSA son lo
mismo: el servidor de sonido es del usuario. **AM+ no necesita sudo.**

**2. `window_mode fullscreen` bajo GNOME Wayland.** La sesión es
`XDG_SESSION_TYPE=wayland`; AM+ corre sobre Xwayland, que expone RandR en
**solo lectura**. En modo `fullscreen` SFML pide cambiar el modo de vídeo
(`RRSetCrtcConfig`) y siempre le responden `BadMatch`. El arreglo es
**`fillscreen`** (ventana sin bordes, sin cambio de modo), que además es el
valor por defecto de AM+.

### Bajo Wayland, AM+ no puede elegir monitor

Medido, no supuesto: mutter **ignora el `setPosition()`** del cliente X. Con
las dos pantallas encendidas la ventana acabó en `+973+32`, a caballo entre
ambas, dijera lo que dijera `fe_window.cpp`. Y `xrandr --pos` tampoco hace
nada: la disposición la decide mutter y se cambia por D-Bus
(`org.gnome.Mutter.DisplayConfig.ApplyMonitorsConfig`).

De ahí `pantalla.py` y `cabina.sh`: **el CRT se queda como única pantalla**
mientras dura la partida. Si no hay otro sitio donde caer, la ventana cae
donde tiene que caer. Verificado: `1024x768 @ 0,0`, y el escritorio vuelve
igual al salir.

Detalles que costaron una iteración:

- **La escala no se adivina, se guarda.** El primer intento elegía «la escala
  entera más alta» y ponía el panel 4K al 400%. `pantalla.py cabina` apunta la
  disposición previa en `~/.attract/pantalla_previa.json` y la devuelve tal
  cual.
- **Con el portátil cerrado mutter se niega a reactivarlo** («Refusing to
  activate a closed laptop panel»), así que la restauración fallaba y dejaba
  la pantalla a medias. Ahora se reintenta sin el panel.
- `pkill -f attractplus` **se mata a sí mismo**: el patrón encaja con la propia
  línea de comandos. Y el truco del corchete (`[a]ttractplus`) tampoco vale si
  la orden menciona el nombre en otro sitio. Usar `pkill -x attractplus`.

### Y switchres tampoco puede

Comprobado lanzando el emulador en esta sesión:

```
Switchres/SDL2: (sdl2_display): SDL2 is only available for KMSDRM for now.
Switchres: could not find a video mode that meets your specs
```

MAME arranca igual, pero a la resolución fija del escritorio y sin modeline.
Para la cabina de verdad conviene una **sesión Xorg** (`ubuntu-xorg.desktop`
está instalado, se elige en la rueda dentada del login): ahí funcionan las dos
cosas, el `fullscreen` de AM+ y switchres.

## Vídeo en el CRT y la cabina actual (resumen)

**La cabina de hoy** (cambiada el 2026-09-04): un VAIO con **i3-2350M + Intel HD
3000** (driver `modesetting`+glamor sobre i915), a **1024x768**. Sale por anclaje
4G, con IP cambiante en un rango `/28` (se la encuentra con un barrido de 14
direcciones al puerto 22). Aquí **sobra GPU**: los shaders van al 100%.

> La cabina VIEJA (GeForce 410M con nouveau clavada a 270 MHz, i5-2430M) no podía
> con los shaders y obligó a un `crt-lite` de una sola pasada. Es historia: con la
> nueva, **`crt-real` es el shader por defecto** (crt-geom ajustado para una
> pantalla que YA es un CRT: sin máscara ni curvatura, `spot_size 0.16`,
> `monitorgamma 2.6`). `crt-lite` queda para GPU flojas.

**Reglas que siguen vigiendo** (medidas, no supuestas):

- En un **CRT de PC** las scanlines solo las dibuja un **shader**, y el shader
  pide **X** porque **bgfx no soporta KMSDRM**. KMS+switchres (modos nativos, con
  las scanlines del propio tubo) solo sirve en un **monitor de recreativa de
  verdad**, no en este VGA de 31 kHz: 288 líneas a 60 Hz piden ~18 kHz y el VGA
  no baja de 31.
- Por eso la cabina va en **X** con `modesetting`+glamor (DRI3; el DDX viejo
  `nouveau` daba DRI2 y era el cuello de botella), shader `crt-real`,
  `switchres 0` y **`waitvsync 0`** (el vsync topa la emulación a 60 Hz y mata el
  arranque acelerado).
- **Los verticales se ven a 3:4 y los horizontales a 4:3**: el monitor de
  recreativa es 4:3 FÍSICO. MAME lo hace bien; el estirado estaba en las capturas
  y vídeos (`aspecto.sh` lo corrige, `videos.sh` graba ya bien). En una pantalla
  5:4 se fuerza `aspect 4:3` en `mame.ini` (a 1024x768, que ya es 4:3, no hace nada).
- **Los ajustes de vídeo por juego** (`keepaspect`, escalado, cadena bgfx) solo
  persisten con el parche `parches/groovymame-guardar-ajustes-video.patch`;
  `tarea_crt` limpia los `.cfg` por juego. Trampa del bgfx: referenciar un
  `parameter` sin declararlo en el bloque `parameters` hace que MAME
  **segfault sin ningún mensaje**.

Mediciones históricas y el detalle a fondo: `docs/sh.md` y el historial de git.

## Juegos que no son un `.zip`: Street Fighter III y el CHD

Traído por Eloy el 2026-09-02: *«tuve que introducir 2 archivos en un
directorio, no en un .zip»*. Los dos ficheros estaban bien —
`./mame -verifyroms sfiii3` decía `romset sfiii3 is good`— pero el juego no
aparecía en la cabina. Eran **dos problemas encadenados**.

### 1. AM+ no veía la carpeta

El emulador tenía `romext .zip;.7z`, y AM+ escanea el rompath **por extensión**:
una carpeta no tiene. Se arregla con el token `<DIR>` (`fe_base.cpp:51`), que
hace que `gather_rom_names` llame además a `get_subdirectories`:

```
romext               .zip;.7z;<DIR>
```

De 23 entradas a 24. Está en la plantilla `config/cabina/groovymame.cfg`, así
que `instalar.sh` ya lo pone.

Ojo al reconstruir la lista: **sin `-o` AM+ NO sobrescribe**, crea
`groovymame1.txt`, `groovymame2.txt`… y el frontend sigue leyendo la vieja.
Hay que pasar `--build-romlist groovymame -o groovymame`.

### 2. CPS3 no arranca del CD: hay que grabar la flash una vez

Lo que salía en pantalla, y no es un fallo de instalación:

```
You have inserted a new CD-ROM.
> Rewrite the game     Cancel
...it will take about 70 minutes to rewrite the new game.
```

La placa CPS3 copia el juego del CD a la flash del cartucho. Es el procedimiento
real, y en MAME hay que pasarlo **una vez**: los 81 MB resultantes quedan en
`~/.mame/nvram/sfiii3/` (`simm1.0`…`simm5.7` y `eeprom`) y los arranques
siguientes van directos.

- **El botón que confirma es `P1 Jab Punch`** (botón 1), no START. Medido
  probándolos uno a uno: con START la pantalla no cambiaba.
- Dura unos 70 minutos **emulados**; sin freno son unos 8 de reloj.
- Después, el arranque son ~20 s emulados hasta el logo de Capcom y ~25 hasta
  la atracción. De ahí `sfiii3 segundos=20 velocidad=0` en `arranque.dat`.

**Peligro con `nvram=0`.** Ese ajuste de `arranque.dat` apaga `nvram_save`, y en
un CPS3 eso tira la flash: volvería a pedir los 70 minutos en cada arranque.
**Nunca ponérselo a un juego de CPS3.**

`arranque.dat` tenía una línea para `sfiii3n`, que es el set **sin CD** (30
ficheros SIMM, unos 80 MB) y no está instalado. Corregida a `sfiii3`.

### Y la tarifa de CPS3 no la arregla `tarifa.lua`

El juego marca `INSERT 2 COINS`. **CPS3 no tiene DIP switches** —comprobado
volcando sus puertos: sólo `:INPUTS` y `:EXTRA`, ningún `dipswitch`— así que la
tarifa vive en el menú de servicio del propio juego y se guarda en su EEPROM.
`GA_TARIFA` no puede tocarla; hay que entrar al test menu una vez.

## El instalador: `instalar.sh` con whiptail

Reescrito el 2026-09-02, a raíz de que Eloy intentara compilar en una máquina
nueva (Linux Mint) y se topara con esto:

```
Package 'libavformat', required by 'virtual:world', not found
Makefile:424: *** pkg-config couldn't find some libraries, aborting.
```

El instalador viejo sólo comprobaba `git make g++` y decía qué faltaba. Ahora lo
instala él, y va por pasos con **whiptail**.

**Todo tiene valor por defecto.** Enter a secas, o Cancelar, deja el defecto:
cancelar una pregunta no debe tirar abajo una instalación a medias. Sin
whiptail, sin terminal, o con `--sin-preguntar`, se usan los defectos sin
molestar. Las tareas son un checklist: dependencias, compilar AM+, configuración,
lista de juegos, artes, CRT, parchear GroovyMAME y vídeos.

### Las dependencias no se comprueban por el nombre del paquete

Se comprueban por el **módulo de pkg-config** (o el binario, para las
herramientas), y sólo entonces se traduce al paquete de esa distro. Preguntar
por el paquete no vale: se llaman distinto en cada sitio y en Arch las cabeceras
van dentro del paquete normal, mientras que en Debian van aparte en un `-dev`.
De las 22 librerías salen 22 paquetes en Debian y **17 en Arch**, porque los
cinco de FFmpeg son un solo `ffmpeg`.

Verificado con `apt-get install --simulate`: los 26 nombres de Debian existen.
**Los de Arch no se han podido comprobar** desde aquí, así que el script se
protege solo: antes de instalar mira cuáles existen de verdad
(`pacman -Si`, y `pacman -Sg` para `base-devel`, que es un grupo y `-Si` no lo
ve), avisa de los que no y sigue con el resto — pacman aborta la instalación
entera si un solo nombre está mal, y perder veinte por una no vale la pena. Si
**ninguno** aparece, lo que pasa es que la base de datos está sin sincronizar,
no que estén todos mal: entonces se lanza `pacman -Sy` y que hable él.

Después de instalar **se vuelve a comprobar**, y si algo sigue sin aparecer se
dice. Así un nombre equivocado se ve en el momento y no cuatro minutos después,
al fallar la compilación.

### Detalles que costaron una iteración

- **whiptail es justo lo que no está** en una máquina recién instalada. Se
  ofrece antes que nada, en texto plano, porque todavía no hay con qué dibujar
  un cuadro. En Arch **lo trae `libnewt`**, no un paquete `whiptail`.
- **La ruta del emulador se normaliza** (`cd … && pwd`): la detección la
  encuentra como `$AQUI/../groovymame_src/mame` y ese `..` acabaría escrito en
  el `.cfg` del emulador y en `mame.ini`.
- El fallback sin whiptail necesita `printf '%b'`, no `'%s'`, o los `\n` de los
  mensajes salen literales.
- `TAREAS="config romlist" ./instalar.sh --sin-preguntar` fija las tareas por
  entorno. Es como se prueba sin ir tarea por tarea.

### Seis fallos que salieron al probarlo en Mint

Eloy lo lanzó en la otra máquina y el log dio para mucho. Merece la pena
apuntarlos porque casi todos son mudos:

**1. `sudo ./instalar.sh` escribe en `/root/.attract`.** Con sudo, `HOME` es
`/root`, así que la configuración entera se instaló donde el frontend —que
corre como el usuario— no la ve jamás. Es el mismo agujero que ya estaba
documentado para `sudo ./attractplus`. Ahora el script **se niega a arrancar
como root**: sudo lo pide él, y sólo para los paquetes.

**2. whiptail toma por opción cualquier texto que empiece por `-`.** El mensaje
final es una lista de guiones, así que respondía
`- Los videos de muestra: ...: unknown option` y no dibujaba nada. Se arregla
metiéndole un salto de línea delante; está en `d_texto`, `d_si` y `d_aviso`.

**3. Un rompath equivocado convierte cada carpeta en un juego.** Con `ROMS` en
el home y `<DIR>` en `romext`, AM+ encontró **36 «juegos»** llamados `.config`,
`Descargas`, `.ssh`, `.gnupg`… Por eso ya no basta con que la carpeta exista:
`hay_roms()` exige un `.zip`, un `.7z` o un `.chd` dentro.

**4. Que falte la carpeta de roms ya no aborta.** Se vuelve a preguntar tantas
veces como haga falta, con el valor malo delante y diciendo qué le pasa; y
dejándolo vacío se sigue sin ellas (se saltan solas la lista, los artes y los
vídeos). Lo mismo para el emulador y el repo de créditos.

**5. Al emulador le faltaban librerías de EJECUCIÓN, no de compilación.**

```
mame: error while loading shared libraries: libSDL2_ttf-2.0.so.0
```

pkg-config no lo ve —eso mira cabeceras— así que se le pregunta al binario con
`ldd … | awk '/not found/'`. El síntoma era feo y callado: MAME no arrancaba,
`-listxml` no devolvía nada, y la lista salió con 36 entradas **sin un solo
dato**. De ahí la revisión final, que comprueba las tres cosas que no dan la
cara hasta mucho después: que el emulador arranque, que la lista tenga datos de
verdad (si la segunda columna es igual a la primera, faltó el `-listxml`) y que
haya sesión gráfica.

**6. `convert` no estaba**, así que `aspecto.sh` no corregía nada. `imagemagick`
está ahora en la tabla.

### «Failed to open X11 display» y un volcado de memoria

AM+ no avisa de esto: aborta. `cabina.sh` lo comprueba antes y dice las tres
causas posibles (consola de texto, ssh sin `-X`, sesión Wayland sin Xwayland).

### GroovyArcade: la disposición de verdad, medida por SSH

Es el destino final de la cabina, y **no usa `~/.attract`**. Lo que hay
(comprobado el 2026-09-03 entrando por SSH, no supuesto):

```
~/shared/roms/mame                 las roms, una carpeta por emulador
~/shared/frontends/attract         la configuracion de AM+ (config/, plugins/,
                                   layouts/, emulators/, romlists/, scraper/...)
~/shared/frontends/groovymame  ->  ../configs/mame     (es un enlace)
~/shared/media/mame                artes y videos de la distro
~/shared/configs/ga.conf           configuracion de gasetup
```

`gasetup` es un guion (`/opt/gasetup/gasetup.sh -p interactive`), y su
configuracion es la que decide que se lanza:

```
frontend=attractplus      <- por eso basta con reemplazar /usr/local/bin/attractplus
video.backend=X           <- Xorg, no Wayland: aqui no hay el problema de la otra maquina
monitor=lcd               <- OJO
connector=LVDS-1          <- OJO: es el panel interno del portatil
```

Binarios:

```
attractplus  -> /usr/local/bin/attractplus     <- el que lanza gasetup
groovymame   -> /usr/local/bin/groovymame -> /usr/lib/mame/groovymame
mame         -> /usr/bin/mame                  (el MAME de la distro, a secas)
```

Y las rutas de MAME **no son las de siempre**:

| | Ubuntu (esta máquina) | GroovyArcade |
|---|---|---|
| `mame.ini` | `~/.mame/mame.ini` | `~/.mame/mame.ini` (y `~/.mame` es un enlace a `~/shared/configs/mame`) |
| `bgfx_path` | junto al ejecutable | `/usr/lib/mame/bgfx` (de root) |
| `rompath` | `/usr/share/games/mame/roms` | `~/shared/roms/mame` |

Por eso `instalar.sh` ya no las supone: **se las pregunta a MAME** con
`mame_opcion()` (`-showconfig`), y el `mame.ini` que manda es el primero del
`inipath`. Con eso el mismo código acierta en las dos máquinas.

**Corregido el 2026-09-04:** aquí estaba escrito que en GroovyArcade el fichero
era `~/.mame/ini/mame.ini`. **Es mentira** — ese directorio existe pero está
vacío, y `groovymame -showconfig -verbose` dice `Parsing
/home/arcade/.mame/mame.ini`. `inipath` vale `$HOME/.mame/ini`, que es de dónde
salen los `.ini` *por juego*, no el principal. Escribir en el sitio equivocado
es un fallo mudo: no da error y ningún ajuste surte efecto.

**El enlace `~/.attract` es imprescindible.** AM+ busca su configuración ahí y
punto (`fe_settings.cpp:54-60`); si la cabina la tiene en
`~/shared/frontends/attract`, el frontend arrancaría con la configuración por
defecto e ignoraría la cabina entera. `instalar.sh` crea el enlace (y si
`~/.attract` ya existe como directorio de verdad, avisa en vez de pisarlo).

**Y el binario del sistema tiene que ser el nuestro**, porque gasetup lanza el
del PATH: la tarea `binario` guarda el suyo en `.antes_instalar` e instala el
nuestro en `/usr/local/bin/attractplus`. Viene marcada por defecto **sólo** en
GroovyArcade.

**switchres no se toca ahí, pero hoy tampoco sirve de nada.** En esta máquina se
apaga porque pisa `keepaspect` y encima no puede poner modelines bajo Wayland.
En GroovyArcade *podría* hacer su trabajo —sesión Xorg propia— pero `ga.conf`
trae **`monitor=lcd` y `connector=LVDS-1`**, o sea declarado como panel interno
de portátil: con eso switchres se queda en las resoluciones del panel y no
genera ni una modeline de recreativa. Hay que cambiarlo en **gasetup > Setup
(video)**, no editando `ga.conf` a mano: ese fichero no regenera solo la línea
del kernel (`kernel_video_cmdline`) ni el `xorg.conf`. `instalar.sh` lo lee y
avisa, pero no lo toca.

Lo que **no** cubre el instalador ahí: los dos parches de `parches/` no están
aplicados al GroovyMAME de la distro. Sin ellos siguen saliendo las pantallas
de aviso y los ajustes del menú Video Options no se guardan. Aplicarlos pide
recompilar GroovyMAME desde el PKGBUILD de Arch.

### En GroovyArcade no hay que compilar el emulador

Es el destino real de la cabina: una distro Arch con GroovyMAME **ya
instalado**. La detección lo busca en `/usr/bin/groovymame` y la tarea de
parchear y compilar MAME viene desmarcada por defecto.

## Un solo `git clone`: los dos repos son uno

Pedido por Eloy el 2026-09-03: *«la idea es hacer solo 1 gitclone»*. Tenía
razón — dos repositorios que sólo funcionan juntos son dos formas de que la
instalación salga a medias.

`groovyarcade-creditos` está ahora dentro, en **`creditos/`**, metido con
`git subtree add` para no perder su historial. Su rama del monedero se
conservó como `creditos-monedero-frontend`.

Lo que hubo que rehacer: los scripts derivaban sus rutas suponiendo que los
repos eran **hermanos** (`$AQUI/../groovymame_src`), y ahora `creditos/` está un
nivel más adentro. En vez de cambiar un `..` por otro, hay una función `vecino()`
que **prueba las dos disposiciones**, porque una copia de trabajo antigua sigue
teniéndolos al lado:

```bash
MAME_DIR="${MAME_DIR:-$( vecino mame \
	"$AQUI/../../groovymame_src" "$AQUI/../groovymame_src" "$HOME/groovymame_src" )}"
```

Las 339 comprobaciones de `correr.sh` pasan desde la ubicación nueva.

`groovymame_src` sigue fuera y sin versionar: son 3 GB de fuentes de terceros.
Lo que se versiona son los parches, en `parches/`.

## Cinco fallos del primer intento en GroovyArcade

Log del 2026-09-03, la primera vez que `instalar.sh` corrió en la cabina de
verdad. Todos son cosas que aquí no se ven.

**1. La base de datos de pacman estaba desfasada.** 404 en los sesenta espejos,
con `pkgconf-3.0.5-1` e `imagemagick-7.1.2.29-2`: no es la red, es que la base
local tiene versiones que ya no están publicadas. En Arch eso se arregla con
**`pacman -Syu` y sólo con `-Syu`** — un `-Sy` a secas deja el sistema medio
actualizado y rompe cosas. El instalador lo detecta y **pregunta** antes de
actualizar: es una cabina que funciona, y esa decisión no es suya.

**2. Faltaba `cmake` en la tabla de dependencias.** El Makefile de AM+ compila
su propia SFML con cmake (`sfmlbuild`, línea 506), y aquí estaba instalado de
antes, así que no se notó: `make: cmake: No such file or directory`.

**3. Al binario del release le faltaba `libpipewire`.** Y el fallo de diseño
detrás: `paquetes_del_emulador` miraba las librerías del emulador **del
sistema**, no las del que se acababa de bajar. Ahora recibe qué binario mirar y
la tarea `descargar` lo comprueba sobre el suyo.

**Dato bueno de ahí: el release SÍ pasa la comprobación de glibc en
GroovyArcade.** O sea que el binario de Ubuntu arranca allí en cuanto están sus
librerías. El aviso se suavizó: el de la distro sigue siendo preferible por
estar hecho a medida, pero no es que el otro no funcione.

**4. `tarea_arte` no comprobaba que el frontend estuviera compilado**, así que
soltaba `./attractplus: No such file or directory`. Como ya hacía `romlist`.

**5. Que fallen las dependencias no paraba nada.** Se seguía adelante y la
compilación reventaba con un error que no dice que el problema son las
dependencias. Ahora pregunta si seguir, con «no» por defecto.

## Lo que rompi en GroovyArcade: `attractplus` no es un binario

Diagnosticado el 2026-09-03 entrando por ssh a la cabina, que es la unica forma
de ver esto.

**`/usr/local/bin/attractplus` es un GUION de ocho lineas**, no un ejecutable:

```bash
if [[ -z $DISPLAY ]] ; then attractplus-kms "$@"; else attractplus-x11 "$@"; fi
```

GroovyArcade compila **dos** frontends -- uno para KMS/DRM directo y otro para
X11 -- y ese envoltorio elige segun haya sesion grafica. La tarea `binario` lo
sustituyo por nuestro ejecutable y se llevo por delante la eleccion: en modo KMS
el frontend deja de arrancar.

Se noto porque el fichero de respaldo pesaba **161 bytes**. Ahora la tarea mira
si el destino empieza por `#!` y, si es asi, instala en `attractplus-x11` y
avisa de que `attractplus-kms` sigue siendo el suyo: nuestro build es de X11, y
para el otro haria falta `make USE_DRM=1`.

### El layout no se cargaba: `displays.cfg` ya existia

`copiar_si_falta` respeta el fichero que haya, que esta bien -- pero entonces
los displays de GroovyArcade apuntaban a `BasicPlus`, que es de serie y vive en
`/usr/local/share/attractplus/layouts`. El frontend arrancaba con otra cara y
sin decir por que.

La regla para detectarlo **no es** «no usa Arcade-UMAG»: en la maquina de
desarrollo el layout de la cabina se llama `Attrac-Man`, porque se edito encima
del de serie, y eso es correcto. La regla es que **ningun display use un layout
que este en nuestro directorio de layouts**. Y al corregirlo se busca el display
por su **lista de roms**, no por su nombre, que puede ser cualquiera.

### Por que el layout seguia sin salir: el display equivocado

Segunda pasada por ssh. El binario ya era el nuestro (el log lo canta:
`+Xinerama` y `Arranque: listo`), pero el log decia:

```
*** Initializing display: 'MAME'
 - Loaded layout: /usr/local/share/attractplus/layouts/Attrac-Man/layout.nut
Error getting emulator info for launch
```

`displays.cfg` traia **dos** displays y el de GroovyArcade, `MAME`, era el
**primero**: la cabina arrancaba en el. Y encima estaba roto — su lista pedia
un emulador `MAME` que no estaba definido en `emulators/`, de ahi el
`Error getting emulator info for launch` al lanzar cualquier juego.

Quitado ese display, el log pasa a:

```
*** Initializing display: 'groovymame'
 - Loaded layout: .../layouts/Arcade-UMAG/layout.nut
```

La revision del instalador ahora avisa de las listas que piden un emulador que
no existe: AM+ las muestra igual y **solo falla AL LANZAR**, con un mensaje que
no dice cual ni por que.

Se puede probar todo esto sin pantalla: la cabina trae `xvfb-run`, y
`xvfb-run -a attractplus-x11` enseña que display y que layout carga. El
emulador tambien arranca ahi, pero **con `-noswitchres`**: si no, switchres
calcula modelines contra un display virtual y revienta con `SIGFPE`, que es el
mismo fallo ya documentado en «Cómo probar».

### La pantalla VGA: X encendia las dos, y el frontend salia en la otra

Tres intentos hasta dar con esto, y los dos primeros iban por mal camino.

Los conectores, leidos de `/sys/class/drm`: `HDMI-A-1` desconectado,
`LVDS-1` conectado (el panel interno) y `VGA-1` conectado (el CRT).
`ga.conf` traia `connector=LVDS-1` y `monitor=lcd`, asi que lo primero que
supuse fue que habia que cambiar el conector de arranque del kernel.

**Era mentira, y la prueba fue arrancar X y preguntarle a xrandr:**

```
Screen 0: current 2390 x 768
LVDS-1 connected primary 1366x768+0+0
VGA-1  connected         1024x768+1366+0
```

**Las dos salidas estaban encendidas.** El CRT funcionaba perfectamente: mostraba
la parte derecha de un escritorio extendido, que esta vacia. El frontend se abre
en la primaria, que es el panel. Es el mismo problema del portatil, pero al
reves de facil: aqui es Xorg de verdad, asi que **xrandr si manda**.

El arreglo va en `~/.xinitrc`, que es del usuario y no necesita root, antes de
`/opt/galauncher/startfe-X.sh`:

```bash
if xrandr --query | grep -q "^VGA-1 connected" ; then
    xrandr --output VGA-1 --primary --pos 0x0 --output LVDS-1 --off
fi
```

El `if` no es adorno: sin CRT enchufado la cabina tiene que seguir arrancando en
el panel en vez de quedarse sin ninguna pantalla. Verificado en la cabina:
`Screen 0: current 1024 x 768`, `VGA-1 primary`, `LVDS-1` apagada.

La tarea `salida` del instalador lo hace sola: lee las salidas conectadas del
kernel (sin necesitar X), y si hay una interna (`LVDS`, `eDP`, `DSI`) y una
externa, ofrece apagar la interna.

### Dos caminos que NO eran

Merece la pena apuntarlos porque parecian obvios:

- **El menu del conector de arranque no existe en esta version.**
  `worker_video_boot_options` (`lib-video.sh:325`), con su lista de
  `[VGA-1 31khz]`, **no lo llama nadie**: es codigo muerto. El menu real esta
  recortado a Monitor Type / Monitor Orientation / Video resolution / X/KMS /
  Tweak geometry, y su opcion 6 «Video resolution» llama a
  `worker_kernel_video_boot`, que solo cambia la RESOLUCION, no el conector.
- **`xorg.conf` tampoco.** `set_xorg_conf` esta marcado `DEPRECATED` en
  `/opt/gatools/video/video.sh` y no lo invoca nadie; no hay `/etc/X11/xorg.conf`
  ni nada en `xorg.conf.d`. X se autoconfigura.

Y una precision que costo una vuelta: **el preset de switchres (`monitor=`) y la
salida fisica son cosas distintas**. Eloy cambio el monitor a `pc_31_120`, que
es lo correcto para su CRT de 31 kHz, y no se movio la imagen: eso solo le dice
a switchres que modelines calcular.

## Apagar una salida mata al frontend: `BadRRCrtc`

Encontrado el 2026-09-03, justo despues de dejar el CRT como unica pantalla.
El frontend dejo de arrancar:

```
X Error of failed request:  BadRRCrtc (invalid Crtc parameter)
  Minor opcode of failed request:  20 (RRGetCrtcInfo)
  Crtc id in failed request: 0x0
```

**Es un fallo de AM+**, en `fe_present.cpp:391`. El bucle que busca la
frecuencia de refresco recorre TODAS las salidas y comprueba que esten
conectadas... pero no que tengan CRTC:

```cpp
if ( output_info && output_info->connection == RR_Connected )
    XRRCrtcInfo *crtc_info = XRRGetCrtcInfo( xdisp, res, output_info->crtc );
```

Una salida **conectada pero apagada** —que es justo lo que deja
`xrandr --output LVDS-1 --off`— tiene `crtc == 0`, y pedir la info del CRTC 0
lanza `BadRRCrtc`, que mata el proceso antes del primer fotograma. Y esa es la
configuracion normal de una cabina: el panel interno apagado para que el
frontend caiga en el CRT.

Arreglado anadiendo `&& output_info->crtc != None`. SFML tiene el mismo patron
en tres sitios (`WindowImplX11.cpp:1319`, `:1390`, `:2132`) pero ahi no revienta,
porque solo mira la salida **primaria**, que por definicion esta encendida.

### Y otra ruta absoluta de la mudanza, esta dentro de un `.pc`

Al recompilar salio esto, que no menciona el problema real:

```
error: 'getMaximumAntiAliasingLevel' is not a member of 'sf::RenderTexture'
```

La SFML que AM+ compila aparte deja su ruta **absoluta** dentro de
`obj/sfml/install/lib/pkgconfig/*.pc`. Tras mover la carpeta, ese `prefix`
apuntaba a `/home/eloy/attractplus`, que ya no existe, asi que el `-I` no valia
y el compilador se caia a la **SFML 2.6.1 del sistema** — donde ese metodo se
llama `getMaximumAntialiasingLevel`, con otra mayuscula.

`instalar.sh` lo corrige solo antes de compilar. Es el mismo tipo de fallo que
los makefiles de genie en `groovymame_src`: rutas absolutas generadas que
sobreviven a la mudanza y fallan diciendo otra cosa.

## Los juegos que iban mal en la cabina: tres causas, no una

Traido por Eloy el 2026-09-03 con una lista de juegos y dos sintomas. El patron
estaba en la lista misma: **los del grupo A eran todos verticales y los del B
todos horizontales.**

| grupo | juegos | sintoma |
|---|---|---|
| A | mappy, centiped, digdug, dkong, frogger, mspacman, ncv2 | sin shader, «va rapidisimo» |
| B | kungfum, elevator, mwalk | shader si, pero descuadrado |

Medido lanzandolos por ssh, que es lo que lo desenredo:

```
mappy    Calculating best video mode for 288x224@60.6 orientation: rotated
         crtc --> 661x496      -waitvsync -syncrefresh    Average speed: 222.72%
kungfum  256x256@56.3 normal
         crtc --> 256x256      -nowaitvsync -nosyncrefresh  Average speed: 100.00%
```

### 1. switchres, en un CRT de PC, hace mas mal que bien

Genera modelines a la resolucion **nativa** del juego. Eso es exactamente lo
que se quiere en un monitor de recreativa, y un desastre en un multisync VGA:
a Kung-Fu Master le mandaba un modo de **256x256** —de ahi el «se ve corrido a
la derecha y no cubre la pantalla»— y a Mappy uno de 661x496 al doble de
frecuencia, con `-syncrefresh` puesto, asi que el juego corria a **222%**.

Probado con cuatro presets (`pc_31_120`, `arcade_31`, `vesa_1024`,
`generic_15`): todos dan modos raros y velocidades mal. Con `-noswitchres`,
mappy, kungfum y centiped a **100.00%** y a 1024x768.

Por eso `tarea_crt` ahora **pregunta que monitor es**: en uno de recreativa
switchres se deja, y en un CRT de PC se apaga.

### 2. Mi propio parche guardaba las decisiones de switchres

El parche de `parches/groovymame-guardar-ajustes-video.patch` hace que MAME
conserve `keepaspect` y `scale_mode`. Eso es lo que se quiere cuando los cambia
una persona... pero **switchres los reescribe en cada arranque** con lo suyo
(`autostretch`), y quedaban grabados en el `.cfg` como si fueran del usuario:

```
centiped, dkong, mapacman, mappy, qbert   scalemode="4"
elevator, kungfum, mwalk                  keepaspect="0" scalemode="4"
```

Que es **exactamente** la division en grupos que trajo Eloy. `scalemode=4` es
escalado entero: Mappy salia a 2x (448x576 en una pantalla de 768) en vez de
llenar, y con dos pixeles por linea el shader no tiene sitio para dibujar nada.

### 3. Y un `.cfg` fijaba la cadena a `default`

`mappy.cfg` tenia `chain="default"`, o sea sin shader. MAME guarda la cadena en
uso por juego, asi que basto con que una vez corriera sin ella.

### Como quedo, medido

| | antes | despues |
|---|---|---|
| mappy, area activa | 448x576 | **574x768** (lo correcto para un vertical) |
| mappy, modulacion entre columnas | 4.5% | **52.6%** |
| kungfum | modo 256x256 | **1024x768**, 63.3% de modulacion |
| velocidad | 222% | **100%** |

`tarea_crt` limpia ahora los `.cfg` por juego: la cadena, el escalado y el
aspecto. Lo que el usuario elija **despues**, con switchres ya apagado, se
guarda y se respeta -- que es justo para lo que estaba el parche.

## El vsync mata el arranque acelerado (y por que parecia intermitente)

Traido por Eloy el 2026-09-04: *«hay un problema con el plugin de aceleracion,
a veces funciona y a veces no; en digdug no funciona, en mappy tampoco, en los
simpsons tampoco»*. **Eran DOS causas distintas a la vez**, y las dos las habia
metido yo o quedaban de una sesion de ajuste.

### 1. `waitvsync 1`, que habia encendido ese mismo dia

El vsync bloquea cada intercambio de buffer hasta el barrido del monitor. Da
igual que `creditos.lua` ponga `video.throttled = false`: **la emulacion no
puede pasar de los 60 Hz del monitor**. Medido con `-str 4`, o sea con toda la
medida dentro de la ventana de arranque:

| juego (refresco de la placa) | con `waitvsync` | sin `waitvsync` |
|---|---|---|
| digdug (60,606 Hz) | 99% | **230%** |
| mappy (60,606 Hz) | 99% | **230%** |
| simpsons (59,186 Hz) | 101% | **143%** |
| kungfum (56,338 Hz) | 107% | 143% |

**Ahi esta el «a veces si y a veces no»**: los juegos por DEBAJO de 60 Hz aun
ganaban un poco, porque el techo del monitor queda por encima del suyo; los de
60,606 no ganaban absolutamente nada. No era intermitente, dependia del
refresco de cada placa.

> **Regla: en esta cabina `waitvsync` va a 0.** El desgarro es un precio
> pequeno al lado de perder el arranque tapado.

### 2. `negro=0` en esos tres juegos, de una tanda de ajuste

Y aunque la aceleracion funcione, esos tres seguian ensenando el test de la
placa, porque su linea de `arranque.dat` traia el modo de ajuste:

```
simpsons velocidad=0 indicador=1 segundos=11 negro=0
mappy    indicador=1 segundos=13 negro=0
digdug   indicador=1 segundos=8 negro=0
```

`negro=0` acelera pero **no tapa la pantalla** — es justo para ver el efecto de
la velocidad mientras se ajusta un juego. Eran los tres unicos del fichero con
esa marca, y son exactamente los tres que Eloy nombro. Quitado `negro=0` y
tambien `indicador=1` (el cartel `>> CARGANDO AL 300%`), que es del mismo tipo.

**Verificado con captura**: a los 2 s la pantalla esta a negro absoluto
(maximo 0) en los tres, y a los 14 s ya se ve el juego.

**Cuidado al editar `arranque.dat` a mano:** en esa tanda se perdieron dos
lineas que hacian falta, `mwalk nvram=0 segundos=10` y
`kungfum segundos=0 velocidad=100`. La de `mwalk` importa: sin `nvram=0`,
Moonwalker vuelve a arrancar con los creditos que guardo la sesion anterior.

## Moonwalker: los creditos viejos TAPABAN la cinematica

Traido por Eloy el 2026-09-04: *«sigue cargando el credito anterior, y ademas
seria bueno que muestre la cinematica del inicio; para ello desactive las
configuraciones del arranque, pero no me las toma»*. Parecian dos problemas y
un ajuste que no se aplicaba. **Era una sola causa y sus ajustes SI se
aplicaban.**

**La causa: el fichero de NVRAM que ya estaba escrito.** `nvram=0` evita
**guardar**, no **cargar** — eso ya estaba documentado, pero no la consecuencia:

> Moonwalker **no reproduce su modo de atraccion mientras tenga creditos
> dentro**. Se queda fijo en «PUSH START BUTTON / CREDITS 6».

Verificado con una tira de capturas: con la NVRAM vieja, 22 segundos clavado en
la pantalla de titulo con `CREDITS 6`. Borrando
`~/.mame/nvram/mwalk/nvram` una vez, sale la secuencia entera — avisos legales,
animacion, logo, **la cinematica de los retratos a los 32 s** y demo con
`CREDIT 0`. Y la NVRAM **no se vuelve a crear**, porque `nvram=0` ya estaba
puesto y funciona (lo dice el log: `nvram=0: esta partida no guardara su
NVRAM`).

**Regla general:** cuando un juego «arranca con creditos», hay que hacer las dos
cosas — `nvram=0` en `arranque.dat` *y* borrar el fichero una vez. Solo con la
primera, el sintoma sigue igual y parece que el ajuste no se aplica.

### Y Moonwalker casi no se puede acelerar

Al proponer un arranque tapado corto en vez de `segundos=0`, medido: mwalk sin
freno llega a **~139%**, porque es un Sega System 18 con dos 68000 y lo limita
la CPU, no la GPU. O sea que tapar 20 s de juego cuesta **14 s reales de
pantalla negra**. Para este juego **`segundos=0` es lo correcto**, que es justo
lo que Eloy habia puesto.

Comparalo con lo que se gana en placas ligeras, medido el mismo dia:
mspacman 561%, digdug 230%, mappy 230%, dkong 212%, frogger 206%,
simpsons 143%. **La aceleracion vale mucho en los clasicos de 8 bits y casi
nada en los de 16.**

### Que juegos siguen expuestos

De los que guardan NVRAM, los que estan en `creditos.dat` con direccion
verificada (`qbert`, `tapper`, `rbtapper`) los limpia el barrido al arrancar.
Los que **no** estan (`mwalk`) solo se arreglan con la receta de arriba.

## Puntuaciones sin créditos: `puntajes.py` (resumen)

Encargo de Eloy (2026-09-05): conservar los puntajes de cada juego **sin**
arrastrar créditos entre sesiones, en un JSON, descartando los nombres de
fábrica. El detalle a fondo —cómo se localiza y descifra la tabla de cada juego—
está en **`docs/puntajes.md`** y **`docs/direcciones-ram.md`**; las recetas por
juego, en `creditos/puntajes.dat`. Aquí, el método y las reglas que no hay que
reaprender.

**Las piezas:**

- El plugin `hiscore` de MAME lee la tabla de la RAM y la escribe en
  `<homepath>/hiscore/<juego>.hi`, pero **solo cuando la tabla CAMBIA** respecto
  al arranque: un juego que nadie ha jugado no deja `.hi`.
- `hiscore.dat` (de MAME) dice **dónde** vive la tabla; **hi2txt-xml** (base
  comunitaria GPL-2, se baja aparte, `--hi2txt`) dice **cómo** se lee por dentro;
  `creditos/puntajes.dat` lleva nuestras recetas propias.
- `puntajes.py` (fuera de MAME, se puede lanzar con la cabina apagada) junta las
  tres fuentes → `~/.attract/puntajes.json`. `volcar.lua` + `--fabrica` leen la
  tabla de la RAM cuando no hay `.hi`; `--capturar` apunta la de fábrica para
  marcar los nombres ficticios.

**Reglas que costaron y conviene no repetir:**

- **Una receta no está confirmada hasta compararla con el marcador EN PANTALLA.**
  «Ese número no puede ser» no es prueba (dkong, tmnt). `confirmado=true` solo
  para las vistas en pantalla.
- Un **`.hi` que existe va SIEMPRE primero**; el orden del XML decide entre las
  demás fuentes. Una **fuente vacía** (toda `0x00`/`0xFF`) no es una fuente.
- **Capturar la tabla de fábrica con `-noplugins`**: el plugin hiscore reinyecta
  el récord guardado y contamina la captura. Un juego con NVRAM propia la carga
  igual; ahí la marca es «no se sabe», nunca «de fábrica».
- Un script que mide cobertura debe llamar a la MISMA función que exporta.
- **«No cambió al jugar» NO prueba que no guarde**: puede ser que esa partida no
  entró en la tabla. Y dejar un NeoGeo en atracción puede pisar un récord real.
- La NVRAM es el hueco que queda: «números que bajan» en un binario de KB da
  falsos positivos; se ancla con un número conocido (de `db_defaults`, del
  marcador, o jugando y diciéndolo).
- Trampas de formato, todas **mudas**: BCD empaquetado vs un dígito por byte;
  `table-index=loop_reverse_index` (tabla al revés); `byte-swap=2` (NeoGeo,
  mwalk, goldnaxe); `byte-trim` (relleno que se cuela, galaga); `<loop start=N>`;
  `base=16` con `nibble-skip` es decimal, no hex; `*10`/`+1` implícitos;
  `<sameas>` (2322 de 3102 XML son redirecciones); `rotar=`/`orden=asc` de
  `puntajes.dat`.
- El rescate se probó de extremo a extremo (`rescate.lua`): cambiar un byte del
  bloque, salir, y comprobar que el `.hi` coincide byte a byte (13 juegos, con
  `missile` que usa un SHARE y los Williams por nibbles).

`correr.sh` pasa `luac -p` sobre los `.lua` de `creditos/`: en la cabina el `lua`
es **5.5** (la variable de control de un `for` es const) y el nuestro 5.4 no lo
detecta.

## Compilar GroovyMAME parcheado en GroovyArcade

`parches/compilar-en-arch.sh`. El release con el binario ya compilado **no
sirve ahí**: está hecho en Ubuntu 24.04 y exige glibc 2.38, y aunque arrancara,
GroovyArcade ya trae su GroovyMAME con switchres funcionando de verdad.

El script **no toca nada del sistema**: compila a
`~/.local/share/groovymame-cabina/`, que es donde `instalar.sh` lo busca, y el
`groovymame` de la distro se queda intacto. Volver atrás es borrar esa carpeta.

Detalles que lleva dentro:

- **Clona la versión que ya está instalada**, no una cualquiera: lee
  `groovymame -version` y traduce `0.264` a la rama `mame0264`.
- Los parches se aplican con `--dry-run` primero, para no dejar las fuentes a
  medias si no encajan.
- `pacman -Si` antes de instalar, porque pacman aborta la instalación entera si
  un solo nombre no existe en esa versión de los repos.
- Comprueba que haya 12 GB libres, y si la compilación falla sugiere
  `TRABAJOS=1`, que es lo que suele pasar en un mini-PC: se queda sin memoria.

**No está probado en Arch** — aquí no hay ninguna máquina Arch. Lo que sí está
probado es que se niega a correr donde no toca.

## Que corra en cualquier distro, no solo en Ubuntu

Encargo de Eloy el 2026-09-05. Cuatro fallos de portabilidad, y **ninguno da la
cara en esta maquina**: los cuatro se manifiestan sólo en la distro que no es.

### 1. `instalar.sh` decia soportar Fedora y no era verdad

Es el que peor pinta tenia, porque el soporte estaba **a medias y en silencio**.
`GESTOR=dnf` se detectaba y habia rama de instalacion, pero `columna()` decia:

```bash
[ "$GESTOR" = pacman ] && echo 3 || echo 2      # o Arch, o Debian
```

O sea que en Fedora se llegaba a `sudo dnf install libx11-dev build-essential`,
con **todos** los nombres equivocados. No es que faltara una columna: es que la
que habia estaba mal y no lo decia.

**La solucion para las librerias no es otra tabla.** En las distros de RPM, rpm
genera solo un *provides* virtual por cada `.pc` que instala un paquete, asi que:

```bash
sudo dnf install "pkgconfig(x11)"        # encuentra el paquete se llame como se llame
```

Encaja con lo que el fichero ya hacia —la primera columna de la tabla **ya era**
el modulo de pkg-config— y no hay nombres que mantener. Sólo `HERRAMIENTAS`
(binarios: `gcc-c++`, `cmake`…) y `LIBRERIAS_EMULADOR` (las `.so` que pide `ldd`)
necesitan nombres de verdad, y ahi si hay cuatro columnas.

Ahora `elige()` reparte por gestor y `instalar_rpm()` **criba antes de instalar**
con `dnf repoquery --whatprovides` o `zypper search --provides`, por el mismo
motivo por el que ya se hacia en Arch: un nombre que no existe aborta la
instalacion entera, y perder veinte paquetes por uno no vale la pena.

Comprobado generando la lista que pediria cada gestor: apt y pacman dan lo mismo
que antes (no hay regresion), dnf y zypper dan nombres coherentes. **Instalar de
verdad en Fedora u openSUSE no se ha probado: aqui no hay ninguna maquina.** Por
eso la criba previa importa tanto.

### 2. ImageMagick 7 no instala `convert`

`aspecto.sh` e `integracion.sh` llamaban a `convert` e `identify`. La version 7
—Arch, Fedora 41+, Debian 13— trae **un solo `magick`** que hace de los dos.
Ubuntu 24.04 todavia lleva la 6, asi que aqui no se ve.

Se elige el que haya, y en arrays (`"${CONVERTIR[@]}"`) porque en la 7 la orden
son **dos palabras**: `magick identify`.

### 3. Cada script suponia la ruta de las roms de Debian

`/usr/share/games/mame/roms` sólo existe en Debian y derivados. La forma buena ya
estaba inventada en `instalar.sh` (`mame_opcion()`, preguntarle a MAME con
`-showconfig`) y `videos.sh` ya la usaba; los otros cuatro no.

Ahora esta en **`creditos/comun.sh`**, que cargan los cinco. Y al escribirlo
aparecio una trampa que la version de `videos.sh` tampoco cubria:

> **El rompath son VARIAS rutas separadas por `;`.** En esta maquina MAME declara
> `$HOME/mame/roms;/usr/local/share/games/mame/roms;/usr/share/games/mame/roms`,
> y las roms estan en la **tercera**.

Quedarse con «la primera que exista» —que fue mi primer intento— habria
encontrado **11 juegos en vez de 112**, sin dar ningun error. Se devuelven todas
y busca MAME, que para eso las declara. Para los `find` que enumeran roms,
`listar_roms()` recorre todos los directorios que existan.

Verificado con `aviso_mame.sh`, que lanza MAME de verdad: 56 comprobaciones en
verde con las rutas nuevas.

### 4. El binario de 7-Zip no se llama igual en todas partes

`importar_cheats.py` exigia `7z` y su mensaje de error decia `apt install
p7zip-full`. En Arch y Fedora el paquete `7zip` trae **`7zz`**, no `7z`. Ahora
prueba `7z`, `7za`, `7zz` y `7zr`, y el mensaje da el paquete de cada distro.

### Y lo que se quito del repositorio

- **`creditos/__pycache__/*.pyc`**: generados, y atados a Python 3.12, que es
  justo lo contrario de lo que se busca. Ignorados desde ahora.
- **`creditos/sq`**: un ELF **x86-64** de 386 KB que entro con el `git subtree` y
  al que no llama nadie. `pruebas/correr.sh` ya se compila su propio `sqhost` en
  cada maquina, que es lo correcto: un binario versionado no arranca en ARM.
- `sandbox.py` se fue de la raiz a **`arduino/`**, con `Arcade.ino`, que es su
  pareja: no es basura, es el banco de pruebas del puerto serie de Eloy.
- `contador_arduino.py` y `arduino/sandbox.py` no tenian **shebang**, asi que `./contador_arduino.py`
  no funcionaba.

### Aviso para las tres sesiones: `git add -A` barre lo ajeno

Con tres sesiones en el mismo arbol, un `git commit -a` se lleva lo que las otras
tengan a medias en el indice. Paso: el commit `53a8227`, que hablaba de
puntuaciones, se llevo dentro esta limpieza entera. No se perdio nada, pero el
mensaje describe la mitad de lo que hay. **Stagear por ruta.**


## Dragon's Lair no va en MAME: va en Hypseus (Daphne)

Decidido por Eloy el 2026-09-05 tras probarlo en la cabina. Los sintomas que
traia eran tres: *«se salta muchas partes»*, *«no se escucha el audio del modo
attract»* y *«se ve todo muy confuso para el usuario»*.

**Yo defendi la via de MAME con mediciones que no cubrian lo que el veia**, y me
equivoque. Conviene apuntar por que, porque el error es facil de repetir:

- Medi que el emulador va al 100,00%, que los CHD son exactos (SHA1 correcto,
  driver `status="good"`) y que los cinco mandos llegan al puerto que lee la
  placa. Todo cierto, y todo insuficiente.
- **Todas mis pruebas llevaban `-sound none`**, asi que el sintoma del audio no
  lo habria detectado nunca.
- Y comprobar que las señales llegan al chip NO es comprobar que las escenas
  salgan en el orden correcto. Lo del puente levadizo saltado se me escapaba por
  diseño de la prueba.

Lo unico que si arregle en MAME se queda: `dlair segundos=0` en `arranque.dat`,
porque el arranque tapado le metia 900 frames (`GA_ARRANQUE_SIN`, al no estar en
`creditos.dat`) sin freno y con frameskip 10 — o sea 15 segundos de pelicula a
camara rapida. **A un laserdisc no se le acelera el arranque nunca**: no hay
carga que tapar, hay pelicula que reproducir.

### Como se convierte el CHD al formato de Daphne

Las piezas que pide Hypseus son cuatro, y **las ROMs ya las tienes**: su set
`lair` son los mismos cuatro `dl_f2_u*.bin` del `dlair.zip` de MAME, con los
mismos CRC. No hay que bajar nada.

```bash
chdman extractld -i dlair.chd -o dlair.avi          # 29 GB, unos 4 minutos
ffmpeg -i dlair.avi \
  -vf "crop=720:480:0:44,fieldmatch,yadif=deint=interlaced,decimate,scale=640:480" \
  -pix_fmt yuv420p -c:v mpeg2video -b:v 5000k -an -f mpeg2video lair.m2v
ffmpeg -i dlair.avi -vn -c:a libvorbis -q:a 5 -ar 44100 lair.ogg
```

De 29 GB se queda en **815 MB**. Cuatro cosas que costaron y que no son opcionales:

- **`crop=720:480:0:44`**. El CHD sale a 720x**524**: esas 44 lineas de mas son
  los datos VBI del laserdisc, y se ven como una franja rayada arriba.
- **`-pix_fmt yuv420p`**. Sin forzarlo, ffmpeg elige 4:2:2 (porque la fuente es
  `yuyv422`) y **Hypseus vuelca a una textura `SDL_PIXELFORMAT_YV12`, que es
  4:2:0** (`video/video.cpp:2013`). Los planos de croma miden el doble de lo que
  espera y se leen desplazados: **colores raros**. Era justo lo que Eloy veia.
- **Quitar el telecine** (`fieldmatch`+`decimate`). La animacion es de 24 fps
  llevada a 29,97; el tutorial del propio Daphne exige 23,976 para este juego.
- **`extractld`, no `extractav`**: en chdman moderno se llama asi. Y `chdman` no
  se construye con `make TOOLS=1` a secas — hace falta **`REGENIE=1`**, o sale
  con codigo 0 sin hacer nada porque los makefiles no traen ese objetivo.

### Version: v2.12.1, no la ultima

La actual (v3.0.2) exige **SDL3**, que no existe en los repos de Ubuntu 24.04
aunque si en Arch. La `v2.12.1` es *«the last sdl2 version»* y SDL2 esta en las
dos, asi que **lo que se prueba en el portatil es lo que corre en la cabina**.
Sus mejoras son de SDL3 (arreglan fallos que el propio SDL3 introdujo) y ninguna
toca laserdisc. Si algun dia se sube, la forma correcta no es meter sdl3 en la
tabla de paquetes sino comprobar `pkg-config --exists sdl3` y elegir rama.

### Aparece mezclado en la misma lista, y eso tiene truco

Eloy lo pidio asi: que no se note que usa otro emulador. Sale gratis porque
**`--build-romlist` acepta VARIOS emuladores con un solo `-o`** y cada entrada
lleva el suyo en la tercera columna:

```bash
attractplus --build-romlist groovymame hypseus -o groovymame
```

> **Trampa: reconstruir la lista con un solo emulador BORRA a Dragon's Lair sin
> avisar.** Hay que pasar los dos siempre.

Pero la primera pasada dejo `lair;lair;hypseus;;;` — sin titulo ni datos, y en el
menu cantaba. Hypseus no tiene `-listxml`, asi que AM+ no tenia de donde sacarlos.
La salida es **`import_extras`, que acepta un XML en formato listxml**
(`scraper_general.cpp:252`): `config/cabina/laserdisc.xml` le da titulo, año,
fabricante y controles, y la entrada queda indistinguible de las de MAME.

Tres detalles mas de `hypseus.cfg`:

- **`workdir` es imprescindible**: hypseus busca `./roms`, `./ram` y `./pics` con
  rutas relativas, y lanzado desde otro sitio no encuentra ni sus ROMs.
- **`[name]`, no `[romfilename]`**, para que la misma linea valga para cualquier
  laserdisc que se añada despues.
- El video vive en `~/shared/roms/daphne/` y `vldp/lair/` solo tiene **enlaces**,
  para no duplicar 815 MB.

Y `dlair.zip` sale del rompath de MAME (a `retirados/`), o los dos emuladores se
pelearian por el mismo juego.

## Conmutar el vídeo solo: CRT si lo hay, panel si no (`pantalla-auto.sh`)

Pedido por Eloy el 2026-09-10: un servicio que detecte si hay un CRT en el VGA y
mande el vídeo allí, y al panel interno si no lo hay. Temporal y desactivable en
cualquier momento.

**Lo que parecía el bloqueo, y no lo era.** La cabina arranca con
`video=VGA-1:e video=LVDS-1:d`, y ese `:d` deshabilita el panel **en el kernel**:
aparece `disconnected` en `/sys/class/drm` y **X no lo ve en absoluto**. No está
apagado y encendible con xrandr — no está. Así que media función parecía exigir
tocar GRUB y reiniciar, que es justo lo que no se quería.

**Se deshace en caliente.** Escribiendo `on` en el `status` del conector vuelve a
la vida sin tocar GRUB ni reiniciar. Medido: pasa a `connected` y ofrece su modo
nativo `1366x768`. Por eso el guion actúa **primero sobre el conector** y sólo
después sobre xrandr.

Y al revés, apagar el conector que no se usa es **mejor** que `xrandr --off`: una
salida `connected` sin CRTC hace que AM+ pida `XRRGetCrtcInfo(0)` y reviente con
`BadRRCrtc` (`fe_present.cpp:391`). Dejándola `disconnected` a nivel de kernel,
X ni la considera.

### Que la detección del VGA sea REAL hay que comprobarlo

El `video=VGA-1:e` **fuerza** el conector a «conectado», así que `status` podría
estar mintiendo y el demonio mandaría el vídeo al panel dejando el CRT negro.
Se midió quitando el forzado (`echo detect > status`): sigue `connected` y
entrega un **EDID válido de 128 bytes** (AOC), con `1280x1024` entre sus modos.
La detección es de verdad y se puede construir encima.

Por eso el demonio escribe `detect` antes de leer, en cada vuelta: **el VGA no
tiene una línea de «me han enchufado» fiable**, así que esperar un evento de
udev no vale — hay que pedirle al kernel que compruebe.

### La resolución NO se toca

Primer intento: fijar `1280x1024`, que es lo que dice este documento. **Estaba
mal**: la cabina está a `1024x768`, así que habría cambiado la resolución en cada
conmutación sin que nadie lo pidiera. La regla es la de menor sorpresa — si la
salida ya está encendida con un modo, no se le toca; sólo se elige modo cuando
hay que encenderla, y entonces `--auto`.

### Cómo se desactiva, en tres niveles

| | qué hace |
|---|---|
| `sudo pantalla-auto.sh pausar` | el servicio sigue vivo pero no toca nada (fichero de freno) |
| `systemctl disable --now pantalla-auto` | lo para y no vuelve a arrancar |
| `sudo pantalla-auto.sh desinstalar` | lo quita todo y devuelve los conectores al estado de arranque |

Y `crt` / `panel` fuerzan una salida a mano.

### Verificado ejecutándolo en la cabina

- Con CRT: `VGA-1 primary 1024x768`, panel `disconnected`, resolución intacta.
- Sin CRT (probado apuntando a un conector vacío de verdad y con la orden
  `panel`): `LVDS-1 primary 1366x768` y VGA apagado. **El vídeo se mueve.**
- Con el freno puesto **respeta un cambio manual** 12 s sin deshacerlo; al
  quitarlo **recupera el CRT solo** en 4 s.
- Desinstalación limpia: unidad, binario y conectores como al arrancar.
- Sobrevive a que X se cierre, y **reaplica cuando X aparece**: el servicio
  arranca antes que Xorg, así que sin eso la parte de xrandr no correría nunca.

**Pendiente:** no se ha probado un arranque completo de la cabina.

Y una falsa alarma que conviene dejar escrita, porque cuesta media hora: probando
esto levanté X con `startx` a secas y no aparecía ningún proceso de
`attractplus`. **No es un fallo, es el diseño.** `startfe-X.sh:14` hace
`[[ -z $FE ]] && FE=lxde`, o sea que un `startx` pelado arranca el ESCRITORIO.
Para el frontend hay que pasar la variable — `FE=attractplus startx` — que es lo
que hace `startfe.sh` leyendo `frontend=` de `ga.conf`.

## Missile Command: por qué no sabías si tu moneda entró

Traído por Eloy el 2026-09-11: *«ingreso un crédito y no sé si se ingresó; tampoco
hay un contador de créditos»*. La respuesta es que **sí hay contador, pero es muy
fácil no verlo**, y de paso salieron dos fallos nuestros.

### Lo que la placa hace de verdad

Missile Command avisa de DOS maneras, y ninguna es un número fijo:

- **Las luces de los botones START parpadean.** Medido leyendo las salidas
  `led0`/`led1` del driver: 0 créditos → apagadas; 1 crédito → parpadea la de
  1 jugador; 2 o más → parpadean las dos. Al pulsar START se consume uno y la
  segunda se apaga. **En un mueble sin esas lámparas conectadas, esta señal
  simplemente no existe.**
- **El rótulo de abajo cambia.** Con 0 créditos va pasando
  `GAME OVER / INSERT COINS / 1 COIN 1 PLAY / ATARI © 1980`; con créditos pasa a
  `PRESS START / CREDITS: N / ATARI ©`. O sea que el número SÍ está, pero
  **dentro de un texto que se desplaza**, así que si miras en el momento
  equivocado ves «ATARI ©» y te quedas igual.

> **Corrección:** yo afirmé primero que este juego «no tiene contador de
> créditos». **Es falso** y lo desmintió una captura: pone `CREDITS: 2`. Lo dije
> porque en mis primeras pruebas la moneda nunca llegaba a entrar, por el fallo
> de la sección siguiente, así que nunca vi ese estado.

### Y el DIP de fábrica pide DOS monedas

El valor por defecto de MAME para `missile` es **2 Coins / 1 Credit**
(`PORT_DIPNAME(0x03, 0x01, ...)`). Con una sola moneda no pasa absolutamente
nada. En la cabina nuestra pasada de `poner_1c1c.sh` lo dejó en 1C/1C
(`missile.cfg`, `mask="3" value="0"`), pero conviene comprobarlo si el síntoma
reaparece.

### El fallo de mi banco de pruebas: `set_value` es PEGAJOSO

Mis tres primeras mediciones decían que la moneda no entraba nunca. Era mentira,
y la culpa era del guion de prueba: **`campo:set_value(1)` se queda puesto**
hasta que alguien escribe `set_value(0)`. O sea que yo dejaba el interruptor de
la moneda *pulsado para siempre*, y una placa de Atari eso lo lee como monedero
atascado y lo ignora.

Lo destapó una **prueba de control con Pac-Man**, cuyo contador conocemos: allí
entraba la primera moneda y no la segunda. `creditos.lua` ya lo hacía bien, con
un comentario que dice literalmente «garantiza soltar la moneda»; el que se lo
había saltado era yo.

> **Regla:** una moneda simulada son DOS órdenes, pulsar y soltar. Si sólo
> pulsas, el primer crédito entra y ninguno más, y el síntoma parece de la placa.

### La dirección que teníamos era imposible

`creditos.dat` traía `missile @:maincpu,program,800c3364 # (cheat)`. Un 6502
direcciona 64 KB: esa dirección **no puede existir**. Venía de la colección de
cheats y por eso nunca se pudo leer nada.

La de verdad es **`0x66`**, y hubo que buscarla midiendo porque Missile Command
es un caso raro por partida doble:

- **Todo su mapa de memoria es un trampolín** (`0000-ffff` a `trampoline_r/w`),
  sin un solo tramo declarado como RAM. Por eso `buscar_creditos.lua` nunca
  encontró nada: barre las entradas de tipo `ram` y aquí no hay ninguna.
- **Usa la misma memoria para las variables y para el bitmap**, y leer por el
  espacio de la CPU pasa por `trampoline_r`, que llama a `load_madsel()` — un
  efecto secundario que puede corromper su vídeo. Hay que leer por el **share**
  `:videoram`, que es la misma memoria sin disparar nada.

Cómo se aisló, barriendo 0, 1, 2 y 3 monedas: tres bytes (`0x29`, `0x66`,
`0x68`) seguían la cuenta exacta. La prueba funcional los separó — al pulsar
START, `0x29` se queda en 3, `0x68` se va a 0 y **sólo `0x66` baja a 2**.
Y escribiendo *sólo* en `0x66`: con 3 las luces parpadean (233 frames de 300
encendida) y con 0 se apagan (1 de 300), así que el barrido también funciona.

### «A veces carga 2 créditos»: no es un fallo, es un DIP

Eloy, 2026-09-11, ya con el contador puesto: *«a veces carga 2 créditos… pasó de
3 a 5, de 8 a 10»*. Sus dos ejemplos son la pista entera: **son la 4ª y la 8ª
moneda**.

La causa es un DIP de la placa, `"Bonus Credit for 4 Coins"` (`R8:!3`), y **su
valor de fábrica es `Yes`**: cada cuatro monedas regala un crédito.

Reproducido metiendo ocho monedas de una en una, con la tarifa en 1C/1C:

```
moneda 1 -> 1     moneda 5 -> 6
moneda 2 -> 2     moneda 6 -> 7
moneda 3 -> 3     moneda 7 -> 8
moneda 4 -> 5  <- +2     moneda 8 -> 10  <- +2
```

Clavado con lo que vio. Poniendo el DIP en `No`, la progresión es regular.

**No lo toca `tarifa.lua`**, y por un motivo de fondo que conviene entender: ese
módulo ya prefiere deliberadamente *la tarifa sin premio* cuando elige entre los
ajustes de `Coinage` (por eso mira los textos con coma, como el
`1 Coin/1 Credit, 2/3` de mwalk). Pero aquí **el premio no está dentro de
Coinage, es un DIP aparte**, así que se le escapa por diseño.

De los juegos instalados, sólo cuatro declaran un DIP de crédito extra y **sólo
Missile Command lo trae encendido**:

| juego | DIP | de fábrica |
|---|---|---|
| `missile` | Bonus Credit for 4 Coins | **Yes** |
| `centiped` | Bonus Coins | None |
| `starwars` | Bonus Coin Adder | None |
| `asteroid` | — | no lo expone |

> **Lo interesante:** esto llevaba ahí desde siempre. Lo que cambió es que ahora
> el contador en pantalla lo hace **visible**, que es justo para lo que se puso.

### Lo que se añadió

- **`creditos.lua` entiende los shares.** El «espacio» de `creditos.dat` puede
  ser `<nombre>/share`, igual que en `hiscore.dat` y que en `volcar.lua`.
- **Contador de créditos en pantalla**, arriba a la derecha: `CREDITOS N`.
  Se apaga con `GA_CONTADOR=0`.

Dos cuidados deliberados en el contador:

- **Sólo se pinta cuando el número es de verdad**: hace falta que la dirección
  esté comprobada (`e.memoria` sobrevive) y que no siga a prueba
  (`e.a_prueba == nil`, que es una importada sin verificar). Enseñar un número
  estimado sería peor que no enseñar ninguno.
- **No se pinta durante el arranque tapado**: ahí la moneda está cerrada y el
  sitio lo ocupa el indicador de carga.

**Trampa al verificarlo:** `screen:snapshot()` **no incluye la capa de
interfaz**, así que el contador no sale en esas capturas — ya estaba escrito
para el cuadro de aviso y volvió a morder. Hay que capturar la ventana: MAME
bajo Xvfb **sin `-nothrottle`**, `xwd -root` y convertir con ffmpeg.

Verificado así: con dos monedas se ve `CREDITOS 2` arriba a la derecha y, en el
mismo fotograma, el propio juego diciendo `CREDITS: 2` abajo. Las 339
comprobaciones de `correr.sh` y las de `aviso_mame.sh` siguen en verde.

## Ocultar juegos del menu sin borrar sus ROMs (2026-09-10)

Pedido por Eloy: Gauntlet, Gauntlet II y TMNT tenian que dejar accesible **solo
la version de 2 jugadores**, y Gradius/Nemesis una sola de las dos. El problema
es que las versiones que se quieren son CLONES, asi que **sus padres tienen que
seguir en disco** aunque no deban aparecer:

| se ve en el menu | oculto, pero el `.zip` se queda |
|---|---|
| `gauntlet2p` Gauntlet (2 Players, rev 6) | `gauntlet` |
| `gaunt22p` Gauntlet II (2 Players, rev 2) | `gaunt2` |
| `gradius` Gradius (Japan, ROM version) | `nemesis` |
| `tmnt2po` TMNT (Oceania 2 Players) | `tmnt` |

Se hace con un **`global_filter`** en el display (`config/displays.cfg`), que se
aplica a TODAS sus pestañas -- si fuera un filtro normal, un juego marcado como
favorito reapareceria en la pestaña de favoritos:

```
global_filter
    rule                    Name not_equals gauntlet|gaunt2|nemesis|tmnt
```

### La trampa: `exception` NO excluye, INCLUYE

AM+ tiene una clausula que se llama `exception` y parece la obvia para esto.
**Hace justo lo contrario**, y su manual lo dice sin rodeos:

> *«If a game does not match a `rule`, then it is not shown. If a game matches to
> an `exception`, then it gets listed no matter what (ignoring the rest of the
> rules in the filter).»*

O sea que `exception` significa «listalo pase lo que pase». Coincide con el
codigo (`FeFilter::apply_filter`, `fe_info.cpp:711`), que ante una excepcion que
encaja devuelve `true` -- aceptar -- y corta. **Usarla aqui habria dejado
visibles exactamente los cuatro que se querian esconder.** Para ocultar, la
unica via es `rule ... not_equals`.

Dos cosas mas que hacen que una sola linea baste:

- **AM+ compara con `regex_match`, o sea coincidencia COMPLETA**
  (`fe_info.cpp:545`). Por eso `tmnt` no se lleva por delante a `tmnt2po`, ni
  `gaunt2` a `gaunt22p`. Con `contains` habria pasado.
- Los targets validos son los de `FeRomInfo::indexStrings` (`Name`, `Title`,
  `CloneOf`, `Year`...) y las comparaciones las de `filterCompStrings`
  (`equals`, `not_equals`, `contains`...).

### `displays.cfg` se REESCRIBE al salir AM+

Del manual: *«changes to this file are only loaded when AM+ first starts, and the
file is overwritten when AM+ exits»*. Editarlo con el frontend abierto es tirar
el cambio. Se toca con AM+ parado.

Comprobar que AM+ entendio la regla es facil por eso mismo: si **sobrevive a un
ciclo de arranque y salida**, la parseo. Y su log lo dice con numeros:

```
sin filtro:  (94 entries from romlist cache)
con filtro:  (94 entries from romlist cache, 90 kept, updated globalfilter cache)
```

**Lo que NO sirve para verificarlo:** el contador `[ListEntry]/[ListSize]` del
layout marcaba `39/89` **igual con filtro y sin el**, asi que no refleja la lista
filtrada. A primera vista parecia confirmar el resultado y no confirmaba nada.

### Gradius o Nemesis

Es el mismo juego de Konami (1985) en dos regiones: **Gradius** en Japon,
**Nemesis** en la exportacion. Se dejo Gradius porque es el nombre con el que se
conoce la saga entera (Gradius II, III, IV, V), mientras que «Nemesis» fue solo
el titulo de exportacion de la primera entrega. Cambiarlo es cambiar una palabra
en esa linea.

## El aviso de salida no siempre saltaba: la estimacion se iba a cero sola

Traido por Eloy el 2026-09-12: *«el aviso de salida con creditos en la maquina
cargados, no siempre funciona... Me pasa por ejemplo cuando juego un buen rato,
ahi salgo y no me avisa»*. La pista buena estaba en «un buen rato»: **no era
intermitente, era acumulativo**.

Son **dos causas encadenadas**, y las dos golpean justo en la partida larga.

### 1. Cada START restaba un credito, aunque el juego lo ignorara

Sin la direccion del contador en la RAM, `aviso.lua` estima
`dentro = entrado - consumido`, y `creditos.lua` llama a `aviso.consume(n)` en
**cada flanco de START**. Pero con la partida ya en marcha **la placa ignora el
START y no gasta nada** -- eso ya estaba medido en este documento, en la seccion
de la busqueda de direcciones («Un solo START»), y no se habia atado con esto.

Reproducido con `lua` a secas sobre el modulo de verdad:

```
3 monedas metidas, 2 creditos sin gastar:
  sale enseguida (0 START extra)   dentro=2  -> AVISA
  2 START de mas                   dentro=0  -> NO AVISA
  partida larga (5 de mas)         dentro=0  -> NO AVISA
```

Y habia un segundo efecto peor: **`consumido` no tenia tope**, asi que la deuda
se arrastraba a las monedas SIGUIENTES. Meter una moneda, jugarla, aporrear
START y meter dos mas dejaba el aviso mudo con dos creditos de verdad dentro.

**El arreglo, sin ninguna heuristica:** `consumido` nunca puede pasar de
`entrado`. Una placa no puede gastar un credito que no esta dentro. Eso cierra
el caso de la deuda arrastrada; lo que la estimacion sigue sin poder distinguir
es un START que empieza partida de otro que el juego tira, y por eso el arreglo
de fondo es el siguiente.

### 2. Y casi ningun juego tenia lectura exacta: la prueba se descartaba SIEMPRE

De los 106 juegos instalados, solo **17** tienen direccion verificada en
`creditos.dat`. Otros **30** la tienen importada de la coleccion de cheats, y
esas se ganan la confianza probandolas: se mira si el byte sube con las monedas.

**Con monedas de verdad no insertamos ninguna al lanzar** (`MONEDAS = 0`), asi
que `e.fase` vale `'fin'` desde el frame 1 y la prueba comparaba el valor
**consigo mismo**. Verificado lanzando Contra:

```
[creditos] la direccion importada 101a no se movio con las monedas (0 -> 0): la descarto y estimo por los START
```

O sea que el descarte era **incondicional y en el primer frame**: 89 de 106
juegos estimaban, y la estimacion se iba a cero sola al jugar un rato.

**El arreglo: la prueba la hace la moneda del JUGADOR.** Cuando no hay monedas
de lanzamiento, `a_prueba` se queda pendiente hasta que entra una moneda de
verdad; ahi se apunta el valor y se comprueba `GA_COMPROBAR` frames despues, que
es el mismo plazo de gracia que ya usaba la devolucion. Verificado en MAME:

```
[creditos] moneda del jugador: entra en la maquina
[creditos] la direccion importada 101a subio de 0 a 1: me fio, a partir de ahora la leo
[P] a_prueba=nil memoria=true dentro=1
```

**Y mientras esta a prueba, el cuadro NO usa ese numero.** Antes el codigo se
apoyaba en que la comprobacion resolvia en el frame 1 y luego `e.memoria` era
nil; ahora la direccion sobrevive hasta la primera moneda, y `fin_del_arranque`
llama a `asentar_ya()`, asi que `memoria.dentro()` devolveria un numero
**asentado pero sin comprobar**. La funcion `dentro` que recibe el aviso
devuelve `nil` mientras haya `a_prueba`: estimar es mejor que anunciar el byte
de una direccion que no sabemos si es el contador.

### Cuantos juegos gana, medido

Barridos los 30 con direccion importada, metiendo una moneda de verdad:

| | |
|---|---|
| **ascienden a lectura exacta** | **15** (1943, atetris, bbredux, commando, contra, dkingjr, dkong3, dkongjr, ffight, galaxian, ncv2, robocop, sf2, snowbros, timeplt) |
| se descartan con razon | 8 (1942, berzerk, bublbobl, gauntlet, mk, mk2, mk3, sf) |
| sin probar aqui | 7 -- **no arrancan en el portatil**, les faltan BIOS o CHD (19xx, arkanoid, btoads, kinst, strhoop, tekken, tekken2). En la cabina si se probaran |

Asi que la cabina pasa de **17 a 32** juegos con aviso exacto, y en esos la
deriva de la estimacion deja de existir por completo.

### La decision de Eloy: estimando, mejor molestar que callarse

Enseñado el arreglo, Eloy volvio con la pregunta de fondo: *«no comprendo la idea
del aviso, es que cuente cuantas veces se presiono el boton de moneda, y se
cuente a partir de ahi»*. La cuenta de monedas **si** es exacta -- se lee el boton
fisico; lo que no se puede saber sin la direccion es la otra mitad, los creditos
que el juego se lleva. Y con eso planteado eligio, que es lo correcto porque no
es una decision tecnica sino de su cabina:

> **En los juegos sin direccion conocida, el aviso salta SIEMPRE que el jugador
> haya metido monedas en esa partida**, diga lo que diga la estimacion.

El razonamiento son los dos errores posibles, que no cuestan lo mismo:

| | |
|---|---|
| callarse de mas | el jugador se deja creditos **pagados** y no se entera |
| molestar de mas | sale un cuadro que se quita pulsando salir otra vez |

Consecuencias, y ninguna es gratis:

- **`a.puede_quedar()`** decide la puerta: con lectura exacta es `dentro() > 0`;
  sin ella, `metido > 0`. Y el cuadro **ya no se quita solo** por llegar la
  estimacion a cero, porque ese cero no significa nada (escenario `7b`).
- **El texto deja de afirmar cuando estima.** Decir «DEJAS 0 CREDITOS» seria
  absurdo y «DEJAS 2» podria ser mentira, asi que pasa a «PUEDEN QUEDAR CREDITOS
  DENTRO DE ESTA MAQUINA». Con la direccion conocida se sigue afirmando
  («DEJAS 2 CREDITOS»), que es justo lo que se gana teniendola. El propio
  encabezado de `aviso.lua` ya pedia ese «pueden quedar» desde el principio; el
  texto no lo cumplia.
- **El que solo entra a mirar sigue sin ser molestado**: la condicion
  `metido > 0` no se toca, y el credito del lanzamiento no cuenta.

Verificado de extremo a extremo en `gng` (sin direccion), metiendo una moneda de
verdad y aporreando START:

```
0 START de mas -> dentro=1 seguro=false cuadro=true   PUEDE QUEDAR 1 CREDITO...
5 START de mas -> dentro=0 seguro=false cuadro=true   PUEDEN QUEDAR CREDITOS...
```

La segunda linea es exactamente el caso que Eloy reportaba, y ahora avisa.

**Trampa al montar la prueba, y volvio a morder:** `creditos.lua` cuenta las
monedas leyendo el **boton fisico** (`entrada:seq_pressed(seq)`,
`creditos.lua:996`), no el campo, porque `set_value` es un OR con la secuencia
fisica y no se pueden distinguir. Mis dos primeros bancos de pruebas metian la
moneda con `set_value` y el contador del script marcaba `metido=0 entrado=0`:
la prueba era invalida y parecia decir que el aviso estaba roto de otra forma.
Hay que sustituir `GA_ESTADO.pulso_moneda.leer`, igual que hace
`pruebas/integracion.sh` con el monedero, **y ademas** pulsar la entrada de
verdad para que el juego conceda el credito. Y la suscripcion del notificador,
en una global, o el recolector se la lleva a mitad.

## Root Beer Tapper decia PRESINSERT COINAYER: el barrido llegaba tarde

Traido por Eloy el 2026-09-12. **Era nuestro**, y es la version completa de lo
que este documento ya insinuaba en «Los creditos que la NVRAM guarda entre
sesiones» sin explicar el mecanismo ni arreglarlo.

### Que pasa

Tapper y Root Beer Tapper guardan los creditos en su NVRAM, asi que arrancan
pintando el rotulo **largo**:

```
CREDIT 4 PRESS 1 OR 2 PLAYER
```

Cuando el barrido escribe 0 en el contador (`e011`), la placa ve el cambio y
repinta con el **corto**. Y su rutina de dibujo **no borra el hueco antes de
escribir**:

```
PRESS 1 OR 2 PLAYER     19 caracteres
    INSERT COIN         11, centrado -> (19-11)/2 = 4 de margen a cada lado

P R E S S _ 1 _ O R _ 2 _ P L A Y E R      <- lo que habia
        I N S E R T _ C O I N              <- lo que estampa encima
P R E S I N S E R T _ C O I N A Y E R      <- lo que queda
```

`PRES` + `INSERT COIN` + `AYER`. Sobreviven las cuatro letras de cada extremo.

**En una recreativa de verdad no pasa**, y el motivo importa: alli el contador
nunca cae a 0 en modo atraccion. Baja al pulsar START, y entonces el juego se va
a la partida y repinta la pantalla entera. «El contador cae a cero estando en
atraccion» es un estado que **solo existe porque le escribimos la RAM desde
fuera**: un fallo latente de la placa que nosotros despertamos.

### El arreglo: `barrido=N` en `arranque.dat`

Adelantar la limpieza a **antes de que la placa pinte el rotulo largo**. Si
nunca lo escribe, no hay resto que tapar. En SEGUNDOS, como el resto de tiempos
del fichero:

```
tapper   segundos=3 velocidad=0 barrido=0.5
rbtapper segundos=3 velocidad=0 barrido=0.5
```

Va **apagado y por juego a proposito**. Barrer pronto es escribir en la RAM de
una placa que puede estar autoprobandose, y eso hecho a lo bruto rompe el
arranque -- ya esta documentado con Pac-Man, cuyo test de RAM entraba en bucle.
Solo se pone donde se ha comprobado juego a juego. El disparo vive **dentro del
arranque tapado**: ahi la pantalla esta en negro y el boton de moneda cerrado,
asi que no hay nada del jugador que respetar todavia.

**Medido en la cabina**, con 4 creditos en una copia aislada de la NVRAM:
escribiendo 0 en los frames 5, 10, 30, 60 y 120 el valor **se queda puesto**
hasta el frame 1500 y la pantalla sale limpia (`CREDIT 0 / INSERT COIN`), con el
record `CEG 40975` intacto. Verificado en los dos Tappers.

### Dos trampas del banco de pruebas, las dos mias

- **MAME reescribe la NVRAM al salir**, asi que la pasada con la que reproduje
  el fallo dejo el fichero de prueba **a cero creditos**, y las cinco medidas
  siguientes barrieron un contador que ya valia 0. No median nada y lo parecian.
  El patron tiene que vivir en un directorio aparte y con `chmod a-w`, y cada
  pasada trabaja sobre una copia.
- **`-showconfig` devuelve el `rompath` con `$HOME` SIN expandir**. Pasandolo
  entrecomillado, MAME recibe la ruta literal y no encuentra ninguna rom; el
  sintoma es que el guion no imprime nada, no un error.

## La pasada de `buscar_creditos.sh`: de 17 a 33 juegos con lectura exacta

Hecha el 2026-09-12 sobre los 89 juegos que no tenian direccion verificada. Es
el punto 4 de «Proximos pasos», que llevaba sin hacerse desde el principio.

**Salen 17 direcciones**, y de regalo una comprobacion cruzada de las importadas
de la coleccion de cheats: de las 10 en que ambos metodos opinaban, **9
coinciden** (tres de ellas encontrando ademas una copia espejo que el juego
mantiene a la vez). La unica discrepancia se explica sola -- `1942` tenia `e010`
importada, que la prueba de comportamiento ya habia descartado en tiempo de
ejecucion; la medida dice `e011`.

Siete no estaban en la tabla: `avsp`, `btime`, `ddragon`, `gng`, `mario`,
`megaman`, `zaxxon`.

> **PELIGRO con `buscar_creditos.sh`: REESCRIBE `creditos.dat` entero** con solo
> lo que encuentra en esa pasada (su ultimo bloque es un `> "$SALIDA"`).
> Lanzado a pelo se lleva por delante las **4945 importadas** y las verificadas
> de los juegos que no esten en la lista. Hay que darle `SALIDA=` a un temporal
> y fundir despues. Conviene tambien `CFG_DIR=` a una copia, o las monedas que
> mete la prueba acaban en los `.cfg` de los juegos.

**Y las cifras hay que darlas de la maquina que toca.** Estas salieron del
portatil, que tiene 106 sets; **la cabina tiene 104 y no son un subconjunto**:
alli no estan `19xx`, `tekken3/4/5d`, `tektagt` ni `dkingjr`, y aqui no arrancan
los que necesitan BIOS o CHD (`arkanoid`, `btoads`, `kinst`, `strhoop`,
`tekken`, `tekken2`...). En la cabina el numero real es **33 de 104**, no 34 de
106.

Repasados en la cabina los que aqui no arrancaban: `tekken`, `tekken2`,
`tmnt2po`, `wboy` y `xevious` arrancan pero **ningun candidato responde**, y los
otros cinco no estan instalados alli. O sea que esa via esta agotada para ellos.

## La tecla de salir no tenia antirrebote, y el aviso se contestaba solo

Traido por Eloy el 2026-09-12, y es **la causa de verdad** del «no siempre
avisa» que arrastraba desde el principio: *«estaba jugando 1943, ingrese 3
creditos, aparecio un contador arriba... y aun asi el aviso no aparecio»*.

Su dato descartaba media investigacion de golpe: **el contador en pantalla lee
`e.memoria.dentro()`, exactamente la misma fuente que el cuadro**. Si el
contador marcaba 3, el aviso veia 3. Asi que la cuenta no era el problema.

### Lo que era

Un microinterruptor abre y cierra varias veces en unos milisegundos al
pulsarlo. El **boton de moneda** ya tenia antirrebote desde el 2026-08-29
(`monedero.lua`, `M.pulsador`, 8 frames), porque esto mismo ya habia mordido
alli. La **tecla de salir no tenia ninguno**: `a.frame()` recibe el nivel y
calcula el flanco a pelo. O sea que una sola pulsacion daba **dos flancos**, el
primero pintaba el cuadro y el segundo lo confirmaba tres frames despues.

El jugador ve que no avisa. Lo que pasa es que aviso y se contesto solo.

Y explica el «a veces si y a veces no» sin mas: **el rebote de contactos es
aleatorio**.

### Como se probo, que es lo que faltaba desde siempre

Este documento ya avisaba de que `aviso_mame.sh` **finge la tecla** sustituyendo
la funcion que la lee, y que esa es la limitacion de la simulacion. O sea que
**la pulsacion real nunca se habia probado**, y el fallo vivia justo ahi.

En la cabina no hay `xdotool`, asi que la pulsacion se inyecta con **XTEST por
`ctypes` sobre `libXtst`**, que no necesita instalar nada (esta en las dos
maquinas). Con MAME corriendo bajo un `Xvfb :77` y 1943 con tres creditos
dentro, medido en la cabina:

| patron de la tecla | antes | despues |
|---|---|---|
| ESC limpio, 400 ms | frena la salida | frena la salida |
| **rebote: 20 ms, hueco de 25, y la pulsacion buena** | **`salida confirmada`, MAME SE CIERRA** | **frena la salida** |
| dos pulsaciones deliberadas, 1,2 s entre ellas | sale | sale |

### El arreglo

`guarda` en `aviso.lua`: durante **15 frames (~250 ms)** tras pintar el cuadro
no se acepta la confirmacion. Una persona que lee «SALIR otra vez para salir»
tarda mucho mas que eso. Se ajusta con `GA_AVISO_GUARDA`.

Es el mismo arreglo que ya tenia la moneda, en el boton al que no se le puso.

### Y de paso, lo que se aprendio del mando de la cabina

Preguntado a MAME desde Lua, no supuesto:

```
UI_CANCEL   seq=[KEYCODE_ESC]
UI_MENU     seq=[KEYCODE_TAB ... OR JOYCODE_1_BUTTON9]
UI_SELECT   seq=[KEYCODE_ENTER ... OR JOYCODE_1_BUTTON1]
dispositivos: PS4 Controller, Xinmotek Dual Controller x2, System keyboard
```

**`UI_CANCEL` no tiene ningun codigo de mando**, solo ESC. UI_MENU y UI_SELECT
si traen uno por defecto; UI_CANCEL no. En `~/.mame/cfg/default.cfg` no hay
ningun bloque `UI_`, y `groovymame.cfg` de AM+ **no define `exit_hotkey`**, asi
que el frontend no mata al emulador: la unica forma de salir de un juego es un
ESC de teclado. Conviene tenerlo presente si algun dia el boton de salir deja de
responder: no es nuestro codigo, es que ahi no hay nada mapeado.

## Los indices de mando NO son fijos: eran la otra mitad del «a veces no avisa»

Pedido por Eloy el 2026-09-12: *«puedes mapear de manera universal el joy 2
button 7?»* -- el boton de moneda. Salieron tres cosas encadenadas.

### 1. El mapeo estaba repetido en nueve `.cfg` por juego

`1942`, `1943`, `arkanoid`, `asteroid`, `avsp`, `berzerk`, `btoads`, `mslug` y
`pacman` traian su propio `<newseq>` de COIN1. Quitado de todos y puesto **una
sola vez** en `~/.mame/cfg/default.cfg`, que es un remapeo por TIPO y vale para
cualquier juego.

**Y eso arregla de paso el cerrojo**, que este documento ya tenia apuntado como
roto en los juegos con mapeo propio: un `<newseq>` por juego vive en
`m_live->seq` y **gana a `set_default_input_seq`**, asi que en esos nueve el
boton de moneda no se podia cerrar mientras la placa arrancaba -- el agujero de
Q*bert con 52 creditos. Comprobado: ya no sale
`AVISO: el cerrojo no ha surtido efecto`.

### 2. `JOYCODE_N` es el ORDEN DE ENUMERACION, no el aparato

Esto es lo gordo, y explica el «a veces funciona y a veces no» que Eloy traia
desde hacia dias. Preguntado a MAME desde Lua:

```
joystick 1  PS4 Controller             id=0300d042...
joystick 2  Xinmotek Dual Controller   id=0300b578...
joystick 3  Xinmotek Dual Controller   id=0300b578...   <- el mismo id, son iguales
```

Con el mando de PS4 enchufado el panel es 2 y 3; **sin el, pasa a ser 1 y 2**.
La prueba de que eso ya habia mordido estaba en los propios ficheros:
`mslug.cfg` tenia el mapeo en `JOYCODE_1_BUTTON7` y los otros ocho en
`JOYCODE_2_BUTTON7`. No son criterios distintos: son **dias distintos**, con el
mando puesto y sin poner.

Se clava con un fichero de **`ctrlr`**, que es la pieza de MAME para esto
(`mapdevice`, por id de dispositivo). `~/.mame/ctrlr/cabina.cfg` y
`ctrlr cabina` en `mame.ini`; copia versionada en
`config/cabina/ctrlr-cabina.cfg`:

```xml
<mapdevice device="0300d042..." controller="JOYCODE_1" />   <!-- PS4 -->
<mapdevice device="0300b578..." controller="JOYCODE_2" />   <!-- Xinmotek -->
<mapdevice device="0300b578..." controller="JOYCODE_3" />   <!-- Xinmotek -->
```

**Los dos Xinmotek comparten id** (es el GUID de VID/PID y son identicos), asi
que cual de los dos cae en el 2 y cual en el 3 sigue sin poder fijarse. Por eso
la moneda se mapea a **los dos a la vez**:

```
COIN1 -> JOYCODE_2_BUTTON7 OR JOYCODE_3_BUTTON7 OR KEYCODE_5
```

Verificado con el PS4 enchufado: los indices salen 1=PS4, 2 y 3=Xinmotek.

### 3. Y una colision que solo aparecio al preguntar

Al clavar los indices al reves -- panel en 1 y 2, PS4 en 3 -- aparecia esto en
`default.cfg`:

```
P1_BUTTON5 -> JOYCODE_1_BUTTON7
COIN1      -> JOYCODE_1_BUTTON7 OR ...
```

o sea el mismo boton fisico haciendo de moneda y de boton 5 del jugador 1. En
un juego de cinco botones, jugar metia creditos.

**No se resolvia razonando**: los dos repartos posibles encajaban con los datos.
Lo cerro Eloy diciendo con que juega -- **con el mando de PS4** -- y eso fija que
`P1_*` apunta al PS4, que es `JOYCODE_1`, y la moneda al mueble. Sin esa
respuesta habria cambiado sus controles creyendo que los arreglaba.

> **Regla:** el reparto de indices no se deduce de los ficheros. Dos historias
> distintas dejan exactamente las mismas lineas en `default.cfg`.

### Lo que queda sin explicar

Una sola pasada de 1943 dio **5 creditos con 3 monedas**. **No se ha reproducido
en tres repeticiones** con la misma orden, ni con la traza del contador frame a
frame (3 monedas -> 1, 2, 3). Se deja apuntado sin causa en vez de inventarsela.
Si vuelve a aparecer, el primer sitio donde mirar es una doble asignacion como
la del punto 3.

## El contador mentia pasado el 9: catorce placas guardan BCD

Traido por Eloy el 2026-09-13: *«el contador de la parte superior llega hasta 9
y luego se reinicia»*. Medido metiendo 30 monedas juego a juego en la cabina,
son **dos cosas distintas** y ninguna era lo que parecia.

### 1. BCD, y afectaba tambien al aviso de salida

Catorce de los 33 juegos con direccion conocida guardan el contador en decimal
codificado en binario. El byte va `0x09 -> 0x10`, asi que leido en crudo el
credito 10 parece **16** y el 20 parece **32**:

```
pacman, antes:  9:9(0x09) 10:16(0x10) 11:17(0x11) ... 20:32(0x20)
pacman, ahora:  9:9(0x09) 10:10(0x0a) 11:11(0x0b) ... 12:12(0x0c)
```

No era solo el marcador: el **cuadro de aviso al salir** anuncia «quedan N
creditos» leyendo lo mismo, asi que mentia igual.

Se traduce en `leer_ram`/`escribir_ram`, que es el unico sitio por el que pasan
todos los consumidores -- marcador, aviso, barrido y tope. Un nibble > 9 no es
BCD valido (la placa esta inicializando su RAM, o la direccion no es la que
creiamos) y ahi se devuelve el byte tal cual, que es lo que el asentamiento
espera. La marca es la palabra `bcd` al final de la linea de `creditos.dat`.

**Verificado en pantalla, que es lo unico que vale:** capturada la ventana de
Pac-Man con 12 monedas dentro, nuestro rotulo dice `CREDITOS 12` y el juego dice
`CREDIT 12` abajo. El mismo numero.

BCD: `ddragon defender dkong dkongjr frogger joust kungfum mspacman pacman
popeye robocop robotron timeplt zaxxon`.

### 2. El «se reinicia» literal es 1942, no 1943

Su byte va 1..9 y **en la moneda 10 vuelve a 0**, y sigue 1, 2, 3... Y como el
marcador solo se pinta con `n > 0`, al dar la vuelta **desaparece**. Eso es
exactamente lo que se veia. 1943 tambien tiene tope 9 pero ahi el byte se queda
clavado: 30 monedas y no se mueve.

### Y de ahi el cerrojo por maquina llena

Segunda mitad del encargo: *«en aquellos juegos que tengan limite de creditos,
cuando se llegue al limite, se deberia bloquear el boton»*. Dos vias:

- **`limite=N` en `arranque.dat`**: al llegar se cierra el boton y sale
  `MAQUINA LLENA: N CREDITOS`. No se pierde ni una moneda. Puesto en los once
  medidos con tope 9: `1942 1943 avsp btime elevator galaxian megaman rbtapper
  snowbros tapper tron`.
- **Aprendizaje solo**, para el resto: la primera moneda que se pierde con el
  contador quieto fija el tope, y el log dice que numero escribir en el fichero.
  Se pierde esa una. Equivocarse sale barato -- en cuanto el jugador gasta un
  credito el contador baja y el boton se abre solo.

`cerrojo.lua` gana una tercera razon para estar echado (`lleno`), al lado de
«sin creditos» y «arrancando». Solo se cierra con un numero **fiable**: hace
falta direccion comprobada y no a prueba. Dejar al jugador sin boton por una
lectura dudosa seria peor que perder una moneda.

### Los otros dos detalles de la misma tanda

- **`contador=0/1` por juego**, expuesto en el plugin **Arranque**, que es donde
  Eloy quiere los ajustes generales. Anadir un ajuste al plugin es una fila en
  su tabla `AJUSTES`... y mueve el indice de «Salir», que `prueba_arranque.nut`
  tenia escrito a mano. Las pruebas lo cazaron; queda anotado en el fichero.
- **El recuadro de los rotulos era una banda fija** de 0.60 a 0.99, o sea el 39%
  del ancho para un texto que ocupa el 17% (`CREDITOS 9` mide 0.17). Ahora se
  mide con `manager.ui:get_string_width`, que devuelve las mismas coordenadas
  0..1 del contenedor, y el recuadro se ajusta. Vale para los cuatro rotulos de
  esa esquina.

### Dos trampas del banco de pruebas, las dos ya documentadas y repetidas igual

La primera tanda de medidas **no valia**, y por dos motivos distintos:

- **`-cfg_directory` a un directorio NUEVO son los DIP de FABRICA.** Missile
  Command volvia a tener su premio cada cuatro monedas -- el que ya se le habia
  quitado -- y daba 20 creditos con 16 monedas. Hay que copiar los `.cfg` de
  verdad, igual que ya estaba escrito para `buscar_creditos.sh`.
- **Una NVRAM vacia hace que las placas Williams digan `FACTORY SETTINGS
  RESTORED` y rechacen las monedas.** `defender`, `joust` y `robotron` salieron
  con el contador sin moverse, y yo estuve a punto de darlos por «sin tope». Con
  su NVRAM buena responden y son BCD como los demas. Es exactamente la trampa
  que este documento ya tenia apuntada de la tanda de la NVRAM.

> **Regla:** toda medida sobre una placa se hace con SUS ficheros -- `.cfg` y
> NVRAM --, copiados a un temporal. Partir de vacio no es un entorno limpio, es
> un entorno **distinto**.

## El panel web de control remoto (2026-10-13)

Pedido por Eloy: administrar la cabina **desde el navegador del teléfono o del PC,
desde cualquier lado y sin abrir puertos**. Reparto acordado: **Claude hace el
backend, Eloy hace la GUI** (la página web). El plano está en `docs/panel.md`, que
es además el **contrato de API** entre los dos.

**Decisiones de Eloy (2026-10-13):**
- Acceso remoto: **Cloudflare Tunnel** (URL HTTPS, cualquier navegador sin app,
  auth con Cloudflare Access). La cabina va por 4G/CGNAT, así que un túnel saliente
  es la única vía de todas formas. Dominio: **dsds.uk** (suyo, hoy sin usar) →
  `arcade.dsds.uk`.
- "Encender" en remoto se **omite** por ahora (software no puede encender una
  máquina apagada; haría falta un enchufe inteligente + BIOS "restore on AC").
  Se mantienen apagar y reiniciar.
- "Créditos por juego" = **tarifa en pesos**, en pasos de **$100** (la moneda es
  de $100): $100/jugada = 1 moneda/crédito (lo actual), $200 = 2 monedas/crédito…
- "Reiniciar monedero" = **reiniciar el demonio/relé** (`systemctl --user restart
  monedero.service`), no poner a cero el conteo.

**Arquitectura** (toda en `panel/`, servicio de usuario `panel.service`, corre como
`arcade`, escucha SOLO en `127.0.0.1`; lo saca al mundo `cloudflared`):
- `panel/servidor.py` — Flask, API JSON + login/sesión + CSRF + SSE. **Probado**
  end-to-end con Flask en un venv: 401 sin login, CSRF obligatorio, estado real.
- `panel/estado.py` — lee cpu/temp/ram/disco/uptime/juego-actual/servicios/arduino
  de `/proc`, `/sys`, `systemctl`, `git`. **Probado** contra el sistema real.
- `panel/acciones.py` — reboot/poweroff (`sudo -n systemctl`), reiniciar FE y
  monedero, mantenimiento, pantalla, volumen, gestión de juegos, tarifa, update.
- `panel/monedas.py` — agrega `~/.attract/monedas.log` → ingresos = monedas × $100.
- `panel/simulador.py` — backend DE MENTIRA, **stdlib puro (sin Flask)**, con las
  mismas rutas `/api/...`: es para que Eloy construya la GUI con la cabina apagada.
  **Probado**. La GUI pasa al backend real sin cambios.
- `panel/static/index.html` — página de arranque mínima de ejemplo (la GUI final
  la hace Eloy); `panel/frontend.sh` — supervisor del frontend.

**Dos canales de orden, a propósito.** El Lua de MAME no tiene sockets, y solo
`creditos.lua` puede tocar el ioport COIN1 o cerrar la máquina. Así que:
- acciones de **sistema** las ejecuta el panel directo (sudo NOPASSWD / systemctl);
- acciones de **MAME** (meter créditos, salir del juego) el panel las deja en
  `~/.attract/panel_cmd` y `creditos.lua` las aplica en su bucle por-frame.

**Cambios en `creditos.lua`** (verificados en MAME real sobre Pac-Man, con
`luac -p` y `correr.sh` en verde):
- Sondeo de `panel_cmd` (atómico: renombra antes de leer). `insertar N` reutiliza
  la máquina de `insertar()` (fija `restantes`+`fase`) y mete N créditos con
  `set_value` — que es un OR con la secuencia física, así que **NO lo ve el
  detector de monedas**: son créditos gratis, no se cobran. Verificado: el byte de
  créditos de la RAM subió 0→1. `salir` → `machine:exit()` (cierre limpio).
- `monedas.log`: una línea por **moneda de verdad** del jugador (evento `moneda`,
  cantidad 1) en el gancho de la moneda, y los comps del panel como evento `panel`.
  Los ingresos son monedas × valor; por eso se apunta 1 (moneda), no los créditos.
- `juego_actual`: el set + descripción, para que el panel sepa qué corre.
- Todo con su `GA_*=off`, y el atajo de "nada que vigilar" ya **no** se toma si el
  buzón del panel está activo (si no, dejaría el sondeo muerto, como pasó con los
  modos de grabación).

**La tarifa por juego**: `creditos/fijar_tarifa.lua` + `.sh` generalizan
`poner_1c1c` (que no se toca): fijan el DIP a "N monedas/1 crédito" (N = pesos/100)
lanzando el juego 2 s; MAME guarda el `.cfg`. **Probado** en Pac-Man ($200→"2
Coins/1 Credit", $100→vuelve, $500→sin-opcion). **Aviso:** para que una tarifa
distinta de $100 PERSISTA, la cabina tiene que lanzar `creditos.lua` con
`GA_TARIFA=auto`; con el `1c1c` por defecto se vuelve a forzar 1 moneda/crédito en
cada arranque. Eso es un cambio pendiente en `groovymame.cfg` cuando se use.

**El instalador**: `tarea_panel` (patrón de `tarea_monedero`) instala Flask, copia
`~/.config/panel.conf` (sin pisarlo), escribe y activa `panel.service`, y **avisa**
de los pasos de Cloudflare (login/create/route/service) y de enganchar
`panel/frontend.sh` — no reescribe la cadena de arranque de GroovyArcade por su
cuenta, que es delicada y hay que probarla con la cabina delante. Marcada por
defecto solo en GroovyArcade.

**Ficheros nuevos en `~/.attract/`**: `panel_cmd` (buzón de órdenes), `monedas.log`
(ingresos), `juego_actual`, `mantenimiento` (centinela), `panel_auditoria.log`,
`panel_secret` (clave de sesión), `puntajes.json` (ya existía, de `puntajes.py`).

**Pendiente (necesita la cabina encendida, Eloy avisa):** desplegar (pull + tarea
`panel`), dar de alta el túnel Cloudflare + Access con su cuenta, enganchar
`frontend.sh`, y probar en vivo las acciones. La GUI la construye Eloy contra el
simulador mientras tanto.

## Próximos pasos

1. Plantearse generar el `.deb` (hay directorio `debian/`) en vez de
   `sudo make install`, para poder desinstalar limpio.
2. Decidir si AM+ se instala en el sistema o se ejecuta desde el repo con
   `--config`.
3. Instalar de verdad en la cabina: copiar `Creditos.nut` a
   `$HOME/.attract/plugins/`, el emulador a `$HOME/.attract/emulators/`,
   activar el plugin y **mapear el botón físico de moneda** (es lo único que no
   se puede probar sin la cabina).
4. Pasar `poner_1c1c.sh` y `buscar_creditos.sh` una vez sobre la lista real de
   juegos.
5. ~~El bloqueo de la moneda cuando el saldo llega a 0.~~ **Hecho** el
   2026-08-28: `cerrojo.lua`, con `set_default_input_seq`, que no ensucia el
   `.cfg`.
6. Arrancar `contador_arduino.py` solo con la cabina (servicio de `systemd` de usuario).

**Aviso**: la API de MAME de este documento está verificada ejecutándola. La de
Attract-Mode Plus **no** — cuando se llegue ahí, contrastar con `Manual.md` y
`Layouts.md` del repo, no con lo que el modelo recuerde.

## Notas del entorno

- `/home` está en el disco de 1.8 TB (`nvme…p1`, UUID `41b2e1de-…`), 1.7 T libres.
- Los dos NVMe **se intercambian los nombres entre arranques**. Todo por UUID.
- ccache (20 G) y mold instalados. Para que MAME los use de verdad:
  `PATH=/usr/lib/ccache:$PATH mold -run make …` en la MISMA invocación
  (exportarlo antes y lanzar en segundo plano no propaga el entorno).
- Recompilar MAME: `make -j10 NOWERROR=1 USE_QTDEBUG=0` desde `~/Dev/arcade/groovymame_src`.
  `USE_QTDEBUG=0` es obligatorio si se usa `REGENIE=1`, si no falla por falta de `moc` de Qt.

## Grabar MI partida con una tecla, y el desfase de `arranque.dat` (2026-09-12)

Dos encargos de Eloy el mismo día, independientes entre sí.

### `videos.sh` leía los decimales y se los comía CALLADO

Esto salió al empezar y es lo más importante de la tanda, porque llevaba ahí
desde el principio. `ajustes.lua` acepta decimales desde siempre —su patrón es
`([%w%.%-]+)` y pasa por `tonumber`— así que `mwalk segundos=11.8` es una línea
perfectamente válida y `creditos.lua` la aplica tal cual. Pero el lector de
claves de `videos.sh` pedía `[0-9]+`:

```bash
v="$( ... | grep -oE "(^|[[:space:]])$2=[0-9]+" | ... )"
```

O sea que **leía `11` y tiraba el `.8`, sin decir nada**. El vídeo empezaba casi
un segundo antes de donde se pidió y no había forma de notarlo. Arreglado, y con
signo, para que `videomas=-2` se pueda escribir.

Y con decimales en juego **bash ya no sabe sumar**: `$(( 11.8 + 3 ))` es un error
de sintaxis. De ahí `calc()` y `es_menor()`, dos ayudas de awk. El `tope` de
`grabar_clip` redondea hacia **arriba**: un tope corto cortaría el clip por el
final.

### `videomas=`: el punto del vídeo, relativo al arranque

Eloy lo planteó así: *«que exista otra variable que automáticamente se asigne a
la misma cantidad que la variable "segundos", pero esa puede modificarse a
gusto»*. Definido a preguntas, salió un **desfase**, no una copia:

```
mwalk segundos=11.8 nvram=0 videomas=3     -> el clip empieza en 14.8
```

Lo que gana frente a escribir `video=14.8`: si mañana se retoca la carga del
juego, el vídeo **se mueve solo con ella** en vez de quedarse apuntando a un
instante que ya no existe.

Decisiones que tomó Eloy, y conviene no darles la vuelta solas:

- **Sólo por juego.** Nada en la línea `defecto`: un desfase general movería
  todos los vídeos de golpe, y cada placa es cada placa.
- **`video=` manda sobre `videomas=`.** Un número absoluto escrito a mano es una
  decisión; no se pisa con una cuenta.
- **Con `videomas=` NO se aplica el suelo de 8 s.** El punto lo eligió una
  persona; subirlo por nuestra cuenta sería ignorar la orden. (Sin él sigue
  valiendo la regla vieja: `segundos=` es un suelo, no el valor final.)

Precedencia completa: `SALTO=` > `video=` > `segundos=`+`videomas=` >
`segundos=` como suelo > 8 s. El script dice de dónde salió cada uno.

**Verificado ejecutándolo**: con `mwalk segundos=11.8 videomas=3`, el log de
`creditos.lua` dice `EMPEZANDO clip en 14.8s`, no en 14 ni en 11.

**Aviso de fondo, que no es del código:** poner `segundos=11.8` en Moonwalker no
sólo mueve el vídeo, **alarga la pantalla negra al entrar al juego**. Y mwalk es
de los que casi no se pueden acelerar (~139%), así que esos 11,8 segundos
emulados son unos 8,5 reales de negro en cada partida. En el repo está en `0`
por eso mismo.

### `grabar.sh`: grabar la partida de uno, con sonido

Pedido: *«comienzo a jugar / encuentro un momento que vale la pena y presiono un
botón de teclado / detengo la grabación con el mismo botón»*.

Es un guion **aparte** de `videos.sh` y sólo corre cuando se pide. Los dos usan
la misma API (`begin_recording`/`end_recording`) pero son lo contrario el uno del
otro: `videos.sh` graba en serie, sin nadie delante, bajo Xvfb y mudo; esto es
una persona jugando en la cabina, con audio. Mezclarlos habría dejado a los dos
peor.

Lo que **sí** comparten vive ahora en **`video_comun.sh`**: encontrar el
emulador, la proporción 4:3 del mueble, el ampliado en dos fases y la conversión
a mp4. Tener dos copias de eso significaba arreglar una trampa en una y no en la
otra, que es el error que este documento ya tiene apuntado para el script que
medía cobertura por una ruta y publicaba por otra.

**La tecla se lee con `input:code_pressed`**, que es el estado CRUDO del teclado:
no pasa por el ioport del juego ni por la UI de MAME, así que no hay que mapear
nada ni se pisa ninguna función del emulador. Por defecto **Pausa/Inter**
(`KEYCODE_PAUSE`), elegida comprobando `inpttype.ipp`: las que parecían obvias
están cogidas — **Insert es «Fast Forward»**, Inicio/Fin/AvPág/RePág son del menú
e ImprPant se la queda el escritorio.

Tres cuidados que costaron pensarlos:

- **Sólo el FLANCO.** Con el nivel a secas, tener la tecla pulsada medio segundo
  —que es lo normal— daría treinta arranques y treinta paradas. Y se arranca
  suponiendo la tecla *pulsada*, para que tenerla apretada al lanzar el juego no
  cuente como un flanco.
- **`code_from_token` NO falla con un token mal escrito**: devuelve un código
  `INVALID` que luego no se pulsa nunca. O sea que una errata en `TECLA=` sería
  un fallo mudo — juegas media hora y no se ha grabado nada. Se comprueba dando
  la vuelta al token con `code_to_token`, que es lo único que lo delata.
- **El atajo de «nada que hacer» de `creditos.lua` dejaba el modo muerto.** Si el
  juego no está en `creditos.dat` y no hay nada que vigilar, el script se salía
  *antes* de suscribir `por_frame` — y los dos modos de grabación viven ahí.

**El indicador `* REC 12s` no entra en el vídeo**, y no es suerte:
`begin_recording` dibuja desde `m_snap_target`, un render target aparte que sólo
lleva las vistas de PANTALLA (`video.cpp`, `create_snapshot_bitmap`), así que la
capa de interfaz no se graba. Es la otra cara de la trampa ya conocida de que
`screen:snapshot()` no captura lo que pintamos ahí.

**El audio: verificado, no supuesto.** El AVI de MAME lleva el sonido dentro
—`sound_manager` alimenta la grabación por su cuenta
(`sound.cpp:2726`)— y sale PCM 16 bits a 48 kHz. Medido en Moonwalker grabando
una toma de 5 s sobre su música:

| | nivel medio |
|---|---|
| toma grabada con `begin_recording` | **-25,0 dB** |
| el mismo tramo por `-wavwrite` (referencia) | **-25,0 dB** |

Idénticos, o sea que captura el audio real y alineado.

> **Trampa al medir esto, y me costó media hora:** las primeras pruebas salían
> en silencio digital (-91 dB) y parecía que la grabación no llevaba sonido.
> **No era eso: Pac-Man y Donkey Kong están callados en esa parte de su
> atracción.** El `-aviwrite` de siempre daba exactamente el mismo -91 dB, así
> que la pista buena era comparar contra una referencia del mismo juego y el
> mismo instante, no contra el silencio. Para probar audio hay que elegir un
> juego con música continua (mwalk sirve; pacman y dkong no).

**Y sí se oirá en el frontend**: `VF_NoAudio` es un flag de exclusión que el
layout tiene que pedir, el `Arcade-UMAG` de la cabina no lo pide, y el volumen
de vídeo de AM+ viene a 100 sin silenciar (`fe_input.cpp:1728`).

Detalles del guion:

- **Varias tomas por sesión** (`toma-1.avi`, `toma-2.avi`…). Al salir se
  enseñan con su duración y se elige; sin terminal, la más larga.
- **El vídeo que se reemplaza se guarda** en `<snap>/respaldo/`. Los automáticos
  se rehacen con `videos.sh` en un minuto; una partida grabada a mano no.
- **No se tocan los ajustes de vídeo ni de sonido**: los pone `mame.ini`, que es
  lo que el jugador tiene delante. `videos.sh` sí los forza, pero porque graba a
  ciegas bajo Xvfb.

**Lo que no se pudo probar aquí:** la pulsación de verdad. En hp-envy no hay
`xdotool` ni nada que inyecte teclas, así que se comprobó en dos mitades, las dos
dentro de MAME: que `KEYCODE_PAUSE` resuelve (y que un token inventado da
`INVALID`), y que el ciclo entero —dos tomas, con sus nombres, duraciones y
audio— funciona sustituyendo la lectura de la tecla por un horario. **Falta
pulsarla con los dedos en la cabina.**

### La calibración de `arranque.dat` vivía SÓLO en la cabina

Salió al hacer el `git pull` allí el 2026-09-12, y era el aviso que este
documento arrastraba desde hacía días, hecho realidad:

| | juegos con línea propia |
|---|---|
| `arranque.dat` del repo | 63, casi ninguno con `segundos=` |
| `arranque.dat` de la cabina | **82, casi todos con `segundos=` cronometrado** |

Eloy había medido placa a placa —`mappy 13.2`, `qbert 0.1`, `sf2 14.5`,
`simpsons2p 10.6`, `nrallyx 12.8`, `mwalk 11.8`— **y nada de eso estaba
versionado**. Un `git pull` a secas allí lo habría borrado entero.

**Cómo se recuperó sin perder nada**, que es lo reutilizable:

1. Traerse el fichero por ssh **comprobando md5 en los dos extremos**. El primer
   intento con `base64 -w0` a pelo llegó corrupto: el pty mete saltos de línea en
   una línea larguísima. Con `gzip | base64` entre marcadores, y limpiando
   espacios al reensamblar, cuadra el md5.
2. Fundir **clave a clave**, no fichero contra fichero. Ninguna de las dos copias
   era superconjunto de la otra: la cabina tenía 20 juegos que el repo no, pero
   había perdido la línea entera de `pacman`, el `video=44` de `nemesis` y el
   `indicador=0` de `nrallyx`.
3. **Comprobar la fusión contra las DOS copias** antes de escribir nada, y otra
   vez sobre la cabina después del pull: `0 perdidas` en los dos sentidos, y de
   195 ajustes a 200.

También hace falta un `md5sum` justo antes del `checkout`: el fichero se estaba
editando por sftp en ese momento, y si hubiera cambiado entre la copia y el
pull, la fusión habría sido sobre datos viejos.

> **Regla:** antes de un `git pull` en la cabina, mirar `git status` allí. Lo que
> salga como `M` puede ser trabajo medido que no está en ningún otro sitio.

**`escribir_ajuste.py` y los comentarios** (corregido el 2026-09-13): pone o
cambia UNA clave de un juego sin tocar el resto. Los comentarios y las líneas en
blanco se copian **verbatim** —conserva la sangría de la tabla de ayuda de
cabecera—; lo único que reescribe es la propia línea del juego editado, cuyos
espacios internos quedan normalizados a uno. Una versión anterior de esta nota
decía que «aplastaba la sangría de todos los comentarios de cabecera»: **era
falso.** Comprobado ejecutándolo sobre un `arranque.dat` con comentarios
sangrados —sólo cambió la línea del juego; la cabecera quedó intacta— y leyendo
el código: los comentarios se añaden con la línea original sin tocar
(`escribir_ajuste.py`, la rama `pelada.startswith("#")`).
