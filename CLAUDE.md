# Sistema de créditos para cabina arcade (GroovyMAME + Attract-Mode Plus)

Contexto traspasado desde otra sesión. Todo lo marcado como **verificado** se
comprobó ejecutando código y mirando capturas de pantalla reales, no de memoria.

**Mapa del proyecto: `ESTRUCTURA.md`** — qué hay en cada directorio, quién lee
qué fichero de configuración y las trampas de sincronización. Este documento
(`CLAUDE.md`) es el *por qué* de cada decisión; `ESTRUCTURA.md` es el *dónde*.

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
rama **`monedero-frontend`** de los dos repos (`attractplus` y
`groovyarcade-creditos`, que desde el 2026-08-29 también está bajo git).
Encenderlo otra vez son dos interruptores: `GA_MONEDERO=1` y activar el plugin.
Sus pruebas siguen pasando, porque los escenarios lo piden explícitamente.

Dos cosas que quedan sueltas con este flujo, por si se quieren retomar:

- **`daemon.py` y el contador físico se quedan sin nada que enseñar**, porque ya
  no hay monedero. La evolución natural sería que mostrara los créditos que hay
  **dentro del juego**, que para los juegos de `creditos.dat` se leen de la RAM.
- **La tarifa del DIP ahora decide dinero de verdad.** Sigue forzada a 1 moneda
  = 1 crédito (`GA_TARIFA`); si se quiere otra cosa, es ahí.

## Decisión de Eloy (2026-08-24): modo manual — SUPERADA, ver arriba

La cabina queda en **modo manual**: el plugin del frontend está **desactivado**,
se entra al juego sin créditos y las monedas las mete el jugador con el botón,
como en una recreativa de verdad.

El razonamiento es bueno y conviene no olvidarlo: la ranura de MAME funciona
igual en el 100% de los juegos, mientras que pasarle los créditos desde el
frontend sólo es exacto en los 10 que tienen su dirección de memoria localizada.
Eloy prefirió consistencia a automatismo.

Todo lo demás sigue montado y probado por si se quiere volver atrás: basta
encender el plugin (`Configure > Plug-ins > Creditos > Enabled`). `creditos.lua`
se queda en los argumentos del emulador porque sin monedero sigue sirviendo para
la tarifa 1C/1C y para el aviso al salir.

## Diseño objetivo (Eloy, 2026-08-28): monedero visible en el Arduino

**Implementado y verificado el 2026-08-28. APAGADO desde el 2026-08-29**, ver
la decisión de las monedas de verdad al principio. Se conserva entero en la
rama `monedero-frontend` y se enciende con `GA_MONEDERO=1`.

La idea, en una frase: **el plugin sólo guarda los créditos del jugador; el
Arduino los enseña; el jugador decide cuántos mete en el juego pulsando la
moneda, y cuando se acaban el botón se bloquea.**

El flujo:

1. El jugador mete 5 monedas en el frontend. El Arduino marca **5**.
2. Elige juego. **No se inserta nada**: entra con 0 créditos, como en el modo
   manual.
3. Dentro de la partida pulsa la moneda 3 veces. El juego marca 3 créditos y el
   Arduino baja a **2**.
4. Si sigue pulsando hasta agotar el monedero, el Arduino marca **0** y el
   botón de moneda deja de responder (el cerrojo, ya montado).

De momento el Arduino lo representa con un LED; el display real viene después.

### Lo que cambia respecto a lo que hay hoy

**El monedero vuelve a cobrar al METER, no al jugar.** Esto invierte a propósito
la regla de la sección «Los créditos que se quedan dentro del juego», y conviene
entender por qué deja de ser un problema:

> El agujero original no era cobrar al meter, era **cobrar sin que se viera**.
> Un jugador que pulsaba la moneda creyendo que acumulaba créditos para otros
> juegos se vaciaba el monedero a ciegas. Con el contador físico delante, el
> número baja a la vista: meter una moneda es gastarla, igual que en una
> recreativa. La regla vieja seguirá siendo la correcta si algún día se quita el
> contador.

Cómo se enciende: **es lo que hay por defecto**. Dos interruptores, uno a cada
lado, y los dos tienen que ir juntos:

- Plugin: `Que se inserta al lanzar` = **`Nada`** (antes «Solo el coste»).
- `creditos.lua`: **`GA_COBRO=meter`** (por defecto; `jugar` es el modo viejo).

Lo que se tocó, por orden de importancia:

- **El plugin no inserta ni cobra al lanzar** (`creditos_a_gastar()` devuelve 0
  con `m_nada`). Escribe `inserta 0`; el campo se mantiene por compatibilidad.
