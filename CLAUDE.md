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
rama **`monedero-frontend`** (la parte del frontend) y en
**`creditos-monedero-frontend`** (la de MAME, que era un repo aparte hasta que
se fundieron el 2026-09-03).
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

Los valores viven en `arranque.dat`, como `video=N`. Y **`FORZAR=1` para rehacer
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

## La GPU de la cabina no puede subir de revoluciones

Eloy, 2026-09-03: *«el rendimiento es pésimo... la resolución del juego es
bastante baja y no debería haber problema»*. Tenia razon en el razonamiento y
en la sospecha (los drivers de NVIDIA), pero la causa es peor de lo que
parecia.

**Medido, con la cabina parada y nada mas corriendo** (la primera medicion
salio mal porque mis propias pruebas competian con su sesion por la GPU):

| | sin shader | crt-real |
|---|---|---|
| mappy | 100,00% | **28,28%** |
| kungfum | 98,25% | **17,13%** |

Y bajar la resolucion no lo arregla: a 640x480 crt-real sigue en 38%.

### La GPU corre a un tercio de lo que puede

```
$ sudo cat /sys/kernel/debug/dri/0/pstate
07: core 270 MHz memory 405 MHz
0f: core 573 MHz memory 800 MHz
AC: core 270 MHz memory 405 MHz     <- el actual
```

Es una **GeForce 410M (GF119, Fermi)** con **nouveau**. El driver lee la tabla
de relojes de la BIOS y ve que la tarjeta puede ir a 573/800, pero se queda en
270/405. Y no se puede forzar:

```
$ echo 0f | sudo tee /sys/kernel/debug/dri/0/pstate
tee: ...: Function not implemented
```

Nouveau implementa el reclocking solo en algunos chips, y este no esta.

### El driver propietario no es una salida

- Fermi solo lo soporta la rama **390.xx**, que es EOL desde 2022 y **no esta
  en los repos de Arch** (solo AUR).
- El kernel de la cabina es **7.1.10-arch1-1-15khz**, o sea muy por encima de
  lo que 390xx puede compilar, y ademas es un kernel propio de GroovyArcade.
- Lo unico oficial es `nvidia-open`, que empieza en Turing.

### Y los graficos integrados no estan: el i5-2430M los tiene, pero apagados

Idea de Eloy, y era la correcta. El procesador es un **Core i5-2430M** (Sandy
Bridge), que lleva **Intel HD Graphics 3000**. Pero en el bus PCI **no
aparece**: solo esta la NVIDIA. O sea que el firmware la tiene desactivada.

Es un **Sony VAIO VPCEG25FL** con BIOS INSYDE R0230Z8 de 2011. Los tres
conectores (`VGA-1`, `LVDS-1`, `HDMI-A-1`) cuelgan de `card0`, que es la
NVIDIA, asi que si la BIOS deja cambiar a integrada hay que comprobar que la
salida VGA siga funcionando.

Actualizar la BIOS **no** es una via: las de Sony son ejecutables de Windows, y
una actualizacion casi nunca añade una opcion de conmutacion que no estuviera.

### La salida: un shader que cueste una decima parte

`config/cabina/crt-lite.json`. Usa `hlsl/scanline`, que **ya viene compilado
con MAME** y hace una cuenta por pixel, en vez del modelo de haz de crt-geom
(varias muestras por pixel y dos `pow()` de gamma).

**Y sobre todo: en UNA sola pasada.** Cada pasada a pantalla completa son unos
6 MB de ida y vuelta a una memoria que va a 405 MHz, y eso pesa mas que la
cuenta en si:

| pasadas | kungfum | mappy |
|---|---|---|
| 4 (blit, upscale, scanline, blit) | 45% | 66% |
| 2 (blit, scanline) | 60% | 83% |
| **1 (scanline de screen a output)** | **85%** | **96%** |

| resolucion | juego | crt-lite | crt-real |
|---|---|---|---|
| 1024x768 | kungfum | 54,9% | 17,9% |
| 1024x768 | mappy | 69,1% | 26,5% |
| 800x600 | mappy | **99,0%** | 42,0% |
| 640x480 | kungfum | **94,3%** | 38,5% |
| 640x480 | mappy | **100,0%** | 63,7% |

Y no se ve peor, al reves: medido en Kung-Fu Master, **75,6% de modulacion
entre filas contra el 63,5% de crt-real, y con mas brillo** (109 contra 99).
Lo que se pierde es el modelado del haz, que sobre un CRT de verdad ya lo pone
el tubo.

**Bajar la resolucion NO es la respuesta**: a 800x600 el shader se ve mal
porque quedan pocas lineas por linea de juego. Con una sola pasada no hace
falta -- se queda a 1024x768.

**Trampa al escribir una cadena de bgfx:** referenciar un `"parameter"` desde
una pasada sin declararlo en el bloque `parameters` de la cadena hace que MAME
**se caiga con un segfault y sin ningun mensaje**. Le pasa con `time` y con
`jitter`. Costo tres intentos.

`instalar.sh` instala las dos cadenas y propone la ligera cuando detecta
nouveau.

## Switchres bajo X no puede: necesita KMS

Eloy, 2026-09-04: *«cuando estaba switchres activado iba bastante bien y se
veia bien, solo que Kung-Fu Master se veia pequeño»*. Su intuicion era buena:
con switchres el CRT recibe un modo casi nativo del juego y **las scanlines las
pone el tubo**, sin shader y sin gastar GPU. Pero bajo X no funciona.

**Los dos problemas tenian un mando cada uno**, y los dos se arreglaron:

- **Los verticales al 222%** era `autosync`. Switchres generaba un modo al
  doble de frecuencia (~121 Hz) y activaba `-syncrefresh`, asi que MAME se
  sincronizaba a 121 fps. Con `-noautosync`: mappy 99,2%, kungfum 98,2%,
  dkong 96,8%.
- **Kung-Fu Master pequeño** era `dotclock_min`. Su modo de 256x256 tiene un
  reloj de pixel bajisimo. Subiendolo a 25 MHz, switchres lo pasa a 1024x256.

**Pero el problema de fondo no se arregla.** Medido con el juego corriendo:

```
modo en el CRT:      1024x256
ventana de MAME:     1024x768
```

Switchres cambia el modo del CRTC pero **no redimensiona el escritorio**, asi
que el tubo enseña solo una franja del escritorio. Con `dotclock_min 0` el modo
era 256x256, una ventanita — y eso es exactamente lo que Eloy describia como
«se veia pequeño».

La razon la dice el propio switchres al arrancar:

```
Switchres/SDL2: (sdl2_display): SDL2 is only available for KMSDRM for now.
```

**Su backend de verdad es KMSDRM, no X.** Y GroovyArcade esta montada para eso:
trae `attractplus-kms` ademas de `attractplus-x11`, y `ga.conf` tiene
`video.backend` para elegir.

### Dos trampas encontradas por el camino

- **`switchres_ini 1` hace que `/etc/switchres.ini` mande sobre `mame.ini`.**
  `-showconfig` decia `dotclock_min 25` y switchres seguia usando 0, porque lee
  su propio fichero. Se resuelve con `switchres_ini 0`.
- **El Makefile de AM+ tiene la ruta de SFML escrita a mano:**
  `cmake --build obj/sfml` en vez de `$(SFML_OBJ_DIR)`. Compilar con
  `OBJ_DIR=obj-drm` configuraba SFML en `obj-drm/sfml` y luego instalaba
  `obj/sfml`, asi que el build fallaba con `SFML/Config.hpp: No such file`.
  Corregido.

### El build KMS ya existe

`make USE_DRM=1 OBJ_DIR=obj-drm EXE_BASE=attractplus-drm` produce un
`attractplus-drm` que reporta `SFML 3.0.1 +7z +Curl` **sin `+Xinerama`**, igual
que el `attractplus-kms` de la distro. Con el se puede probar el camino
autentico: `video.backend=KMS`, switchres generando modos nativos, sin shader.

