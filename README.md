# Creditos de recreativa para GroovyMAME + Attract-Mode Plus

Un boton mete monedas en el frontend, se ven en pantalla, y al elegir juego
entran solas en GroovyMAME.

## Las piezas

| Fichero | Lenguaje | Que hace |
|---|---|---|
| `Creditos.nut` (en `attractplus/config/plugins/`) | Squirrel | cuenta creditos en el frontend, los pinta y los deja en el buzon al lanzar |
| `creditos.lua` | Lua | dentro de MAME: inserta los creditos y vigila el boton de moneda |
| `monedero.lua` | Lua | la cuenta compartida entre las dos partes |
| `aviso.lua` | Lua | el cuadro que avisa de creditos dentro de la maquina |
| `memoria.lua` + `creditos.dat` | Lua | lee los creditos de la RAM del juego |
| `buscar_creditos.lua` + `.sh` | Lua + bash | encuentra esa direccion, juego a juego |
| `importar_cheats.py` | Python | saca direcciones de la coleccion de cheats de MAME |
| `tarifa.lua` | Lua | analiza el DIP de tarifa del juego. Lo usan los dos scripts Lua |
| `poner_1c1c.lua` + `poner_1c1c.sh` | Lua + bash | pasada unica que deja los juegos en 1 moneda = 1 credito |
| `groovymame.cfg` | — | emulador de ejemplo para AM+ |

El monedero es un fichero de texto, por defecto `$HOME/.attract/creditos.txt`,
que **leen y escriben las dos partes**:

```
saldo 4
inserta 1
```

- `inserta` son los creditos que MAME mete en la partida al arrancar. MAME lo
  pone a 0 en cuanto lo lee, para que un segundo arranque no regale creditos.
- `saldo` es lo que le queda al jugador. Mientras se juega, `creditos.lua` lo
  mantiene al dia descontando lo que el juego se lleva de verdad (las partidas
  jugadas), asi que al salir el frontend ensena lo que realmente queda.

Se escribe siempre a un temporal y se renombra, que en POSIX es atomico: matar
MAME a media escritura no puede dejar la cuenta a medias. Y si el fichero no se
puede leer al volver de la partida, el frontend **deja el contador como
estaba**: perder creditos por un fichero ilegible seria lo peor que podria pasar.

El monedero lleva CREDITOS, no monedas. Cuantas monedas hacen falta depende del
DIP de tarifa de cada juego, y eso solo lo sabe `creditos.lua`.

## Dos formas de usarlo

**Manual** (la de Eloy, y la que funciona igual en todos los juegos). El
frontend es solo un menu: eliges juego, entra sin creditos y las monedas las
metes tu con el boton, como en una recreativa. No hay monedero ni marcador, y no
depende de conocer la direccion de creditos de cada placa.

    Plugin Creditos: desactivado (Configure > Plug-ins > Creditos > Enabled: no)

`creditos.lua` se deja igualmente en los argumentos del emulador, porque sigue
haciendo dos cosas utiles: mantener la tarifa en 1 moneda = 1 credito y avisar
al salir si dejas creditos dentro de la maquina.

**Con monedero.** El frontend cuenta tus creditos, no te deja entrar sin uno y
se los pasa al juego. Es lo que documenta el resto de este fichero. Se activa
encendiendo el plugin.

## Instalacion

1. Copiar el plugin y activarlo:

       cp /home/eloy/attractplus/config/plugins/Creditos.nut $HOME/.attract/plugins/

   En AM+: *Configure > Plug-ins > Creditos > Enabled*. Ahi mismo se elige el
   boton de moneda y el resto de ajustes.

2. Declarar el emulador:

       cp groovymame.cfg $HOME/.attract/emulators/

3. Pasada unica de tarifas (recomendado, ver mas abajo):

       ./poner_1c1c.sh

4. Pasada unica para saber donde guarda cada juego sus creditos (opcional,
   mejora la cuenta de lo que queda dentro de la maquina):

       ./buscar_creditos.sh
       ./importar_cheats.py CheatCollection/cheat.7z   # miles mas, sin comprobar

## La tarifa: monedas no son creditos

El DIP de tarifa del juego decide cuantos creditos da cada moneda. Pac-Man
venia en `1 Coin/2 Credits`, asi que 3 monedas daban `CREDIT 6`.

`creditos.lua` lo resuelve solo (`GA_TARIFA`, por defecto `1c1c`):