- **`creditos.lua` cobra la moneda al meterla**, en el mismo sitio donde ya
  avisaba al jugador. Y **no vuelve a cobrar** cuando el juego se lleva el
  crédito: eso sería cobrar dos veces.
- **La sincronización por escritura se apaga sola en modo `meter`**
  (`SINCRONIZAR and (COBRO ~= 'meter')`). Era imprescindible: volcaba el
  monedero entero en la RAM del juego, o sea metía los 10 créditos de golpe y
  el botón de moneda no pintaba nada. `memoria.lua` y `creditos.dat` siguen
  usándose para saber **cuántos hay dentro** en el aviso de salida.
- **El cerrojo valía tal cual**: `disponible = SALDO - metidas` es exactamente
  el saldo del momento.
- **El cuadro de aviso vuelve a ser un aviso de pérdida de verdad**
  (`op.se_pierden`): «SI SALES AHORA LOS PIERDES. MONEDERO: N». Con la regla
  nueva esos créditos ya están pagados.
- **Se sigue exigiendo saldo para elegir juego**, pero **sin cobrarlo**:
  `m_coste` pasa de ser un precio a ser un mínimo. Sin créditos no hay nada que
  hacer dentro de una partida, así que dejar entrar sería un engaño.
- **`daemon.py` no cambia**: ya se limita a enseñar el `saldo`.

### Lo que no cambia

- El fichero `~/.attract/creditos.txt` y su escritura atómica.
- El cerrojo y su técnica (`set_default_input_seq`).
- Que el plugin escriba el monedero en cada cambio, que es lo que alimenta al
  contador físico.

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

Ficheros en `~/Dev/arcade/groovyarcade-creditos/`: `creditos.lua`, `monedero.lua`
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

**Ojo: el diseño objetivo del 2026-08-28 invierte esta regla a propósito**
(cobrar al meter), porque el contador físico hace visible el gasto. Ver
«Diseño objetivo» al principio antes de tocar nada aquí.

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

## El contador físico de la cabina (Arduino)

Montado el 2026-08-28, escrito por Eloy con tutoría.

```
Creditos.nut escribe ~/.attract/creditos.txt  ->  daemon.py lo vigila
   ->  puerto serie 9600  ->  Arcade.ino  ->  contador físico
```

**`daemon.py`** (en la raíz del repo): lee el `saldo`, y sólo cuando **cambia**
respecto a lo último enviado manda `N\n` por `/dev/ttyUSB0`. Detalles que
costaron una iteración cada uno:

- **Se vuelve a abrir el fichero en cada lectura.** El monedero se reemplaza
  entero (temporal + `rename()`), no se modifica: con el descriptor abierto se
  leería el fichero viejo para siempre.
- **El puerto se abre una sola vez.** Abrirlo **reinicia la placa**, de ahí los
  3 s de espera antes del primer envío. El `echo > /dev/ttyUSB0` que se intentó
  al principio reiniciaba el Arduino en cada moneda.
- **`lastCredit = None` al reconectar**, porque la placa se ha reiniciado
  mostrando 0 y el saldo del fichero no ha cambiado: sin esto el contador se
  queda congelado tras un tirón de cable.
- **Sólo se apunta el crédito si el envío devolvió `True`.** Apuntarlo antes
  dejaba el contador desincronizado para siempre.
- El registro **no repite el mismo error**, pero anota `recuperado` al
  arreglarse, para que un fallo que vuelve tres horas después no se pierda.

**El plugin escribe el monedero en CADA cambio**, no sólo al lanzar
(`Creditos.nut`, `guardar()` y el constructor). Antes el contador físico no se
enteraba de las monedas metidas en el menú, y si alguien borraba el fichero no
se recreaba hasta el siguiente juego.

**`Arcade.ino`** (`~/snap/arduino/85/Arduino/Arcade/`): faltaba
`Serial.begin(9600)` en el `setup()` — el fallo por el que «no funcionaba nada»
mientras el Python estaba perfecto. Además `Serial.parseInt()` estaba dentro de
la condición del `for`, así que se releía en cada vuelta y devolvía 0 a la
segunda. Diagnóstico que conviene recordar: **el registro del demonio decía la
verdad** (leía el saldo, escribía sin error); el fallo estaba al otro lado del
cable.

Pendiente: que el demonio arranque solo con la cabina (servicio de `systemd` de
usuario) y sustituir el parpadeo del LED por el display de verdad — el parpadeo
bloquea el `loop()` y deja la placa sorda al puerto casi cuatro segundos con 9
créditos.

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