**Sin probar todavia**: pasar la cabina a KMS quita X del medio, y con el se van
`~/.xinitrc` y el ajuste de xrandr que manda la imagen al CRT. Es un cambio que
hay que hacer delante de la maquina, no por ssh.

## En KMS no hay bgfx, y eso tumbaba los juegos

Eloy paso la cabina a `video.backend=KMS` el 2026-09-04 y los juegos empezaron a
crashear devolviendo al frontend. La causa estaba en `attract.log`, que en KMS
recoge tambien la salida del emulador:

```
Initializing BGFX library
BGFX: Unsupported SDL window manager type 13
Setting BGFX platform data failed
```

**bgfx no soporta KMSDRM** (tipo 13 = `SDL_SYSWM_KMSDRM`). El `video bgfx` que
habia dejado puesto para el shader mata a MAME nada mas arrancar. Culpa mia por
no anticiparlo al cambiar de backend.

### Y en KMS no hace falta shader

Es el camino autentico, y ahora si funciona: switchres genera el modo **nativo**
de cada juego y **las scanlines las pone el tubo**. Medido, todos al 100%:

| juego | modo que pone switchres |
|---|---|
| tapper | 1024x480 @ 60.00 |
| mappy, mspacman | 661x496 @ 60.61 |
| dkong | 796x512 @ 59.62 |
| kungfum | 1024x256 @ 112.68 |

Fijarse en los refrescos: **60.61 Hz** es la frecuencia real de la placa de
Namco, no un 60 redondeado. Eso es lo que switchres hace bien y no se puede
imitar con un shader.

La configuracion de KMS es distinta de la de X:

```
video               opengl        <- bgfx no vale aqui
switchres           1
switchres_ini       0             <- si no, /etc/switchres.ini manda
autosync            0             <- si no, los verticales van al 222%
dotclock_min        25            <- si no, Kung-Fu Master sale en 256x256
bgfx_screen_chains  (vacio)
```

`instalar.sh` lee `video.backend` de `ga.conf` y aplica una u otra.

### Y aun asi no se veian: switchres apuntaba al panel, no al CRT

Los modos nativos se creaban... **en el LCD interno**. El log lo dice sin
rodeos:

```
DRM/KMS: card 0 connector 0 id 45 name LVDS-1 selected as primary output
```

Switchres coge el conector 0 y ese es el panel. El CRT no recibia ninguno de
esos modos, de ahi que no hubiera scanlines y que Kung-Fu Master siguiera igual
que al principio. Todas las medidas de «100% con modo nativo» eran ciertas,
pero sobre la pantalla equivocada.

Dos arreglos, y hacen falta los dos:

- **`display VGA-1` en `/etc/switchres.ini`** (con `switchres_ini 1` en
  `mame.ini`, o no se lee). Comprobado: pasa a decir
  `connector 1 id 47 name VGA-1 selected as primary output`.
- **Apagar el panel en el arranque**, que quita la ambiguedad para KMS, para X
  y para la consola. Y aqui otra sorpresa: **la cabina arranca con GRUB, no con
  syslinux** — por eso el menu de gasetup que buscaba `syslinux.cfg` era codigo
  muerto y no encontraba nada. Se hace en `/etc/default/grub`:

```
GRUB_CMDLINE_LINUX_DEFAULT="video=VGA-1:e video=LVDS-1:d ..."
sudo grub-mkconfig -o /boot/grub/grub.cfg
```

El VGA va **delante** porque `getConnectorFromKernel` de gasetup lee el primer
`video=` de la linea para decidir el conector.

Si tras reiniciar no hubiera imagen: en el menu de GRUB, `e`, quitar
`video=LVDS-1:d` y arrancar. Copia previa en `/etc/default/grub.antes_crt`.

### El frontend para KMS

`make USE_DRM=1 OBJ_DIR=obj-drm EXE_BASE=attractplus-drm` deja un binario listo
en el repo de la cabina. De momento corre el `attractplus-kms` de la distro, que
funciona y usa nuestra configuracion igual (los plugins y el layout viven en el
directorio de configuracion, no en el binario). Cambiarlo es:

```bash
sudo cp -a /usr/local/bin/attractplus-kms /usr/local/bin/attractplus-kms.antes
sudo install -m 755 ~/attractplus-creditos/attractplus-drm /usr/local/bin/attractplus-kms
```

## En un CRT de PC las scanlines nativas son IMPOSIBLES: es aritmética

Medido el 2026-09-04, tras dejar la cabina en KMS + switchres y ver que Mappy
iba perfecto pero **sin una sola scanline**, mientras Kung-Fu Master sí las
tenía pero salía centrado y sin estirar.

No es un ajuste mal puesto. Lo dice el propio preset del monitor:

```
Monitor range 31400-31600 Hz, 100-130 Hz vertical, 200-256 lineas
Monitor range 31400-31600 Hz,  50-65 Hz vertical, 400-512 lineas
```

- **Kung-Fu Master**: 256 líneas a 56 Hz. Cabe en el primer rango doblando el
  refresco → modo `1024x256 @ 112,68 Hz` → **scanlines**, pero el tubo lo
  centra sin estirar.
- **Mappy**: 288 líneas a 60,6 Hz. 288 **no cabe** en «200-256», así que
  switchres está obligado a ir al segundo rango → `661x496 @ 60,61` → y a 496
  líneas el haz ya no deja huecos → **sin scanlines**.

Enseñar 288 líneas a 60 Hz pide ~18 kHz horizontales. **Un CRT VGA de 31 kHz no
baja de ahí.** Eso es lo que hace un monitor de recreativa de 15 kHz y éste no.

**Y `dotclock_min` no cambia nada**: comprobado con 0, 15 y 25, los verticales
reciben siempre el mismo modo.

> **Regla:** en un CRT de PC, las scanlines sólo las puede dibujar un shader.
> Y el shader pide X, porque **bgfx no soporta KMSDRM**. Así que KMS+switchres
> es el camino bueno *sólo* en un monitor de recreativa.

## El driver de X era el cuello de botella (DRI2 contra DRI3)

Encontrado el 2026-09-04 buscando de dónde sacar más rendimiento, y resultó ser
lo más gordo de toda la sección de vídeo.

Con una NVIDIA, Xorg autoconfigura el **DDX viejo `nouveau`**, que sólo ofrece
DRI2: cada fotograma se copia a través del servidor X. En el log:

```
(II) NOUVEAU(0): [DRI2] Setup complete
(II) GLX: Initialized DRI2 GL provider for screen 0
```

Cambiándolo a **`modesetting` + glamor** (que usa el Gallium de Mesa y habilita
DRI3), con el shader `crt-lite` puesto y a 1024x768:

| juego | DDX `nouveau` | `modesetting`+glamor |
|---|---|---|
| profpac | 79,5% | **100%** |
| simpsons | 88,7% | **100%** |
| mwalk | 96,3% | **100%** |
| kungfum | 98,2% | **100%** |
| kungfum con `crt-real` | 20,2% | **69,6%** |
| mappy con `crt-real` | 28,6% | **100%** |

Se instala solo (`instalar.sh`, `tarea_crt`) y se deshace borrando
`/etc/X11/xorg.conf.d/20-modesetting.conf`.

**Cómo se supo que no era la CPU ni el relleno de píxeles**, que es la parte
que evitó perseguir la pista falsa:

- Con **`-video none`** los tres iban al **100%**: la emulación tenía tiempo de
  sobra, todo se iba en pintar.
- **Bajar a 640x480 no ayudaba** (profpac 79,5% → 79,6%): si fuera relleno de
  píxeles, un cuarto de píxeles se habría notado. Lo que costaba era la subida
  del bitmap y el intercambio de buffers, que no dependen de la resolución de
  salida.

### Y el governor de la CPU no aporta nada

