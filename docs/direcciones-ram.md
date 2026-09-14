# Cómo se localizan las direcciones de RAM: créditos y puntajes

Este es el documento que explica, con el máximo detalle, **cómo se averigua en qué
posición de memoria guarda cada juego sus créditos y su tabla de puntuaciones**, y
por qué el método es el que es. Es la pieza central del proyecto y la que cuesta
más entender, así que va despacio y con ejemplos.

> Si sólo lees una idea, que sea ésta: **una dirección equivocada es peor que
> ninguna.** Todo el diseño gira en torno a no apuntar nunca un dato en el que no
> confiamos, aunque eso signifique quedarnos sin él. Cuando hay duda, se estima o
> se deja en blanco; nunca se inventa.

---

## 0. El problema de fondo

MAME emula la placa entera, pero **no tiene ningún concepto de «crédito» ni de
«puntuación»**. Esos números viven dentro de la RAM del juego, en una dirección
que **elige cada placa** y que cambia de un juego a otro (y a veces entre
revisiones del mismo juego). No hay una API que diga «dame los créditos»: hay que
localizar el byte concreto, una vez por juego, y apuntarlo en una tabla.

Son **dos problemas distintos**, y se resuelven con herramientas distintas:

| | Créditos | Puntuaciones |
|---|---|---|
| Qué es | **un byte** (un contador que sube al meter moneda y baja al pulsar START) | **una tabla ordenada** (varias entradas: puntuación + iniciales) |
| Cómo se localiza | **en vivo**, sondeando la RAM mientras el juego corre | por la base de datos `hiscore.dat` (dónde) + la estructura (cómo) |
| Herramienta | `buscar_creditos.lua` + `buscar_creditos.sh` | `puntajes.py` + `hi2txt.py` + `buscar_tabla.py` |
| Tabla resultado | `creditos.dat` | `puntajes.dat` (+ recetas de hi2txt-xml) |
| Se apunta como | `pacman @:maincpu,program,4e6e` | `1943 entradas=6 bytes=16 puntos=0,8,digitos …` |

La idea de las dos vino del **plugin `hiscore` de MAME**: si no hay un concepto
general, se localiza el dato una vez por juego y se anota en un fichero de texto,
igual que `hiscore.dat` hace con las tablas de récords.

---

# PARTE A — La dirección del contador de CRÉDITOS

Fichero: `creditos/buscar_creditos.lua` (lo lanza `creditos/buscar_creditos.sh`).

La técnica es la de un **buscador de trucos** (tipo Cheat Engine): no sabemos
dónde está el contador, pero sabemos **cómo tiene que comportarse** —sube al meter
moneda, baja al pulsar START— así que provocamos ese comportamiento y nos quedamos
con el único byte de toda la RAM que lo sigue exactamente.

## A.1. De dónde se lee: TODA la RAM, de TODAS las CPU

Antes de sondear nada hay que saber qué bytes mirar. El script recorre
`manager.machine.devices`, coge **cada procesador que tenga espacio de programa**
(no sólo `:maincpu`) y de su mapa de memoria (`sp.map.entries`) se queda con los
tramos cuyo manejador de lectura o escritura sea de tipo `'ram'`:

```lua
if (r == 'ram') or (w == 'ram') then ...   -- r/w = handlertype de la entrada
```

Y además recorre `manager.machine.memory.shares`. **Hacen falta las dos fuentes**,
y esto costó descubrirlo:

- La RAM de trabajo de **Pac-Man** no aparece como un *share*, sólo en el mapa.
- La de **Simpsons** no aparece como `'ram'` en el mapa (va detrás de un
  *delegate*, una función C++), pero sí como *share*.

Un *share* sólo sirve si sabemos **en qué dirección lo ve una CPU** (si no, no
podríamos escribirlo en `creditos.dat`). Por eso, al recorrer el mapa, se apunta la
dirección base de cada share (`base_de_share`), y luego cada share se traduce a la
dirección que ve la CPU. Al principio se apuntaba el desplazamiento *dentro* del
share, y eso metió direcciones falsas (a `popeye` le salía `15d` cuando su
contador está en `8fdd`).

Cada tramo de RAM se guarda como un «bloque» con dos funciones: `leer(i)` (lee el
byte en el desplazamiento `i`) y `dir(i)` (devuelve la dirección absoluta que verá
la CPU). Sólo se aceptan tramos de hasta 256 KB (`n <= 262144`), para no barrer
megas de VRAM inútil.