- Lee el DIP y **compensa** las monedas de esta partida.
- Y deja el DIP en 1 moneda/1 credito para los proximos arranques.

Hay un detalle medido con Pac-Man: la placa lee la tarifa **al arrancar**, asi
que el cambio de DIP no afecta a la partida en curso. Traducido:

| | tarifa vigente | monedas | resultado |
|---|---|---|---|
| primer arranque | 1C/2C | 2 | `CREDIT 4` para 3 pedidos |
| siguientes | 1C/1C | 3 | `CREDIT 3` exacto |

Por eso conviene pasar `poner_1c1c.sh` una vez: deja todos los juegos en
1 moneda/1 credito de entrada y desde el primer arranque el numero es exacto.
Es idempotente y respeta los juegos puestos en *Free Play* a proposito.

Cuidado: eso reescribe los `.cfg` de MAME de cada juego, que es justo lo que
hace la propia interfaz de MAME al cambiar un DIP a mano.

## Variables de entorno de creditos.lua

| Variable | Por defecto | Que hace |
|---|---|---|
| `GA_CREDITOS` | — | creditos a insertar; manda sobre el fichero |
| `GA_ARCHIVO` | `$HOME/.attract/creditos.txt` | fichero del monedero |
| `GA_TARIFA` | `1c1c` | `1c1c`, `auto` (solo compensa) u `off` (ignora los DIP) |
| `GA_PULSO` | 8 | frames con la moneda pulsada |
| `GA_HUECO` | 8 | frames entre monedas |
| `GA_ESPERA` | 0 | frames extra de espera |
| `GA_MONEDA` | `COIN1` | token de entrada |
| `GA_VIGILAR` | 1 | `0` para no llevar la cuenta del monedero durante la partida |
| `GA_AVISO` | 1 | `0` para no avisar al salir con creditos dentro |
| `GA_AVISO_ESPERA` | 300 | frames que el cuadro aguanta antes de rendirse |
| `GA_MENSAJE` | 150 | frames que dura el mensaje al meter una moneda |
| `GA_SINCRONIZAR` | 1 | `0` para no escribir los creditos en la RAM del juego |
| `GA_TOPE` | 9 | maximo que se escribe en el contador |
| `GA_TABLA` | `creditos.dat` de al lado | fichero de direcciones |
| `GA_VERBOSO` | — | `1` para diagnostico |

## Probar sin frontend

    echo 3 > $HOME/.attract/creditos.txt
    cd /home/eloy/groovymame_src
    GA_VERBOSO=1 ./mame pacman -rompath /usr/share/games/mame/roms \
      -autoboot_script /home/eloy/groovyarcade-creditos/creditos.lua \
      -autoboot_delay 6

Sin pantalla, envolver en `xvfb-run -a` y anadir `-noswitchres`: GroovyMAME
revienta con SIGFPE bajo Xvfb porque Switchres calcula modelines contra un
display virtual.

## Los creditos no se pierden

La regla es una: **el monedero paga por lo que se JUEGA, no por lo que se mete.**

- Al lanzar un juego entra **un credito** (ajuste *Que se inserta al lanzar*),
  no el monedero entero.
- Meter monedas **dentro** de la partida no cuesta nada: mueve creditos del
  monedero a la maquina. Si no los gastas, siguen siendo tuyos.
- Lo que descuenta de verdad es pulsar **START**, que es cuando el juego se
  lleva el credito. Una partida de 1 jugador vale 1, la de 2 jugadores vale 2.

Recorrido del jugador despistado, que es el caso que importa: entra a Pac-Man
con 10 creditos y se pone a pulsar la moneda pensando que acumula para otros
juegos.

| Momento | El juego | El monedero |
|---|---|---|
| lanza la partida | recibe 1 | 10 |
| pulsa la moneda cuatro veces | recibe 4 mas | 10 |
| juega una partida | — | **9** |
| sale al frontend | — | **9** |

Antes ese jugador salia con 5 creditos menos. Ahora paga solo la partida que
jugo. Y para que se entere en el momento, cada moneda que mete dentro del juego
saca un mensaje corto en pantalla:

```
CREDITO PARA ESTE JUEGO. MONEDERO: 9
```

El frontend descuenta el credito del lanzamiento nada mas lanzar, y es
`creditos.lua` quien lo devuelve si no se ha gastado. Es asi a proposito: si el
script Lua no llegara a ejecutarse, la cuenta se queda cobrada, que es el error
seguro. Nunca al reves.