Probado por si acaso, porque parecía obvio. **No**: la CPU ya sube sola a
2,79 GHz con `schedutil` (`intel_cpufreq`), y `performance` sale igual o peor.

| | schedutil | performance |
|---|---|---|
| mwalk | 96,3% | 87,0% |
| simpsons | 90,1% | 87,3% |
| profpac | 76,4% | 75,6% |

### Las cifras viejas del shader estaban mal medidas

Lo que este documento decía antes (crt-lite al 55% en Kung-Fu Master, crt-real
al 18%) se midió **con mis propias pruebas corriendo a la vez** y compitiendo
por la GPU. Las buenas, con la máquina parada, están en la tabla de arriba.

`crt-lite` va al **100% en todos los juegos probados** y encima se ve mejor:
**84,5% de modulación entre filas** en Kung-Fu Master ocupando los 1024x768
enteros, y **90,8% entre columnas** en Mappy (en un vertical las líneas salen
verticales, y es lo correcto: el shader sigue el barrido de la placa). Medido
capturando la salida VGA de verdad, no supuesto.

### Dos cosas más que estaban puestas y sobraban

- **`verbose 1` en `mame.ini`**: un par de cientos de líneas por lanzamiento, y
  en KMS acaban dentro de `attract.log`.
- **El plugin `data` de MAME está roto** en esta versión y suelta un error de
  Lua en cada arranque:
  `data_story.lua:19: attempt to assign to const variable 'line'`.
  Apagado en `~/.mame/plugin.ini` (`data 0`); se enciende otra vez ahí.

## La cabina nueva: i3 con graficos integrados, y ahi si sobra GPU

Eloy cambio de maquina el 2026-09-04. Sigue siendo un VAIO, pero:

| | cabina vieja | cabina nueva |
|---|---|---|
| CPU | i5-2430M | **i3-2350M** (2,3 GHz, 2 nucleos / 4 hilos) |
| GPU | GeForce 410M (nouveau, clavada a 270 MHz) | **Intel HD 3000** en `00:02.0` |
| driver | `modesetting`+glamor sobre nouveau | `modesetting`+glamor sobre i915 |

Es el **mismo disco** en otro chasis: la configuracion, el repo y las roms
estaban ya en su sitio, y el `/etc/X11/xorg.conf.d/20-modesetting.conf` que
puso `instalar.sh` seguia valiendo. `glamor X acceleration enabled on
Mesa Intel(R) HD Graphics 3000 (SNB GT2)`, OpenGL 3.3.

**La IP cambia** (la cabina va por anclaje de movil): el rango es `/28`, asi que
se encuentra con un barrido de catorce direcciones buscando el puerto 22.

**Aqui sobra GPU.** Medido con la maquina parada, a 1024x768:

| cadena | kungfum | mappy | simpsons | profpac | mwalk |
|---|---|---|---|---|---|
| sin shader | 100% | 100% | 100% | 100% | 100% |
| crt-lite | 100% | 100% | 100% | 100% | 100% |
| **crt-real** | **100%** | **100%** | **100%** | **100%** | **100%** |
| crt-geom | 100% | 100% | 100% | 100% | 100% |
| crt-geom-deluxe | 100% | 100% | 100% | – | – |
| `hlsl` | 37% | 60% | 35% | 34% | 36% |

Solo `hlsl` se queda fuera. Y a 1280x1024 todo sigue al 100% menos
crt-geom-deluxe, que baja a 99,2%.

### La metrica con la que compare los shaders estaba mal

Esto importa mas que las cifras, porque me hizo elegir mal. Yo medaa
**la diferencia media entre filas contiguas**. Eso penaliza al shader que
tiene mas pixeles por linea de juego: con un perfil de haz suave, dos filas
vecinas se parecen aunque el pico y el valle esten igual de separados.

La buena es **pico a valle DENTRO de cada periodo de scanline**:

| | px por linea | contraste | brillo |
|---|---|---|---|
| crt-lite @1024x768 | 3,00 | 69,7% | 112 |
| crt-real @1024x768 | 3,00 | 58,8% | 97 |
| crt-real @1280x1024 | 4,00 | 69,8% | 94 |
| **crt-real retocado @1280x1024** | **4,00** | **73,2%** | **94** |
| crt-geom-deluxe @1280x1024 | 4,00 | 20,2% | 117 |

O sea que **crt-real con 4 pixeles por linea iguala y supera a crt-lite**, y
encima trae lo que crt-lite no tiene: dilatacion del haz en las zonas claras,
interpolacion Lanczos y gamma correcta. Es el defecto ahora; crt-lite se queda
para GPU flojas.

crt-geom-deluxe **no sirve aqui** aunque corra: su persistencia de fosforo y su
mascara lavan las lineas (20,2%) y encima la mascara se suma a la del tubo.

### El retoque de crt-real

Medido en Kung-Fu Master a 1280x1024:

| spot_size | monitorgamma | contraste | brillo |
|---|---|---|---|
| 0.18 | 2.4 | 69,4% | 95,2 |
| 0.16 | 2.4 | 75,7% | 88,1 |
| **0.16** | **2.6** | **73,4%** | **94,1** |
| 0.16 | 2.8 | 71,1% | 99,6 |
| 0.14 | 2.2 | 85,2% | 75,1 |

**`monitorgamma` va al reves de lo que parece: SUBIRLO aclara.** Lo supuse al
contrario y la primera tanda de variantes salio toda mas oscura.

Hay un compromiso duro detras: haz mas fino = mas contraste y menos brillo. Es
fisica, no un ajuste mal puesto — media pantalla apagada da menos luz.
`0.16 / 2.6` es el punto donde se gana contraste sin perder brillo.

### 1280x1024 a 60 Hz, y por que el aspecto no se rompe

El tubo ofrece `1024x768@85`, `1152x864@75` y `1280x1024@60`. Se eligio el
ultimo: **4 pixeles de salida por linea de juego en vez de 3**, y ademas su
refresco casi cuadra con el de las placas.

- **1280x1024 es 5:4 y el tubo es 4:3** (mide 310x230 mm). MAME lo resuelve
  solo con **`aspect 4:3`** en `mame.ini`, que le dice el aspecto FISICO de la
  pantalla; sin eso supondria pixeles cuadrados y la geometria saldria un 6,7%
  ancha. Verificado con captura: los verticales siguen bien proporcionados.
- **AM+ no tiene ese ajuste**, pero no hace falta: estira el layout a la
  ventana, la ventana cubre el tubo entero y el tubo es 4:3, asi que sale bien.
  Comprobado comparando capturas a 1024x768 y a 1280x1024.
- **`waitvsync` NO se puede encender**, aunque a 60,02 Hz parezca la ocasion
  perfecta. Ver la seccion siguiente: mata el arranque acelerado.

**Lo que no se puede medir por ssh: el parpadeo.** Un CRT de PC a 60 Hz
parpadea mas que a 85. Si molesta, se cambia el `--mode` de `~/.xinitrc`.

### Dos trampas de esta tanda

- **Las opciones booleanas de MAME no llevan valor.** `-waitvsync 0` responde
  `Error: unknown option: 0` y el juego no arranca; es `-nowaitvsync`. Perdi
  una tanda entera de medidas con las casillas vacias por esto.
- **Mi detector de "area activa" se traga las pantallas oscuras.** El titulo de
  Mappy es casi todo negro, asi que daba un area de 492x1018 en vez de los
  ~747x1024 que le tocan, y de ahi un "1,71 px por linea" que no significaba
  nada. Con pantallas oscuras hay que fijar el area, no detectarla.
- **Una medida suelta de `profpac` al 20,68%** no se reprodujo en cuatro
  pasadas (99,96%). Era del banco de pruebas, no de la configuracion.

### Un fallo del layout que no es de video

En el frontend, los titulos largos salen recortados por los lados
(`lassic Collection Vol.2`, `ame That Tune`). Pasa **igual a 1024x768 y a
1280x1024**, asi que es del layout `Arcade-UMAG`, no de la resolucion.

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