Barrer TODAS las CPU es lo que hace que el método valga para cualquier
arquitectura, y también para juegos donde la cuenta la lleva **un segundo chip** y
no la CPU principal.

## A.2. La secuencia: monedas y un START, comprobando cada paso

El corazón es una `instantanea()`: una foto de **todos** los bytes de RAM a la vez
(un diccionario `"bloque|offset" -> valor`). Comparando fotos antes y después de
cada pulsación se ve qué bytes reaccionaron.

El guion es exactamente éste (`GUION` en el código):

```
foto inicial
moneda  -> 'primera'   (apuntar candidatos: los que suben entre 1 y 4)
moneda  -> 'sube'      (quedarse con los que suben LO MISMO otra vez)
moneda  -> 'sube'      (y otra vez lo mismo)
(nada)  -> 'marcar'    (escribir un número distintivo en todos los candidatos)
START   -> 'responde'  (quedarse con el que BAJA 1 ó 2: prueba funcional)
```

Paso a paso:

1. **`'primera'`** — tras la primera moneda, cualquier byte que haya subido entre
   `1` y `MAX_DELTA` (4) es candidato, y **su subida queda fijada** como sus
   «créditos por moneda». Se guarda en `deltas[clave] = d`.

2. **`'sube'` (dos veces)** — con cada moneda siguiente sólo sobreviven los
   candidatos que suben **exactamente esa misma cantidad** `d`. Aquí se caen los
   falsos positivos: bytes que subieron por casualidad la primera vez pero no
   siguen el patrón.

   > **Por qué TRES monedas y no dos.** Con dos monedas quedaban falsos positivos
   > que se movían por azar, y **la respuesta cambiaba de una pasada a otra**
   > (`centiped`, `mwalk` daban direcciones distintas cada vez). La tercera moneda
   > mata casi todo lo espurio.

3. **`'marcar'`** — a cada candidato que queda se le **escribe** el mismo número
   distintivo (`ESCRIBO = 7`) en su dirección. La idea: el juego sólo hará caso al
   byte que él de verdad lee como contador.

4. **`'responde'`** (la prueba **funcional**, la que de verdad decide) — se pulsa
   **START** y sobreviven sólo los candidatos cuyo valor bajó a `6` ó `5`, es
   decir, que **bajaron 1 ó 2** desde el `7` que les escribimos. Pulsar START
   arranca una partida sólo si el juego cree que hay crédito; el byte que él mira
   es el que baja.

   > **Por qué UN solo START.** Un segundo START no serviría: con la partida ya en
   > marcha el juego lo ignora y no gasta crédito, así que descartaría hasta al
   > candidato bueno. Se probó y los seis juegos de prueba pasaron a
   > «sin candidatos».
   >
   > **Por qué «baje 1 ó 2» y no «que baje».** Una placa que está inicializando su
   > RAM pone bytes a cero y *parece* que responde. Exigir una bajada de
   > exactamente 1 ó 2 créditos distingue al contador de verdad del ruido.

Detalle de temporización: entre paso y paso se esperan `GA_BUSCA_ESPERA` (45)
frames, y cada pulsación se mantiene 8 frames y luego se suelta
(`set_value(0)`). Soltar es obligatorio: **`set_value` es un OR con el botón
físico** y dejar la moneda «pulsada para siempre» la placa lo lee como monedero
atascado y la ignora.

## A.3. Los filtros finales, y por qué

Cuando el guion termina, quedan cero o más «finalistas». Antes de aceptar nada:

- **Arranca sin créditos.** La placa empieza a cero, así que el contador valía `0`
  en la primera foto (`foto_inicial[k] == 0`). Un candidato que empezó en otro
  número es **otra cosa** (así se resolvió `elevator`, donde competían tres bytes:
  sólo uno partía de 0).

- **El mismo byte contado dos veces no es ambigüedad.** Un contador puede aparecer
  a la vez en el mapa y en un share; se deduplica por `cpu:dir`.

- **Varias copias con el mismo valor son espejos.** Algunos juegos mantienen el
  contador duplicado y pintan el marcador desde cualquiera de las copias. Se
  apuntan **todas**, unidas con `+` (`qbert @:maincpu,program,b60+bbd+1100`), y
  `creditos.lua` escribe en todas.

- **Demasiados candidatos, o en CPU distintas → se descarta.** Más de cuatro, o
  repartidos entre procesadores, huele a que algo se coló: se declara
  `estado=demasiados` y no se apunta nada.