## Los vídeos de muestra los grabamos nosotros

Pedidos por Eloy el 2026-09-01. **No hay de dónde bajarlos**: la fuente que AM+
trae incrustada devuelve 404 (`progettosnaps.net/videosnaps/mp4/pacman.mp4`,
`scraper_net.cpp:218`) y arcadeitalia no sirve vídeos, sólo imágenes.

Pero las roms y el emulador ya están aquí, así que `videos.sh` los graba:
MAME con `-aviwrite` durante unos segundos, y ffmpeg recorta la carga y comprime
a h264. Salen a `<config>/scraper/<emu>/snap/<juego>.mp4`, el mismo sitio que la
captura fija — **AM+ prefiere el vídeo cuando existe**.

- El AVI de MAME es **sin comprimir**, unos 11 MB por segundo: va a un temporal
  y se borra en cuanto se convierte.
- `-ss 8` descarta el arranque de la placa y toma el modo de atracción.
- Sin audio (`-an`): grabar sonido sin tarjeta no es fiable bajo Xvfb.
- Las 20 roms: **2,5 MB en total** y unos 8 minutos de grabación.

**El salto por juego no se adivina, se mide.** Eloy volvió el 2026-09-01 con
Simpsons, New Rally-X y Mappy enseñando la pantalla de test de la placa. Con
`./videos.sh --tira <juego>` sale una tira de doce fotogramas etiquetados por
segundo, y ahí se ve cuándo empieza lo que quieres:

| juego | qué pasa | salto |
|---|---|---|
| `simpsons` | 4 s «RAM ROM CHECK», 10 s patrón de test, atracción a los 14 | 16 |
| `nrallyx` | test hasta los 12, lista de personajes, juego a los 28 | 28 |
| `mappy` | título y personajes hasta los 35, demo a los 38 | 38 |

Los valores viven en la tabla `SALTOS` del script. Y **`FORZAR=1` para rehacer
uno que ya tiene vídeo**: sin eso el script lo salta, que es lo que hizo pensar
a Eloy que cambiar el salto no servía de nada.

**Verificado que AM+ los reproduce**, no que existan: dos capturas del frontend
separadas dos segundos con Donkey Kong seleccionado difieren en 63.948 píxeles.
Con la imagen fija serían idénticas.

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
  -autoboot_script ~/Dev/arcade/groovyarcade-creditos/creditos.lua -autoboot_delay 6
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

`~/Dev/arcade/groovyarcade-creditos/creditos.lua`, configurable por entorno:

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

`~/Dev/arcade/groovyarcade-creditos/pruebas/correr.sh` — 84 comprobaciones del
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

## La salida de vídeo en el CRT: tres cosas distintas que parecían una

Traídas por Eloy el 2026-09-02 con el CRT de escritorio (HDMI + adaptador VGA):
no se ven las scanlines, los juegos verticales salen estirados, y los ajustes
de pantalla de MAME no se guardan. Son **tres causas independientes**.

### 1. Los ajustes de vídeo que no se guardaban: parcheado

*«en Kung-Fu Master lo configuré para no mantener el aspect ratio, pero no se
guarda»*. La causa, leída en el código:

- **`render_target::config_save`** (`src/emu/render.cpp`) escribía en el `.cfg`
  la vista, el `zoom`, la rotación y la visibilidad de capas. **`keepaspect` y
  `scale_mode` no estaban en esa lista**, así que «Maintain Aspect Ratio» y
  «Non-Integer Scaling» del menú Video Options se cambiaban sólo en memoria.
- **`sliders_save`** (`ui.cpp:3107`) filtra por nombre y sólo conserva los
  deslizadores con «Frame Delay», «V-Sync Offset», «Overclock», «Screen Refresh
  Rate» o «CRT». Por eso **tocar crt-geom a mano tampoco persiste**: de sus 17
  ajustes el único que se guardaría es «Gamma of simulated CRT», por llevar
  «CRT» en el nombre. De ahí que la cadena se configure por JSON.

**Arreglado con un parche**, `parches/groovymame-guardar-ajustes-video.patch`
(33 líneas). Añade `m_base_keepaspect` y `m_base_scale_mode` — cómo estaban al
arrancar — y guarda cada uno **sólo si el usuario lo cambió**, igual que MAME ya
hacía con la vista y la rotación. En una cabina no hay teclado para editar
ficheros: el ajuste tiene que quedarse desde el propio menú.

Verificado en las dos direcciones, y la prueba se apoya en que MAME **reescribe
el `.cfg` entero al salir y tira lo que no reconoce**:

- Con `<video><target index="0" keepaspect="0"/></video>` metido a mano,
  Pac-Man pasa de 575 a 910 px de ancho: `config_load` lo aplica.
- Tras una salida limpia el nodo **sigue ahí**: `config_save` lo escribió.
- Sin tocar nada, no aparece ningún nodo: no ensucia los `.cfg`.

**Y había un segundo dueño de esos ajustes: switchres.** Con el parche puesto,
Eloy seguía perdiendo el cambio de aspecto. La causa está en
`switchres_module::set_options()` (`src/osd/modules/switchres/switchres_module.cpp:488`),
que con `autostretch 1` **recalcula y sobrescribe** `keepaspect` y `scale_mode`
en cada arranque:

```cpp
set_option(OPTION_KEEPASPECT, force_aspect);
...
target->set_keepaspect(options.keep_aspect());
```

Medido en el CRT, poniendo `keepaspect="0"` a mano y arrancando:

| | queda en el `.cfg` |
|---|---|
| `switchres 1` | `keepaspect="0" scalemode="4"` <- el `scalemode` **lo mete switchres** |
| `-noswitchres` | `keepaspect="0"` y nada más |

O sea que el parche funcionaba, pero switchres pisaba el valor y encima ensuciaba
el `.cfg` con decisiones suyas. **Bajo Xvfb no se reproduce**: switchres no llega
a abrir pantalla y la rama de `autostretch` no corre. Hay que probarlo en la
pantalla de verdad.

Arreglo para esta cabina: **`switchres 0` en `mame.ini`**. Aquí no puede hacer su
trabajo de todas formas (ver «Y switchres tampoco puede») y encima estaba
apuntado a `monitor generic_15`, que no es este CRT VGA de 31 kHz. Cuando se
monte una sesión Xorg con un monitor arcade de verdad, se vuelve a encender.

**Ojo con probarlo en un juego horizontal.** En una pantalla 4:3, `keepaspect`
en Kung-Fu Master (que ya es 4:3) no cambia **nada**: con y sin él la imagen
llena la pantalla igual. Sólo se nota en los verticales. Es otra razón por la
que parecía que no se guardaba.

**La alternativa sin parche**, por si algún día se compila MAME limpio: un
`.ini` por juego. MAME los lee de `inipath` (`$HOME/.mame;/etc/mame`) en este
orden, comprobado con `-verbose`:

```
mame.ini -> horizont.ini / vertical.ini -> raster.ini -> source/<driver>.ini -> <juego>.ini
```

O sea que `~/.mame/kungfum.ini` con `keepaspect 0` funciona, y `vertical.ini`
vale para **todos** los verticales de golpe. Detalle: `-showconfig` **no** lee
los `.ini` por juego, sólo `mame.ini`, así que no sirve para comprobarlo; hay
que lanzar el juego con `-verbose` y buscar `Parsing .../<juego>.ini`.

### Recompilar tras la mudanza de carpetas

Los makefiles generados por genie llevaban dentro la ruta **absoluta vieja**:

```
fatal error: /home/eloy/groovymame_src/src/osd/sdl/sdlprefix.h: No such file or directory
```

No están en `src/` sino en `build/projects/sdl/mame/gmake-linux/*.make`, y no se
arreglan solos. Hay que regenerarlos:

```bash
cd ~/Dev/arcade/groovymame_src
PATH=/usr/lib/ccache:$PATH mold -run make REGENIE=1 -j10 NOWERROR=1 USE_QTDEBUG=0
```

### 2. Los verticales estirados: el arte, no la emulación

Medido: Pac-Man en el CRT ocupa 575x754 px, o sea 0.763. Correcto. **MAME lo
hace bien.** El estirado estaba en las capturas y los vídeos del frontend.

La regla que faltaba: **el monitor de una recreativa es 4:3 FÍSICO**, así que un
juego vertical se ve a 3:4 = 0.750 y uno horizontal a 4:3 = 1.333, *diga lo que
diga el tamaño del bitmap*. Tanto `-aviwrite` de MAME como las capturas de
arcadeitalia guardan los píxeles crudos:

| juego | guardado | debía verse | error |
|---|---|---|---|
| `qbert` | 240x256 = 0.938 | 0.750 | **25% más ancho** |
| `dkong` | 224x256 = 0.875 | 0.750 | 17% más ancho |
| `kungfum` | 256x256 = 1.000 | 1.333 | **25% más estrecho** |
| `pacman` | 224x288 = 0.778 | 0.750 | 4% |