## Los videos: tres arreglos distintos (2026-09-04)

Pedidos por Eloy: que los juegos usen lo que ya dice `arranque.dat` para
ahorrar tiempo, que los videos no se vean tan mal en el modo espera, y que los
verticales no salgan estirados. **Son tres causas independientes.**

### 1. El estirado NO era de los videos: era un ajuste del salvapantallas

El salvapantallas de serie (`/usr/local/share/attractplus/screensaver/screensaver.nut`)
declara una opcion **`preserve_ar`** y su valor por defecto es **`"No"`**. Con
eso mete el video en `fe.layout.width x height` **sin respetar la proporcion**:
un vertical de 224x298 estirado a pantalla completa. En `attract.cfg` no habia
bloque `saver_config`, asi que mandaba el defecto.

```
saver_config
    param                   preserve_ar Yes
```

Verificado con capturas del salvapantallas de verdad (bajando
`screen_saver_timeout` a 5 s y restaurandolo despues): Dig Dug sale con bandas
negras a los lados y Tapper ocupa su ancho. El layout pone
`preserve_aspect_ratio` en sus tres modos (video simple, collage 2x2 y collage
4x4), asi que el ajuste vale para todos.

**Lo que NO habia que hacer:** recodificar los videos con bandas negras
metidas. Habria arreglado el salvapantallas y estropeado el hueco del layout
principal, que si respeta la proporcion.

### 2. La mala calidad: 33 kbps sobre 224 px

`pacman.mp4` medido: **224x298 a 33 kbps**. Dos problemas a la vez -- el video
es diminuto y AM+ lo estira hasta los ~700 px del hueco del layout, y encima el
h264 a ese tamano con crf 26 gastaba una miseria.

Se amplia **antes** de codificar, y en dos pasos que no son intercambiables:

1. un multiplo **entero** con `flags=neighbor`, que duplica pixeles exactos y
   mantiene el filo del arte original;
2. la correccion de proporcion con `flags=lanczos`, que es la parte no entera,
   ya sobre una imagen grande.

Hacerlo al reves reparte mal las filas y se ve irregular. Con `crf 20`:

| | antes | despues |
|---|---|---|
| pacman | 224x298, 33 kbps | **672x894, 74 kbps** |
| kungfum | 340x256 | **1020x768, 250 kbps** |
| contra | – | **672x894, 1,75 Mbps** |

`AMPLIAR=0` vuelve al tamano crudo.

### 3. El salto sale de `arranque.dat`, pero solo como SUELO

`arranque.dat` ya sabe cuanto tarda en arrancar cada placa, asi que no hace
falta medirlo dos veces. Dos cuidados que costaron pensarlos:

- **Solo se mira la linea PROPIA del juego, nunca la de `defecto`.** La de
  defecto vale 5 s, que es MENOS que el salto general de 8: usarla haria que
  los juegos sin linea propia empezaran el video ANTES que antes.
- **Es un suelo, no el valor final.** `arranque.dat` dice cuando la placa esta
  lista; la demo llega despues. Contra arranca a los 7 y su demo empieza a los
  16 (medido con `--tira`: test hasta los 4, «PLEASE DEPOSIT COIN» a los 8,
  titulo a los 12).

Precedencia: `SALTO=` de la linea de ordenes > `video=` de `arranque.dat` >
`arranque.dat` > el defecto de 8. El script dice de donde salio cada uno.

**Todo el ajuste por juego vive en `arranque.dat`** (pedido por Eloy el
2026-09-05: *«así no debo ajustar el video de cada juego manualmente»*). Antes
había una tabla `SALTOS` dentro de `videos.sh`, y afinar un juego obligaba a
tocar el código. Ahora son dos claves más de `arranque.dat`, al lado de las de
la carga:

```
contra segundos=7 velocidad=0 video=16
```

- **`video=N`** — el segundo en el que empieza lo que quieres grabar.
- **`videodura=N`** — cuánto dura ese vídeo (opcional).

**`creditos.lua` las ignora**, y eso está comprobado ejecutando su parser: guarda
cualquier clave y sólo consulta las suyas, así que añadirlas no le afecta ni
genera avisos.

**Al regrabar se borra el vídeo anterior**, y no sólo el `.mp4`: AM+ prefiere el
vídeo a la imagen fija y acepta varias extensiones, así que un `.avi` olvidado
de una grabación vieja seguiría mandando sobre el `.mp4` nuevo y parecería que
regrabar no sirve de nada. Se borran todas las extensiones de vídeo del juego
(la `.png` no se toca: es el respaldo). Además se convierte a un temporal y se
mueve al final, así el frontend nunca se encuentra un `.mp4` a medio escribir y
un fallo de conversión deja el vídeo viejo en su sitio.

**Y NO se ejecuta `creditos.lua` al grabar**, aunque sea lo que lee
`arranque.dat` en la cabina: ese script tapa el arranque pintando la pantalla
de **negro**, y ese negro entraria tal cual en el video. Se toma el dato, no el
comportamiento.

### Lo que de verdad ahorra tiempo: `-nothrottle`

La grabacion iba a **tiempo real** porque `-seconds_to_run` no quita el freno.
Medido con Pac-Man, 22 segundos emulados:

| | reloj |
|---|---|
| con freno | 26 s |
| `-nothrottle` | **11 s** |

El AVI sale identico (`-aviwrite` guarda todos los fotogramas emulados, tenga
freno o no): son 249 MB en los dos casos.

## Puntuaciones sin créditos: `puntajes.py`

Pedido por Eloy el 2026-09-05: conservar los puntajes de cada juego **sin**
arrastrar los créditos entre sesiones, y dejarlos en un fichero para que otro
programa suyo los lea después, sin contar los nombres ficticios que traen
algunos juegos de fábrica.

### La pieza que ya estaba: el plugin `hiscore` de MAME

MAME trae un plugin `hiscore` (activado en la cabina) que lee la tabla de
puntuaciones **de la RAM del juego** y la escribe en `<hi_path>/<juego>.hi`.
Eso es exactamente lo que permite separar las dos cosas: **los créditos viven
en la NVRAM y las puntuaciones no tienen por qué**.

Su `hiscore.dat` cubre **5856 juegos** y dice *dónde* vive la tabla de cada uno
y cuánto ocupa:

```
@<cpu>,<espacio>,<direccion>,<longitud>,<espera1>,<espera2>[,<relleno>]
```

**Lo que NO dice es cómo está ordenada por dentro**, y eso cambia con cada
placa. Comprobado también que `sort_hiscore.lua` del plugin no ayuda: es sólo
un utilitario para ordenar el `.dat`.

### La regla de `nvram=0`, revisada juego a juego

La NVRAM de muchas placas guarda **créditos y puntuaciones a la vez**, así que
apagarla quita los créditos viejos pero también tira los puntajes. No hace
falta elegir siempre:

| situación | qué hacer |
|---|---|
| está en `hiscore.dat` | `nvram=0` es **seguro**: los puntajes se guardan aparte |
| no está, pero sí en `creditos.dat` **verificado** | **NO** poner `nvram=0`: el barrido ya pone los créditos a 0 y la NVRAM conserva los puntajes |
| en ninguno de los dos | `nvram=0` y se pierden los puntajes (o se le busca la dirección) |

**Corregido con esto:** `tapper` y `rbtapper` tenían `nvram=0` y no les hacía
falta — los dos están en `creditos.dat` con dirección verificada (`e011`), así
que el barrido les limpia los créditos y ahora conservan sus puntuaciones. Se
les borró la NVRAM vieja una vez, porque `nvram=0` evita **guardar**, no
**cargar**. `mwalk` se queda con `nvram=0`: no está en ninguna de las dos
tablas, así que ahí sí hay que elegir.

**Nunca a un CPS3** (`sfiii3`): ahí la «NVRAM» son los 81 MB de la flash con el
juego grabado del CD, y sin ella vuelve a pedir los ~70 minutos de reescritura.