- **Ninguno responde → nada.** `estado=ninguno-responde`. Mejor estimar que mentir.

El orden de preferencia pone al final los shares con «video»/«color» en el nombre
(menos fiables que la RAM de trabajo) y prefiere `:maincpu`.

## A.4. El caso que justificó la prueba funcional: Q*bert

Sin el paso `'responde'`, Q*bert quedaba apuntado en `b60`, **un byte que el juego
no lee**: la pantalla marcaba `CREDITS 0` mientras nuestro log decía «sincronizados
4». Se descubrió mirando las capturas, no los logs. La prueba funcional (escribir y
ver si START gasta) es la única que distingue el contador real de una copia muerta.

## A.5. El orquestador: `buscar_creditos.sh`

Lanza `buscar_creditos.lua` como `-autoboot_script` para cada juego de la lista,
bajo Xvfb, y recoge las líneas `CREDITOS juego=…`. Dos avisos **críticos**:

> **PELIGRO: reescribe `creditos.dat` ENTERO** con sólo lo que encuentra en esa
> pasada (su último bloque es un `> "$SALIDA"`). Lanzado a pelo se lleva por
> delante las ~4.900 direcciones importadas de la colección de cheats y las
> verificadas de los juegos que no estén en la lista. **Hay que darle `SALIDA=` a
> un temporal y fundir después.**

> Conviene darle también `CFG_DIR=` a una copia de los `.cfg`, o las monedas que
> mete la prueba acaban guardadas en los `.cfg` de los juegos.

Y una regla de medición: **las cifras se dan de la máquina que toca.** El portátil
tiene 106 sets y la cabina 104, y **no son un subconjunto** (hay juegos que sólo
arrancan en una). En la cabina el número real es 33 de 104.

## A.6. La otra fuente de direcciones: la colección de cheats (`importar_cheats.py`)

La colección de trucos de Pugsy para MAME trae, para miles de juegos, un cheat
*Infinite Credits* cuya acción escribe justo en el contador:

```xml
<cheat desc="Infinite Credits">
  <script state="run"><action>maincpu.pb@4E6E=09</action>
```

`importar_cheats.py` saca esa dirección (`4E6E`) y añadió **~4.958 juegos** a
`creditos.dat`. Comprobación cruzada de regalo: de los que se habían medido a mano,
los cinco que la colección también trae **coinciden exactos** (pacman 4E6E, dkong
6001, asteroid 0070, popeye 8FDD, elevator 80A2). Dos métodos independientes que
convergen.

**Pero las importadas se ganan la confianza, no se les da.** Hay cheats que
parchean el *código* en vez de escribir el contador, así que una dirección
importada puede ser cualquier cosa:

- Se marcan `(cheat)` en `creditos.dat` y **nunca se escribe en ellas** (escribir
  en el byte equivocado corrompe la partida).
- Se prueban **por comportamiento** en `creditos.lua`: se mira si el byte sube al
  meter una moneda de verdad. Si sube, se asciende a lectura exacta; si no, se
  descarta y se vuelve a estimar. (Trampa: comprobarlo mirando si vale 0 al
  arrancar **no vale**, porque hay placas con NVRAM que arrancan con créditos de
  la sesión anterior; la comprobación es por comportamiento, no por valor.)

## A.7. Al leer el contador: el BCD

Catorce de las placas con dirección conocida guardan el contador en **BCD**
(decimal codificado en binario): el byte va `0x09 → 0x10`, así que leído en crudo
el crédito 10 parece **16**. `creditos.lua` lo traduce en `leer_ram`/`escribir_ram`
(un nibble > 9 no es BCD válido y se devuelve tal cual). La marca es la palabra
`bcd` al final de la línea de `creditos.dat`. Juegos BCD: `ddragon defender dkong
dkongjr frogger joust kungfum mspacman pacman popeye robocop robotron timeplt
zaxxon`.

---

# PARTE B — La tabla de PUNTUACIONES

Aquí no buscamos un byte sino **una estructura**: varias entradas ordenadas de
mayor a menor, cada una con una puntuación y (casi siempre) unas iniciales. El
reparto de responsabilidades copia el de los créditos, pero con **dos** fuentes de
información:

| | dice… |
|---|---|
| `hiscore.dat` (de MAME) | **DÓNDE** vive la tabla: cpu, espacio, dirección, longitud |
| `hi2txt-xml` / `puntajes.dat` | **CÓMO** se lee ese bloque por dentro |