`aspecto.sh` corrige lo ya descargado y `videos.sh` graba ya bien. La corrección
**agranda un lado en vez de encoger el otro**, para no tirar detalle — con un
tope de 1.5x, porque Frogger graba 224x768 (la placa da tres líneas por línea
útil) y agrandar ahí pedía inventar un 2,6x de ancho.

Trampa que costó un rato: **`SNAP` ya existe en el entorno** cuando algo se
lanza desde un snap (VS Code la pone a `/snap/code/NNN`), y `"${SNAP:-...}"` se
la come tan tranquilo. El síntoma es mudo: el script no encuentra ningún fichero
y dice que no hay nada que corregir. La variable se llama `CAPTURAS`.

### 3. Las scanlines: `crt-real`, crt-geom para una pantalla que YA es un CRT

crt-geom está pensado para un LCD: simula el tubo entero. Sobre un CRT de verdad
la mitad sobra y encima estorba, porque se suma a lo que el tubo ya hace.

`config/cabina/crt-real.json` — se instala en `bgfx/chains/` del emulador:

| | crt-geom | crt-real | por qué |
|---|---|---|---|
| `aperture_strength` | 0.40 | **0.0** | el tubo ya tiene máscara física; otra encima da muaré y roba luz |
| `curvature` | 1 | **0** | el tubo ya es curvo |
| `cornersize` | 0.01 | **0.0** | el bisel ya está |
| `spot_size` | 0.30 | **0.18** | el haz se afina: es lo ÚNICO que el CRT no da a 1024x768 |
| `monitorsRGB` | sRGB | **custom 2.4** | la salida es un CRT, no un panel: así la conversión de gamma sale neutra |

**Medido** en Kung-Fu Master a 1024x768, modulación entre filas contiguas:

| | modulación | nivel medio |
|---|---|---|
| sin shader | 2,2% | 138,8 |
| crt-geom | 29,2% | 104,4 |
| **crt-real** | **63,1%** | 100,3 |

Más del doble de profundidad **sin perder más brillo**: la luz que se llevan las
líneas es la que devuelve quitar la máscara.

Para ajustarlo, `spot_size`: 0.10 finísimas y muy marcadas, 0.30 las de
crt-geom, 0.50 ninguna.

**En los juegos verticales las líneas salen VERTICALES**, y es correcto: el
shader las dibuja siguiendo el barrido de la placa, que en un mueble vertical
iba girado. Medido en Pac-Man: 13,5% de modulación entre filas y **51,6% entre
columnas**. Sobre un tubo horizontal se ven como rayas de arriba abajo, que es
lo que se vería en el mueble original si lo tumbaras.

### Lo que había mal en `~/.mame/mame.ini`

- `bgfx_path` apuntaba a `/usr/share/games/mame/bgfx`, o sea a los assets del
  **MAME de la distro (0.264)**, no a los del GroovyMAME 0.289 que corre.
- `resolution` estaba fija a `1920x1080`, la del portátil. Ahora `auto`.
- `bgfx_screen_chains` era `crt-geom-deluxe`, que simula hasta la persistencia
  del fósforo.

Y **25 ficheros de `~/.mame/cfg/` fijaban una cadena por juego** (`<bgfx>`), que
manda sobre `mame.ini`: quitados, para que el ajuste central valga.

Detalle que despista: `/etc/mame/mame.ini` (del paquete de la distro) también se
lee, y pone `video opengl`. **Pierde** frente a `~/.mame/mame.ini`, comprobado
con `-showconfig`, pero está ahí.

### Si aún se ve estirado: es el tubo

`patron.py` saca un patrón a pantalla completa en el CRT con un círculo, una
rejilla y bandas de líneas de 1, 2 y 3 px. Dos respuestas de una vez:

- **Círculo ovalado** = el tubo estira; se arregla en el H-SIZE del monitor, no
  por software.
- **Banda de 1 px gris lisa** = el tubo no resuelve 768 líneas, y entonces
  ninguna scanline fina se va a ver por mucho shader que se ponga.

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
| `mame.ini` | `~/.mame/mame.ini` | `~/.mame/ini/mame.ini` |
| `bgfx_path` | junto al ejecutable | `/usr/lib/mame/bgfx` (de root) |
| `rompath` | `/usr/share/games/mame/roms` | `~/shared/roms/mame` |

Por eso `instalar.sh` ya no las supone: **se las pregunta a MAME** con
`mame_opcion()` (`-showconfig`), y el `mame.ini` que manda es el primero del
`inipath`. Con eso el mismo código acierta en las dos máquinas.

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
6. Arrancar `daemon.py` solo con la cabina (servicio de `systemd` de usuario).

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