### `puntajes.py` + `puntajes.dat`

`puntajes.py` traduce esos `.hi` a un JSON legible. **Va fuera de MAME a
propósito**: no toca `creditos.lua`, no depende de la versión de Lua del
emulador y se puede lanzar con la cabina apagada.

El reparto de responsabilidades copia el de `creditos.dat`:

- **`hiscore.dat`** (de MAME) dice *dónde* está la tabla → trocea el `.hi`.
- **`puntajes.dat`** (nuestro) dice *cómo* se lee ese bloque.

```
1943  entradas=6 bytes=16 puntos=0,8,digitos nombre=8,3,idx:capcom
```

Añadir un juego es **añadir una línea**, no tocar código. Formatos de
puntuación: `bcd`, `bcdle`, `digitos` (un dígito decimal por byte), `be`, `le`;
de nombre: `ascii` o `idx:<alfabeto>` para las placas con tabla de caracteres
propia.

Descifrados y **verificados contra los `.hi` de la cabina** (las cinco tablas
salen siendo las de fábrica conocidas, que es la comprobación):

| juego | tabla | lo que sale |
|---|---|---|
| `1943` | 6×16 | 20000 TAE, 15000 YAM, 10000 POO… (defecto de Capcom) |
| `bublbobl` | 5×7 | 30000 I.F, MTJ, NSO, KIM, YSH (defecto de Taito) |
| `dkong` | 5×34 | 76500, 61000, 59500, 50500, 43000, sin iniciales |
| `pacman` / `mspacman` | 1×4 | una sola puntuación, sin iniciales |

**Y verificar en pantalla evitó un error de 10x.** Le había puesto
`multiplica=10` a `dkong` razonando que sus puntuaciones son múltiplos de 100.
Es **falso**: capturada su tabla de atracción en la cabina, el juego enseña
`007650 / 006100 / 005950 / 005050 / 004300`, exactamente lo que da el
descifrado crudo. En `bublbobl` sí era correcto — marca `HIGH SCORE 30000` y el
BCD guarda `003000`.

> **Regla:** una receta de `puntajes.dat` no está confirmada hasta que se ha
> comparado con lo que el juego enseña en pantalla. El razonamiento «esas
> puntuaciones no pueden ser» no vale como prueba.

### `asteroid`: sin receta, y por qué

Se intentó y **se deja sin resolver a propósito**, porque una receta equivocada
es peor que ninguna — el mismo criterio que en `creditos.dat` con las
direcciones ambiguas.

- **No enseña su tabla en el modo de atracción**: sólo la demo con
  `1 COIN 1 PLAY`, así que no hay nada contra lo que correlacionar.
- **Escribirle un patrón no vale.** Su bloque (`0x001d`, 53 bytes) lleva también
  **estado**, y al escribirlo el juego saltó a `YOUR SCORE IS ONE OF THE TEN
  BEST / PLEASE ENTER YOUR INITIALS`. Es la lección que ya estaba escrita para
  el barrido de créditos, y resulta que vale igual para una placa en marcha, no
  sólo para una que se autoprueba.
- **Jugando de verdad** (moneda, START y disparar solo 60 s) sólo cambiaron 4
  bytes: el 0 pasó de `00` a `0x59` —parece la puntuación, unos 590 puntos— y
  los 21, 22 y 23 son estado. Y esos tres caen **dentro** de lo que sería la
  quinta entrada si la tabla fuera de 10×5, así que el bloque mezcla tabla y
  estado.

Para cerrarlo haría falta terminar una partida y simular la entrada de
iniciales (rotar + hiperespacio), que ya es otro proyecto.

### Las direcciones de `tapper` y `rbtapper`, verificadas

`rbtapper` tenía su `e011` heredada de `tapper` por parecido, no comprobada. Se
comprobó ejecutando, con `tapper` de control, y las dos pasan: escribir 0 se
queda puesto y una moneda lo sube 0→1.

**Trampa que costó una pasada: Tapper y Root Beer Tapper corren a 30 Hz**, no a
60. Un guion que espere «frames» y se lance con `-str 15` nunca llega al frame
480, porque ahí 15 segundos son 450 frames. En placas MCR hay que contar a 30.
Explica de paso por qué sus líneas de `arranque.dat` llevan `segundos=3` y
parecen tan cortas: son 90 frames, no 180.

### hi2txt-xml: la base que resuelve las recetas

Eloy pasó varias fuentes el 2026-09-05 y una lo cambió todo:
**[hi2txt-xml](https://github.com/GreatStoneEx/hi2txt-xml)** (GreatStoneEx,
GPL-2), una base comunitaria con la **estructura interna** de la tabla de unos
**3.100 juegos**. Es exactamente la pieza que yo estaba deduciendo a mano:

| | |
|---|---|
| `hiscore.dat` (de MAME) | dice **dónde** vive la tabla |
| `hi2txt-xml` | dice **cómo** se lee por dentro |

Su formato es rico y cubre lo que a mí se me atascó: `<loop>`, tipos
`int`/`text`/`raw`, BCD, endianness, charsets con desplazamiento, y
**`nibble-skip`/`byte-skip`** — la codificación por nibbles de Q*bert y los
Williams. Y lee **tanto `.hi` como NVRAM**.

`hi2txt.py` implementa el subconjunto que usan estos juegos. **Validado contra
mis 13 verificaciones en pantalla: acierta los 12 que describe, al número
exacto.** Eso es lo que permite fiarse de los otros 30.

**No se copia al repo** (es GPL-2 y se actualiza sola): se baja aparte, igual
que la colección de cheats, y se le indica con `--hi2txt <carpeta db>`.

**Cobertura: de 21 recetas a 71 juegos descifrables** — 56 por hi2txt y 15 con
recetas propias. **De ellos, 19 comparados con el marcador del propio juego**;
del resto sabemos que se leen, no que el número sea el que el jugador vio. De los 94 instalados, sólo **3 no pueden guardar puntuaciones
en absoluto** (`dlair`, `kinst`, `mt_srage`), así que el denominador real es 91.
Las dos fuentes se complementan.

**Comprobado contra el marcador en pantalla: 15 de 15 al número exacto**, sin
una sola regresión respecto a lo que yo había verificado a mano.

Dos cosas más que hicieron falta para llegar ahí, y las dos eran fallos míos:

- **`<sameas id="otro"/>`: 2322 de los 3102 XML son redirecciones.** Los clones
  y variantes comparten estructura y se apuntan al original
  (`rbtapper` → `tapper` → `journey`). Sin seguirlas se pierde la mayor parte
  de la base, y **en silencio**: el fichero existe y parece vacío.
- **MAME no llama `nvram` a todo.** Los NeoGeo guardan en `saveram`, Star Wars
  en `x2212` y Gauntlet en `eeprom`, todos dentro de `~/.mame/nvram/<juego>/`.
  Buscando sólo un fichero llamado `nvram` se quedaban fuera diez juegos que sí
  tenían sus datos escritos. Ahora se le pregunta al XML qué fichero quiere.

Tres detalles que costaron encontrarse, y ninguno da error:

- **`decoding-profile="bcd"` no siempre es BCD empaquetado.** Cuando todos los
  bytes valen 0-9 la placa guarda **un dígito por byte**; leerlo como
  empaquetado multiplicaba por diez mil (1943 daba 200000000 en vez de 20000).
  Se distingue mirando los datos.
- **Los `<format>` cuelgan de `<output>`**, no de la raíz. Buscándolos sólo en
  la raíz salían vacíos y las puntuaciones perdían su `*10` en silencio.
- **`*10` y `+1` son operaciones implícitas**: el identificador ES la
  operación. **706 de los 3.102 XML** referencian un formato que no definen,
  así que no es un descuido suyo sino parte del formato.

### Tres fallos más al aplicar hi2txt, todos por elegir mal