## B.1. DÓNDE: `hiscore.dat` y el plugin `hiscore`

MAME trae un plugin `hiscore` (activado en la cabina) que lee la tabla **de la RAM
del juego** y la escribe en `<homepath>/hiscore/<juego>.hi`. Su base `hiscore.dat`
cubre ~5.860 juegos y dice, por juego, dónde vive la tabla y cuánto ocupa:

```
@<cpu>,<espacio>,<direccion>,<longitud>,<espera1>,<espera2>[,<relleno>]
```

Dos cosas cruciales:

- **El plugin sólo escribe cuando la tabla CAMBIA** respecto a como estaba al
  arrancar. Un juego que nadie ha jugado **no deja ningún `.hi`**. Por eso, para
  cubrir muchos juegos sin jugarlos todos, se lee la tabla nosotros: `volcar.lua`
  lee de la RAM el bloque que declara `hiscore.dat` y lo imprime; `puntajes.py
  --fabrica` lo lanza por cada juego. (Verificado: el volcado directo de Donkey
  Kong coincide **byte a byte** con su `.hi`.)

- **El «espacio» puede ser un SHARE** (`<nombre>/share`) en vez de `program` —
  Missile Command guarda ahí su tabla— y **el fichero no siempre se llama
  `nvram`**: los NeoGeo usan `saveram`, Star Wars `x2212`, Gauntlet `eeprom`, Namco
  `at28c16`. Se le pregunta al XML qué fichero quiere.

`hiscore.dat` NO dice **cómo** está ordenada la tabla por dentro, y eso cambia con
cada placa. Ahí entra la segunda fuente.

## B.2. CÓMO: `hi2txt-xml` + `puntajes.dat` (y `hi2txt.py`)

**hi2txt-xml** (proyecto comunitario, GPL-2) es una base con la **estructura
interna** de la tabla de ~3.100 juegos — exactamente lo que faltaba. Trae dos
carpetas:

| carpeta | qué tiene |
|---|---|
| `db` | la **estructura**: cómo se lee la tabla de cada juego |
| `db_defaults` | la **tabla de fábrica ya descifrada** (~2.700 juegos) |

`hi2txt.py` implementa el subconjunto de ese formato que usan estos juegos, y
`puntajes.dat` guarda recetas propias con el mismo espíritu para lo que hi2txt no
cubre. Formatos que hay que entender:

- **De puntuación:** `bcd` (empaquetado, dos dígitos por byte), `bcdle` (BCD con
  los bytes al revés), `digitos` (un dígito decimal por byte), `be`/`le` (entero
  binario grande/pequeño), `texto` (los dígitos en ASCII, como Atetris).
- **De nombre:** `ascii`, o `idx:<alfabeto>` cuando las iniciales son un **índice
  de letra** y no ASCII (`0x0a`='A' en Capcom, `0x00`='A' en SNK, `0x11`='A' en
  Donkey Kong).

Y las claves finas que costó descubrir, cada una porque un juego salía mal **en
silencio**:

- **`<sameas id="…">`** — 2.322 de los 3.102 XML son redirecciones: los clones se
  apuntan al original (`rbtapper → tapper → journey`). Sin seguirlas se pierde la
  mayor parte de la base, y el fichero *parece* vacío.
- **`decoding-profile="bcd"` no siempre es BCD empaquetado.** Si todos los bytes
  valen 0-9, la placa guarda **un dígito por byte**; leerlo como empaquetado
  multiplica por diez mil (1943 daba 200000000 en vez de 20000).
- **`table-index="loop_reverse_index"`** — la tabla va guardada **del peor al
  mejor**. Ignorarlo devuelve la tabla al revés sin dar error (Kung-Fu Master
  salía con 14950 arriba cuando su marcador dice `TOP-048520`). La receta propia lo
  expresa con `orden=asc`.
- **`byte-swap="2"`** — los bytes van intercambiados por parejas (la placa vuelca
  en palabras de 16 bits). Afecta a los NeoGeo, `mwalk`, `goldnaxe`. El fallo es
  **mudo**: salen nombres bien formados pero equivocados (`ABKCPUR MAO` en vez de
  `BACKUP RAM`).
- **`byte-trim="0x24"`** — el byte de RELLENO del campo. En Galaga el relleno es
  `0x24` (el espacio de su juego de caracteres) y sin quitarlo se lee como un
  dígito más (daba 240200000000 en vez de 20000).