Lo unico que sigue sin poder cobrarse: si el monedero llega a 0 y sigues
pulsando la moneda, el juego te da creditos igual, porque esa entrada la lee
MAME directamente. Se podria bloquear, pero MAME guarda los cambios de mapeo en
su `.cfg` y el riesgo es dejar el boton muerto de forma permanente. Para una
cabina de casa no merece la pena.

## Leer los creditos de la RAM del juego

MAME no tiene un concepto de "creditos": cada placa los guarda en una direccion
distinta de su RAM. Pero se puede averiguar cual, juego a juego, igual que el
plugin `hiscore` de MAME sabe donde esta el record de cada uno.

`buscar_creditos.sh` lo hace solo, con el metodo de un buscador de trucos:

```
foto de la RAM -> moneda (sube d) -> moneda (sube d) -> moneda (sube d)
               -> START (baja)    -> el que quede es el contador
```

Y afina el resultado con cuatro reglas, todas aprendidas a base de fallar:

- **Tres monedas, no dos.** Con dos aparecian falsos positivos y la respuesta
  cambiaba de una pasada a otra.
- **Un solo START.** El segundo no sirve: con la partida ya en marcha el juego
  lo ignora y no gasta credito.
- **La placa arranca sin creditos**, asi que el contador vale 0 en la primera
  foto. Lo que empieza en otro numero es otra cosa.
- **Y la prueba que de verdad decide:** se escribe el mismo numero en todos los
  candidatos y se pulsa START. Solo baja el que el juego mira. Tiene que bajar
  exactamente 1 o 2 (lo que cuesta una partida); "que baje" a secas no vale,
  porque una placa que aun esta inicializando su RAM lo pone a cero y parece que
  ha respondido.

Sin esa ultima prueba, Q*bert quedaba apuntado en un byte que el juego ni lee:
la pantalla marcaba `CREDITS 0` mientras nosotros creiamos haber sincronizado 4.

**Juegos con varias copias del contador.** Si responden varios candidatos, el
juego mantiene copias y puede pintar el marcador desde cualquiera, asi que se
apuntan todas y se escribe en todas:

    qbert @:maincpu,program,b60+bbd+1100

    ./buscar_creditos.sh              # todos los juegos -> creditos.dat
    ./buscar_creditos.sh pacman       # solo uno

El resultado, con el mismo espiritu que `hiscore.dat`:

    pacman @:maincpu,program,4e6e

Con esa linea, `creditos.lua` sabe en todo momento cuantos creditos tiene la
maquina: cuantos entran y cuantos se lleva el juego, exacto y sin estimar. Los
juegos que no esten en la tabla siguen funcionando con la estimacion por
pulsaciones de START.

**No sale en todos.** De las 24 roms de prueba salen 9. Se barre la RAM de
**todos** los procesadores de la maquina, no solo la principal, pero los Namco
(digdug, mappy, nrallyx) siguen sin dar la cara: su contador no vive en la RAM
de ninguna CPU sino en el chip de entrada/salida. Los que no salen siguen
funcionando con la estimacion por pulsaciones de START.

## Sincronizar en vez de simular monedas

Si el juego esta en `creditos.dat`, `creditos.lua` **escribe** el monedero
directamente en el contador del juego: los dos numeros pasan a ser el mismo.

```
[creditos] sincronizando 7 creditos por escritura, sin insertar monedas
[creditos] creditos sincronizados: el juego marca 7
```

Es la otra mitad del metodo del plugin hiscore (el lee su fichero y lo vuelca en
la RAM al arrancar), y de paso se quitan de en medio tres fuentes de error: los
pulsos de moneda que se pierden, la espera de arranque y la tarifa del DIP.

Dos cuidados, y los dos importan:

- **Se comprueba que el valor se quede puesto.** Si la placa todavia estaba
  inicializando su RAM, su propio codigo lo machaca; por eso se reintenta unas
  veces y, si no hay manera, **se vuelve a las monedas de siempre**.
- **Hay un tope** (`GA_TOPE`, por defecto 9): escribir 99 en un juego cuyo
  contador solo llega a 9 puede confundirlo.

Con `GA_SINCRONIZAR=0` se desactiva y se insertan monedas como antes.

## Aprovechar la coleccion de cheats de MAME