Los tres daban «no se descifra» sin más, y ninguno era culpa de la base:

- **Cogía el fichero equivocado.** Juegos como `simpsons2p` tienen un `eeprom`
  escrito Y una estructura que describe el `.hi`. Al elegir el `eeprom` sólo
  porque estaba ahí, fallaba con «no hay estructura para la fuente eeprom»
  teniendo el dato bueno al lado. **Ahora el orden lo manda el XML**, no una
  lista fija mía.
- **Sólo probaba una estructura.** Un XML puede describir varias (versiones
  distintas de `hiscore.dat`), y yo elegía por el tamaño declarado y me rendía.
  Ahora se prueban todas y vale la primera que descifre — eso solo recuperó
  `tmnt`, `xevious` y `galaxian`.
- **La tabla de fábrica vale como `.hi`.** Mientras nadie haya jugado, lo que
  leímos de la RAM con `--fabrica` es exactamente lo que habría en el `.hi`, así
  que se usa cuando el XML pide `.hi` y todavía no existe.

### Dos sitios más donde mirar, y una regla que faltaba

- **El «espacio» de `hiscore.dat` puede ser un SHARE de memoria**, escrito
  `<nombre>/share` en vez de `program` — Missile Command guarda ahí su tabla.
  `volcar.lua` lo trataba como espacio de CPU y no volcaba nada. Se resuelve
  igual que en el plugin (`init.lua:129`): `manager.machine.memory.shares`.
- **MAME nombra el fichero por el CHIP, no por una lista corta.** Además de
  `nvram`, `saveram`, `eeprom` y `x2212` hay cosas como `at28c16` (la EEPROM de
  Namco Classic Collection). Cuando el XML no dice nada, se prueba cualquier
  fichero que haya en la carpeta del juego.

Y la regla que faltaba, que salió de romperlo: **si el XML declara una fuente,
no se busca fuera de ella.** Al permitir el comodín para todos, `arkanoid` pasó
a leer su `nvram` en vez de su tabla, y devolvía **0 en vez de 50000 sin dar
ningún error** — un descifrado perfectamente válido y perfectamente falso.

### `byte-swap`: nueve juegos daban basura sin avisar

El hallazgo más importante de esta tanda, y salió buscando otra cosa. Los XML
pueden declarar **`byte-swap="2"`**: los bytes van intercambiados por parejas,
porque la placa vuelca su memoria en palabras de 16 bits. Lo usan 63 XML, y de
los juegos de esta cabina afecta a **nueve** — todos los NeoGeo, `mwalk` y
`goldnaxe`.

No lo implementaba, y el fallo es **mudo**: el descifrado no da error, devuelve
números y nombres perfectamente formados pero equivocados. Se ve a simple vista
en el `saveram` de un NeoGeo, donde pone `ABKCPUR MAO` en vez de `BACKUP RAM`.
Con el arreglo salen las tablas reconocibles: `mwalk` 50000/45000/40000 con
iniciales `M.J`, `mslug2` 107400 APE / 98410 BAT / 89330 CAT.

### Descifrar «lo que quepa», y el filtro que hace falta detrás

Cuando el XML describe más posiciones de las que hay en los datos —porque
describe otra versión de `hiscore.dat`— vale más quedarse con las completas que
rendirse. Pero eso deja pasar basura, así que hay un filtro después: se recortan
las posiciones vacías del final, se corta donde la tabla deja de estar ordenada,
y se exige que la primera llegue a 1000.

Los dos límites salieron de equivocarme en las dos direcciones:

- Sin filtro, `tmnt` daba **cien** posiciones de 312, 257, 206… Números que
  bajan y no son puntuaciones de nadie.
- Con el filtro demasiado estricto (tope de 40 posiciones) se caía `avsp`, que
  tiene una tabla **de verdad** de 49 (300000, 250000, 200000, 150000…). El tope
  está en 64 por eso.

### `atetris` guarda las puntuaciones en ASCII

Diez puntuaciones de seis dígitos seguidas (`007000006500…`) y después los diez
nombres en un bloque aparte, con 18 bytes de firma (`TETRISTETRISTETRIS`) en
medio. De ahí dos cosas nuevas en `puntajes.dat`: el formato `texto` y la clave
`nombres=`, para las placas que no intercalan los campos.

### Lo que NO se pudo, y por qué

**Los NeoGeo no tienen tabla todavía.** Descifrado su `saveram`, sólo contiene
la cabecera `BACKUP RAM OK` y el nombre del juego (`SAMURAI`, `FATAL FURY`,
`DOUBLE DRAGON`, `STREET HOOP`). La tabla aparece cuando alguien juega: **no es
que falte la receta, es que no hay nada que leer**.

Y probar las 3102 estructuras del corpus contra un juego que no tiene la suya
**no funciona**: las placas no comparten la posición de la tabla ni dentro de la
misma familia. Se intentó con los NeoGeo y sólo salieron falsos positivos.

### Medir por una ruta y publicar por otra: el número estaba inflado

Estuve dando **66** cuando la cifra real era **59**. El script de medición
tenía su propia copia de la lógica de descifrado, más permisiva que la del
export: no aplicaba el filtro de plausibilidad. O sea que medía una cosa y se
publicaba otra.

> **Regla:** un script que mide cobertura tiene que llamar a la MISMA función
> que produce el resultado, no reimplementarla.

Al arreglarlo salieron dos cosas más:

- **El filtro estaba demasiado apretado.** Exigir que la primera posición
  llegase a 1000 tiraba tres casos buenos para cazar uno malo: `asteroid` con
  una única puntuación de 590 (real), y `kof99`/`kof2000` con su escalera
  100/90/80/70/60. El tope de posiciones basta para tirar la basura.
- **Estaba afirmando de más.** Marcaba como `confirmado` todo lo que viniera de
  hi2txt. Que acierte los 12 de mi muestra da confianza, pero no es lo mismo
  que haberlo mirado: `kof99` da 100/90/80 donde `kof97` da 100000/80000, y una
  de las dos lecturas está mal. Ahora `confirmado` sólo lo llevan los 16 vistos
  en pantalla.

### Los NeoGeo, resuelto a medias jugando

Su `saveram` arranca con la tabla vacía, así que se jugó automáticamente
(moneda, START y aporrear botones) para que la escribieran. El resultado es
desigual y no se puede suponer por familia:

| juego | qué pasó |
|---|---|
| `samsho` | cambiaron 31 bytes, ninguno en la zona de la tabla: **no guarda puntuaciones** |
| `doubledr` | apareció la tabla, con iniciales ASCII |
| `strhoop` | también escribió en esa zona |

`doubledr` quedó descifrado a partir de ahí: entradas de 16 bytes desde
`0x325`, BCD de 3 y tres letras, con `swap=2`. Sale
**10000 TAC, 9000 KSI, 8000 MAR, 7000 SZU, 6000 OHS**.

**Y al limpiarlas apareció el dato bueno.** Eloy pidió borrar esos récords por
ser inventados, y al borrar el `saveram` y arrancar limpio **Double Dragon
reescribió exactamente la misma tabla**: `10000 TAC, 9000 KSI, 8000 MAR, 7000
SZU, 6000 OHS` no eran mías, son **su tabla de fábrica**, que el juego escribe
en el primer arranque. Mi partida sólo había tocado 49 bytes, casi todos
contadores.

O sea que la receta queda **verificada contra el estado de fábrica**, que es
mejor prueba que la que buscaba. Y la conclusión sobre los NeoGeo se afina:

> No es que la tabla no exista hasta que alguien juega. Es que **unos juegos
> traen tabla de fábrica y la escriben al arrancar, y otros no guardan
> puntuaciones en absoluto**. `doubledr` es de los primeros; `samsho`, de los
> segundos.

Los ficheros de la prueba quedaron en `~/nvram_respaldo/*.saveram.tras_jugar`.

### `buscar_tabla.py`: encontrar la tabla por las INICIALES