- **`*10`, `+1` implícitos** — el identificador de formato **ES** la operación;
  706 XML referencian un formato que no definen, y no es un descuido: es parte del
  formato.

## B.3. Elegir la fuente correcta (una regla que costó tres fallos)

Un juego puede tener varios ficheros candidatos (`.hi`, `nvram`, `eeprom`,
`saveram`…). El orden importa y **no es una lista fija**:

- **El `.hi` que exista de verdad va SIEMPRE primero.** Es lo que produce el
  rescate y lo que describe `hiscore.dat`. (Berzerk descifraba mal porque su XML
  pone `nvram` antes que `.hi`, y su nvram guarda cada byte partido en dos.)
- **Si el XML declara una fuente, no se busca fuera de ella.** Al permitir el
  comodín para todos, `arkanoid` leía su `nvram` en vez de su tabla y devolvía
  **0 en vez de 50000 sin dar error**.
- **Una fuente vacía no es una fuente.** Un fichero entero a `0x00` o a `0xFF` es
  memoria que la placa no ha escrito nunca; se descarta y se pasa a la siguiente
  (Centipede tiene un `earom` de 64 bytes a `0xFF` que descifraba `16777215`
  repetido = `0xFFFFFF`).

## B.4. Cuando no hay receta: buscar la tabla en el binario (`buscar_tabla.py`)

Para los juegos que nadie ha descrito, buscar «números que bajan» en un binario de
kilobytes da falsos positivos por todas partes. Lo que **sí** funciona es buscar
**grupos de letras a intervalos regulares**: una tabla de récords es de las
poquísimas cosas con esa forma. El método (automatiza lo que funcionó a ojo con
Double Dragon):

1. **Encontrar la rejilla de nombres.** `iniciales(d, i, modo)` mira si en la
   posición `i` hay 3 caracteres con pinta de iniciales — en ASCII, o como índice
   de letra probando los alfabetos `capcom`/`snk`/`dkong`. `rejillas()` busca
   posiciones donde esas iniciales se repiten a un paso constante (de 6 a 64
   bytes), al menos 4 veces.

2. **Descartar el nombre del juego.** ` DOUBLE DRAGON ` leído de tres en tres
   *también* parece una rejilla. La diferencia: en una tabla, **entre una inicial y
   la siguiente hay HUECO** (ceros, la puntuación), no más letras. `texto_corrido()`
   exige ese hueco.

3. **Buscar la puntuación dentro de la entrada.** Ya localizada la rejilla, la
   puntuación tiene que estar en los pocos bytes de esa misma entrada.
   `puntuacion()` prueba todos los desplazamientos cercanos, todos los formatos
   (`bcd/bcdle/digitos/be/le`) y todos los anchos, y **puntúa** cada lectura
   candidata: exige que los valores **bajen** (tabla ordenada), que haya al menos 3
   distintos, magnitud plausible (100 … 10.000.000), y da puntos extra si todos son
   múltiplos de 10 (las recreativas puntúan de 10 en 10).

4. **Probar los ocho modos.** Cada análisis prueba `normal` y `swap` (bytes
   intercambiados) × los cuatro alfabetos de iniciales. El `swap` es lo que
   destapa los NeoGeo.

Y una pista que ahorró muchísimo: **en TODOS los NeoGeo la tabla cae entre `0x320`
y `0x340`** del `saveram`. Con eso, en vez de barrer 64 KB, se mira un tramo de 32
bytes.

## B.5. La técnica que de verdad desatasca: anclar un número conocido

Cuando ni la receta ni la búsqueda por rejilla dan, la vía más potente es **saber
qué número tiene que aparecer y buscarlo**:

- **`db_defaults`** trae la tabla de fábrica ya descifrada. Buscando esos valores
  en el binario, la estructura aparece sola. Así cayó `xevious` (su `db_defaults`
  dice `40000 M.Nakamura…`; buscando 4000 en BCD sale a la primera).
- **Que Eloy juegue y diga la puntuación.** Con un valor real conocido, la entrada
  se localiza buscándolo. Así se cerraron `fatfury1` (1600, y de paso se vio que la
  puntuación va **dividida por 100** y las iniciales son índices), `samsho3`,
  `samsho2`, `mvsc`, `nrallyx`…

## B.6. La única prueba que vale: la PANTALLA