La coleccion de Pugsy trae, para miles de juegos, un cheat *Infinite Credits*
que apunta justo al contador:

    <cheat desc="Infinite Credits">
      <script state="run"><action>maincpu.pb@4E6E=09</action>

`importar_cheats.py` saca esas direcciones y las anade a `creditos.dat`. Traga
carpetas, `.zip` y `.7z`:

    ./importar_cheats.py CheatCollection/cheat.7z

Con la coleccion de MAME 0.279: **181.686 ficheros mirados, 4.958 juegos
anadidos**. Y sirve de comprobacion cruzada: de los que yo habia medido
ejecutando el juego, los cinco que la coleccion tambien trae coinciden exactos
(`pacman 4E6E`, `dkong 6001`, `asteroid 0070`, `popeye 8FDD`, `elevator 80A2`).

**Lo comprobado manda y lo importado se gana la confianza.** Las lineas que
encontro `buscar_creditos.sh` no se pisan. Las importadas se marcan `(cheat)` y
se tratan con desconfianza, porque hay cheats de creditos infinitos que parchean
el codigo en vez de escribir el contador:

- No se escribe en ellas nunca (podria corromper la partida).
- Se prueban por comportamiento: se insertan las monedas de siempre y se mira si
  ese byte sube. Si sube, se pasa a leerlo; si no, se descarta y se estima.

```
direccion importada (sin comprobar): la pruebo con las monedas
la direccion importada e011 subio de 0 a 3 con las monedas: me fio
```

Ojo con la tentacion de comprobarlo mirando si el contador vale 0 al arrancar:
hay placas con NVRAM que **guardan los creditos** de la sesion anterior. Tapper
lo hace, y por eso se comprueba por comportamiento y no por valor.

## El cuadro de aviso al salir

Los creditos que metiste dentro de una maquina solo valen ahi: al salir se
quedan. Ya no arruinan a nadie (el monedero no los ha cobrado), pero conviene
decirlo. Si sales dejando creditos **que metiste tu**, la primera pulsacion de
la tecla de salir no sale: pinta un cuadro y espera.

```
                    OJO
    DEJAS 2 CREDITOS DENTRO DE ESTA MAQUINA
   SOLO VALEN AQUI. TU MONEDERO NO SE TOCA: 7

           SALIR otra vez para salir
           START para seguir jugando
```

- **Salir otra vez** sale de verdad.
- **START** quita el cuadro y sigues jugando.
- Si no haces nada en 5 segundos, el cuadro se va **y no sales**.
- Si con el cuadro puesto gastas el credito, se quita solo.

**Entrar a mirar un juego y salir no molesta.** El cuadro solo aparece si el
jugador metio monedas durante la partida; el credito del lanzamiento no cuenta.

El numero es exacto en los juegos que estan en `creditos.dat`. En los demas se
estima mirando el boton de start (1 jugador = 1 credito, 2 jugadores = 2), y por
eso el texto dice "dejas" sobre una cuenta que puede quedarse corta en un juego
que cobre dos creditos por partida. Con `GA_AVISO=0` se desactiva.

Como se frena la salida, que es la parte delicada: **no se toca ningun mapeo de
controles**. Se llama a `uiinput:reset()` en el momento justo del frame, que deja
los eventos de interfaz en `SEQ_PRESSED_RESET`; el `check_ui_inputs()` de MAME,
que corre despues, no los vuelve a levantar mientras la tecla siga pulsada. En
cuanto el script deja de pedirlo, la tecla vuelve a funcionar como siempre.

## Limitaciones conocidas

- Los textos de los DIP los traduce MAME, y el analizador espera **ingles**
  (`1 Coin/2 Credits`, `A 1/1 B 1/1 C 1/1`). Con otro idioma usa `GA_TARIFA=off`.
- Juegos sin DIP de tarifa (Q*bert, Tapper, Simpsons: hardware que no lo lleva)
  van a una moneda por credito, que es lo correcto ahi.
- Tarifas con premio (`1 Coin/1 Credit, 2/3`) pueden dar algun credito de mas;
  `poner_1c1c.sh` elige siempre la tarifa sin premio.
- El numero del cuadro de aviso es una estimacion (ver arriba).
- El cuadro se pinta en la capa de interfaz de MAME. Las capturas que hace MAME
  con `snapshot()` NO la incluyen: para verlo hay que capturar la ventana.