Los juegos que nadie ha descrito se resisten a todo lo anterior, y buscar
«números que bajan» en un binario de kilobytes da falsos positivos por todas
partes — ya pasó con la NVRAM. Lo que sí funciona es **buscar grupos de letras
a intervalos regulares**: una tabla de records es de las poquísimas cosas que
tienen esa forma. Localizada la rejilla de nombres, la puntuación se busca sólo
dentro de esa misma entrada, que son un puñado de bytes, y ahí sí se puede
probar todo.

Dos correctivos que hicieron falta:

- **El nombre del juego también parece una rejilla.** ` DOUBLE DRAGON ` leído
  de tres en tres pasa el filtro. Se descarta exigiendo **hueco** entre inicial
  e inicial: en una tabla, entre un nombre y el siguiente hay ceros o la
  puntuación, no más letras.
- No rendirse con la primera rejilla que aparezca: se puntúan todas y gana la
  mejor.

Con eso salieron tres juegos que estaban atascados:

| juego | qué se encontró |
|---|---|
| `doubledr` | 5×16 desde `0x323`, `TAC KSI MAR SZU OHS` |
| `tmnt` | 10 puntuaciones BCD al principio y los nombres en un bloque a `0xc8` |
| `tekken` | 15×12 desde `0xc0`, iniciales de Namco (`AGR KAZ TEN ONO`) |

**`tmnt` confirmado en pantalla**, y por poco no la lío: su tabla da 312, 257,
206… y estuve a punto de ponerle un `×1000` porque parecía poco para un TMNT.
Su modo de atracción muestra `BEST 10 PLAYERS / 1ST HID 312 PTS`, o sea que el
número crudo era el bueno. Es el mismo error que ya cometí con `dkong`, evitado
por mirar la pantalla en vez de razonar.

**`tekken` no son puntuaciones sino tiempos**: los valores SUBEN de 3600 en
3600, que es un minuto a 60 fps. Es su tabla de récords de tiempo. Se exporta
igual, pero conviene saberlo.

### Qué NeoGeo hay que jugar y cuáles no

Pregunta de Eloy el 2026-09-05. La respuesta no es «todos», y averiguarlo salió
barato: arrancar cada juego limpio, jugar automáticamente y comparar la zona de
la tabla. Tres resultados distintos:

| juego | zona de la tabla al arrancar | qué cambió al jugar | conclusión |
|---|---|---|---|
| `samsho4` | **1008 bytes, con iniciales** | nada | ya trae tabla: **descifrar, no jugar** |
| `samsho5` | **943 bytes, con iniciales** | nada | igual |
| `samsho3` | vacía | **39 bytes** | **hay que jugarlo** |
| `fatfury1`, `strhoop` | vacía | 2 bytes | dudoso |
| `samsho2` | vacía | nada | probablemente no guarda |

`samsho4` y `samsho5` quedaron descifrados sin tocar el mando: entradas de 8
bytes desde `0x422`, tres letras ASCII y un valor BCD de 4. Y el número de
entradas delata qué son: **13 en samsho4 y 28 en samsho5, que es el número de
personajes de cada juego**. O sea que no es una tabla de diez mejores sino un
récord **por personaje**.

**Aviso sobre el método:** mi guion juega aporreando botones al azar, así que en
un juego de lucha no puntúa casi nada. Que la zona no cambie **no demuestra** que
el juego no guarde puntuaciones; sólo que mi partida no dio para batir la marca.
La prueba es concluyente en un sentido (si cambia, guarda) y no en el otro.

### Jugar una partida y decir el número: la mejor pista de todas

Eloy jugó a mano y dio los valores: `samsho3` 5200 con iniciales ABC, y
`fatfury1` 1600 sin poder registrar iniciales. **Con un número conocido, la
tabla se localiza buscándolo**, y eso es mucho más rápido que cualquier
heurística.

**`fatfury1` quedó resuelto y confirmado.** Buscando 1600 no aparecía, pero al
mirar la zona salió una escalera limpia de entradas de 8 bytes desde `0x32c`:

```
00 10 00 00 | 0f 0e 0d 00     16 -> 1600, "PON"
00 08 00 00 | 13 12 14 00      8 ->  800, "TSU"
00 06 00 00 | 03 04 11 00      6 ->  600, "DER"
```

Dos cosas que no se habrían adivinado:

- **la puntuación va dividida por 100** — se guarda 16 y el juego enseña 1600,
  que es justo lo que Eloy vio;
- **las iniciales son ÍNDICES de letra** (`0x00` = 'A'), no ASCII. Buscar texto
  imprimible ahí no encuentra nada.

**`samsho3` cerrado a medias, y con una lección.** Con la segunda partida
(~45000, iniciales ACD) quedó claro qué se mueve: `0x329` pasó de `005200` a
`046900` —los «~45000» de Eloy son 46900— y `0x33d` de `ABC` a `ACD`. Los dos
sitios cambiaron **a la vez, las dos veces**, así que son la misma entrada.

Lo que **no** se resolvió es la tabla completa: hay otro nombre (`LOM`) y otro
número (47400) en esa zona que no encajan en ninguna rejilla regular con los
anteriores. Y `samsho3` **no enseña su ranking en el modo de atracción**
—sólo logo, demos y «INSERT COIN»—, así que no hay pantalla contra la que
comprobarlo. Se exporta sólo la entrada segura.

**Y una advertencia que salió de meter la pata:** al capturar su atracción
buscando el ranking, **la demo jugó sola, marcó 50400 y sobreescribió los 46900
de Eloy**. El byte pasó a `050400` con el nombre intacto, lo cual confirma la
receta con un tercer dato — pero borró una marca real. **Dejar un NeoGeo en
atracción puede pisar un récord.**

### La técnica que faltaba: saber QUÉ número buscar

Lo que desatascó a Eloy con `samsho3` —jugar y decir el número— se puede
automatizar, porque hi2txt trae **dos** bases y yo sólo estaba usando una:

| carpeta | qué tiene |
|---|---|
| `src/main/db` | la **estructura**: cómo se lee la tabla (3102 juegos) |
| `src/main/db_defaults` | la **tabla de fábrica ya descifrada** (2697 juegos) |

Con la segunda se le da la vuelta al problema: en vez de adivinar el formato,
**se sabe qué valores tiene que haber y se buscan en el binario**. Ahí la
estructura aparece sola.

Así cayó `xevious`, que llevaba semanas resistiéndose. Su `db_defaults` dice
`40000 M.Nakamura / 35000 Eirry Mou. / 30000 Evezoo End`, y buscando 4000 en
BCD sale a la primera: entradas de 16 bytes, BCD de 3 con `×10`, y el nombre en
10 caracteres indexados. El alfabeto se deduce del propio nombre: `M`=0x16 y
`a`=0x36, o sea mayúsculas en 0x0a, espacio en 0x24 y **minúsculas** en 0x36.

`tekken2` cayó por parentesco con `tekken`: misma placa, entradas de 8 bytes
con el nombre del personaje en ASCII. Son 33 récords de tiempo, uno por
personaje.

**Y una limitación del pre-chequeo que había puesto**: exigía que el bloque
tuviera sitio para TODAS las entradas de la receta, y el de `xevious` son 77
bytes contra los 80 que piden sus 5×16. Ahora basta con que quepa una: se
descifra lo que haya.

### Las otras fuentes que pasó Eloy

- **`hiscore.dat` oficial en GitHub**: comprobado, el de la cabina es
  **idéntico** (mismo md5, 5.855 juegos). Ya estaba al día.
- **MAMEworld high scores**: **no responde** (HTTP 000). Es el origen histórico
  del `hiscore.dat` no oficial, ya integrado en MAME.
- **Plugin de LaunchBox/BigBox**: es para Windows y no aplica aquí, pero fue
  útil como pista — por dentro usa hi2txt, que es lo que confirmó cuál era la
  buena.

### Cubrir muchos juegos: el `.hi` NO aparece solo