> **Una receta no está confirmada hasta que se ha comparado con lo que el juego
> enseña en pantalla.** El razonamiento «esas puntuaciones no pueden ser» no vale
> como prueba.

Esto se aprendió metiendo la pata en las dos direcciones:

- A `dkong` se le puso un `×10` «porque sus puntuaciones son múltiplos de 100» —
  **falso**: la pantalla enseñaba `007650`, exactamente el descifrado crudo.
- A `tmnt` se estuvo a punto de ponerle `×1000` porque 312 parecía poco; su
  atracción dice `1ST HID 312 PTS`, el número crudo era el bueno.
- `mappy`/`arkanoid`/`commando` tenían el multiplicador mal y sólo se vio mirando
  el marcador.

Confirmar es rápido: casi todos los juegos enseñan el récord en el HUD
permanentemente (`HIGH 25800` en Contra, `HI 57300` en Gradius), así que una
captura por juego valida la magnitud, que es donde aparece el error.

Y para comparar en masa: **`auditar_puntajes.py`** contrasta nuestra salida contra
las ~2.700 tablas de fábrica de `db_defaults`, juego a juego. Su primera pasada
sacó **15 juegos mal de 58**, todos en silencio — y de ahí salieron los arreglos de
`nibble-skip`/base-16, `loop_reverse_index` y las fuentes vacías.

> **Regla de oro del que mide:** un script que mide cobertura tiene que llamar a la
> MISMA función que produce el resultado, no reimplementarla. Estuvimos publicando
> «66 juegos» cuando eran 59 porque el medidor tenía su propia copia (más
> permisiva) de la lógica de descifrado.

## B.7. Contaminación de las capturas de fábrica

Un detalle fino pero importante para la marca `defecto` (distinguir un récord real
de las iniciales de relleno que trae la ROM): **el plugin `hiscore` reinyecta en la
RAM la puntuación guardada nada más arrancar.** Si se captura la «tabla de fábrica»
con el plugin activo, se captura el récord restaurado, no la de fábrica. Se corrige
con `-noplugins` (entonces Pac-Man y Ms. Pac-Man dan **0**, su fábrica de verdad).
Y aun así, un juego con NVRAM propia carga sus puntuaciones al arrancar plugins o
no; ahí se marca «no se sabe» en vez de arriesgarse a dar por ficticia una real.

---

## Resumen de la filosofía compartida

1. **Una dirección equivocada es peor que ninguna.** Ante la duda: estimar, o dejar
   en blanco.
2. **Comportamiento, no valor.** El contador se confirma haciéndolo subir y bajar;
   la tabla, viéndola bajar y coincidir con la pantalla. «Vale 0 al arrancar» no
   demuestra nada.
3. **La pantalla es la única verdad.** Ninguna receta está confirmada hasta que
   coincide con lo que el juego pinta.
4. **Medir en la máquina que se despliega.** Las roms del portátil y la cabina no
   son las mismas; las cifras se dan de la cabina.
5. **Los fallos de este terreno son MUDOS.** Casi ninguno da error: dan un número
   plausible y equivocado. Por eso todo se cruza contra una segunda fuente
   (cheats↔medición, descifrado↔`db_defaults`, receta↔pantalla).

## Dónde está cada pieza

| pieza | fichero | qué hace |
|---|---|---|
| Buscar el contador de créditos | `creditos/buscar_creditos.lua` + `.sh` | sondeo en vivo de la RAM |
| Importar direcciones de cheats | `creditos/importar_cheats.py` | ~4.958 direcciones de la colección de Pugsy |
| Leer/escribir el contador | `creditos/memoria.lua` (dentro de `creditos.lua`) | con traducción BCD |
| Tabla de créditos | `creditos/creditos.dat` | `juego @cpu,espacio,dir[+copias] [bcd] [(cheat)]` |
| Volcar la tabla de récords de la RAM | `creditos/volcar.lua` | lo que declara `hiscore.dat` |
| Descifrar una tabla | `creditos/hi2txt.py` + `puntajes.dat` + hi2txt-xml | de bytes a puntuaciones legibles |
| Buscar la tabla sin receta | `creditos/buscar_tabla.py` | por rejilla de iniciales |
| Auditar las recetas | `creditos/auditar_puntajes.py` | contra `db_defaults` |
| Exportar los puntajes | `creditos/puntajes.py` | a JSON, marcando fábrica/jugador |

Para el detalle línea a línea de cada uno de estos scripts, ver
[`lua.md`](lua.md) y [`py.md`](py.md).