Pedido por Eloy el 2026-09-05: *«que queden guardados los highscore de la mayor
cantidad posible de juegos»*. El primer intento —arrancar los 94 juegos para que
el plugin escribiera su `.hi`— **no podía funcionar**, y el motivo está en el
código del plugin (`init.lua`):

```lua
if checksum ~= current_checksum and checksum ~= default_checksum then
    write_scores( positions );
```

> **El plugin sólo escribe cuando la tabla CAMBIA respecto a como estaba al
> arrancar.** Un juego que nadie ha jugado no deja ningún fichero.

Por eso sólo había 6 `.hi`: son los 6 que alguien jugó. Sin datos no se puede ni
deducir el formato ni apuntar la tabla de fábrica.

**La salida: leer la tabla nosotros.** `volcar.lua` lee de la RAM el bloque que
declara `hiscore.dat` y lo imprime; `./puntajes.py --fabrica` lo lanza para cada
juego. Verificado en Donkey Kong: el volcado directo coincide **byte a byte**
con su `.hi`.

De ahí salieron **59 tablas de fábrica**, que sirven para las dos cosas a la
vez: deducir formatos y alimentar el filtro de nombres ficticios de todos ellos.

### El detector automático de formatos

Escribir una receta a mano no escala. Pero una tabla de puntuaciones tiene una
propiedad que la delata: **está ordenada de mayor a menor**. `--detectar` prueba
anchos de entrada, desplazamientos y formatos, y propone las que encajan.

Lo que de verdad lo hizo acertar fueron dos criterios tontos y muy selectivos:

- en formato `digitos` **ningún byte puede pasar de 9**;
- en BCD **ningún nibble puede ser A-F**.

Más tres correctivos sacados de ver en qué se equivocaba: casi toda recreativa
puntúa de 10 en 10; leer 4 bytes como entero da números de siete cifras (falso);
y la primera posición de una tabla no baja de 1000 (si no, confunde la tabla con
el campo de la ronda alcanzada, que también va ordenado).

Acierta **3 de 6** a la primera, y la correcta suele estar entre las 2-3
primeras. Por eso `--proponer` escribe las líneas con **`confirmado=no`** y
nunca las da por buenas: cada fila del JSON lleva `"confirmado": true/false`.

> **Sólo cuenta como confirmada la receta comparada con lo que el juego enseña
> en pantalla.** A `dkong` le sobraba un ×10 y sólo se vio mirando su modo de
> atracción.

**Confirmar en pantalla es rápido: el marcador basta.** No hace falta esperar a
que salga la tabla — casi todos los juegos enseñan el récord en el HUD
permanentemente (`HIGH 25800` en Contra, `HI 57300` en Gradius, `TOP 008900` en
Zaxxon). Con una captura por juego se valida la magnitud, que es donde aparece
el error del multiplicador.

Y **cazó tres recetas mal** que parecían perfectas:

| juego | pantalla | lo que daba | arreglo |
|---|---|---|---|
| `arkanoid` | `HIGH SCORE 50000` | 5000 | faltaba `multiplica=10` |
| `commando` | `TOP SCORE 50000` | 5000 | faltaba `multiplica=10` |
| `mappy` | `HIGH SCORE 20000` | 200000 | leía un dígito de más |

Las tres tenían forma de escalera de números redondos y habrían pasado
cualquier criba automática.

**Y las propuestas se cribaron antes:** de las 28 que dio el detector se
quitaron 12 por no tener forma de tabla — valores no redondos, ceros en medio o
números imposibles (`goldnaxe` daba 33024026055).

**Y hay juegos que guardan la tabla al reves.** Kung-Fu Master la tiene de
MENOR a MAYOR: sus 20 posiciones acaban en el record (`00 48 52` -> 48520, que
es lo que marca `TOP-048520`). El detector solo buscaba descendente y por eso
proponia una lectura equivocada. Ahora acepta los dos sentidos y `orden=asc` le
da la vuelta al descifrar, para que «puesto 1» sea siempre el mejor.

**Cobertura hoy:** 94 juegos instalados, **59** con tabla localizable, **21**
con receta, de ellas **16 confirmadas en pantalla**.

Las 5 que faltan (`ffight`, `simpsons2p`, `ssf2t`, `ssriders`, `timeplt`) no
enseñaron su marcador en ninguno de los cinco instantes capturados: son juegos
cuyo modo de atracción es casi todo cinemática o selección de personaje.

**La NVRAM sigue sin resolverse, y se intentó.** `detectar_en_ventana()` busca
la tabla deslizando una ventana por el fichero, porque ahí no ocupa el bloque
entero. Funciona rápido (1-2 s) pero **los resultados no son de fiar**: en un
binario de kilobytes «va de mayor a menor» es señal demasiado débil y salen
falsos positivos por todas partes — `berzerk` daba `555555` seis veces,
`polepos` una sucesión con diferencias exactamente iguales, `defender` valores
pegados a `0xF2xx` (la codificación por nibbles de Williams mal leída). **No se
metió ninguna en `puntajes.dat`**: queda como pista para `--detectar`, nada más.

**La NVRAM es el hueco que queda.** Los juegos que no están en `hiscore.dat`
(`qbert`, `tapper`, los Williams, los NeoGeo…) guardan las puntuaciones ahí,
mezcladas con todo, y no hay ningún fichero que diga dónde ni cómo. Joust, por
ejemplo, guarda nibbles con prefijo `0xf0`. Es trabajo por placa.

### Dos fallos míos en el parser de `hiscore.dat`

Los dos daban tamaños de bloque absurdos (dkong con 32 KB en vez de 179 bytes) y
ninguno saltaba como error:

- **Saltarme las líneas en blanco** hacía que los nombres se acumularan y cada
  juego heredara los bloques de todos los anteriores.
- **Los nombres con comentario detrás** (`pacmini:  ; missing`) no acababan en
  `:`, así que el parser los tomaba por línea desconocida y reiniciaba el grupo
  — dejando a `pacman` sin bloques.

Arreglados, el fichero pasa de 5753 a **5862** juegos reconocidos.

### Los nombres ficticios

Un juego recién instalado trae una tabla puesta por la ROM — las iniciales de
Q*bert, o las `I.F / MTJ / NSO` de Bubble Bobble. Ésas no son de nadie.

`./puntajes.py --capturar` apunta la tabla actual como la de fábrica en
`puntajes_defecto.json`, y a partir de ahí cada entrada del JSON lleva
`"defecto": true/false` (o `null` si nadie capturó la base). **Hay que
capturarla antes de que nadie juegue.**

Ya mordió al probarlo: capturé la base con Pac-Man marcando 48800, así que dio
por «de fábrica» una puntuación de verdad. La de fábrica de Pac-Man es **0**, y
hubo que corregirla a mano.

### La comprobación de Lua 5.5 en `pruebas/correr.sh`

La cabina tiene **dos binarios de MAME con Lua distinta**: el nuestro lleva 5.4
y el de la distro 5.5. En 5.5 la variable de control de un `for` es **const**,
así que asignarle valor es un error de **compilación** y el fichero entero deja
de cargar:

```lua
for linea in f:lines() do
    linea = linea:gsub(...)     -- revienta con 5.5, pasa con 5.4
```

Le pasó a `ajustes.lua`, y es un fallo **mudo**: probando con 5.4 no se ve.

`correr.sh` pasa ahora `luac -p` sobre todos los `.lua` de `creditos/`, que
cuesta milisegundos. **En la cabina el `lua` del sistema ES 5.5.1**, así que la
comprobación es real allí; donde el `luac` disponible no sea de 5.5 se salta
avisando, en vez de romper la tanda. Los 9 ficheros compilan.

Ojo: eso también significa que **probar contra nuestro binario no detecta este
fallo**, porque 5.4 lo permite.

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
- `daemon.py` y `arduino/sandbox.py` no tenian **shebang**, asi que `./daemon.py`
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
