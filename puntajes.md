# Informe técnico: rescate y descifrado de puntuaciones de la cabina arcade

**Fecha:** 2026-09-08
**Autor:** sesión de Claude Code trabajando sobre el repositorio `attractplus-creditos`
**Destinatario:** un modelo de lenguaje que debe resumir esto para Eloy, en lenguaje llano

---

## 0. Instrucciones para la IA que lee este documento

Este documento es deliberadamente largo y técnico. Tu tarea es **explicárselo a
Eloy de forma humana y resumida**, no repetirlo. Ten en cuenta:

- Eloy es el dueño de la cabina. Sabe de electrónica y de recreativas, pero no
  necesita el detalle de bytes ni de código: quiere saber **qué funciona, qué
  no, y qué le queda por hacer**.
- Lo que más le importa, por orden: (1) que las puntuaciones de sus partidas se
  guarden y se puedan leer, (2) que las puntuaciones **falsas de fábrica** no
  cuenten como si fueran de alguien, (3) saber a qué juegos le falta jugar.
- Cuando haya un error cometido por la máquina o por el asistente, **dilo
  claramente**; no lo suavices. Varios de los hallazgos de este informe son
  errores propios corregidos.
- Si Eloy pregunta por un juego concreto, la tabla de la sección 8 tiene el
  estado de los 96.
- Las cifras de este documento están medidas, no estimadas. Si algo es una
  suposición, está marcado como tal.

---

## 1. Qué es este sistema y qué problema resuelve

La cabina es un mueble arcade que corre **GroovyArcade** (una distribución Linux
para recreativas) con **Attract-Mode Plus** como menú y **GroovyMAME** como
emulador. Hay unos 96 juegos instalados.

El problema: **MAME no tiene un concepto general de "puntuación máxima"**. Cada
placa arcade guarda su tabla de récords donde le da la gana, en un formato
distinto, y muchas ni siquiera la guardan al apagar. Antes de este trabajo, las
puntuaciones se perdían o quedaban enterradas en volcados binarios ilegibles.

El objetivo era doble:

1. **Rescatar** las puntuaciones: que sobrevivan al apagado de la máquina.
2. **Descifrarlas**: convertir esos volcados binarios en un fichero legible
   (JSON) que otro programa pueda consumir, distinguiendo las puntuaciones
   reales de las **falsas que trae la ROM de fábrica**.

Ese segundo punto es más importante de lo que parece. Casi toda recreativa
arranca con una tabla inventada por el fabricante — Bubble Bobble sale de
fábrica con `I.F`, `MTJ`, `NSO`; 1942 sale con `CAPCOM / ALL / RIGHT /
RESERVED`, que es su aviso de copyright repartido por los campos de nombre. Si
no se distinguen, el sistema publicaría decenas de récords que no son de nadie.

---

## 2. Arquitectura: de dónde salen los datos

### 2.1 El rescate (que los datos existan)

Lo hace un **plugin de MAME llamado `hiscore`**, que ya venía con el emulador.
Su funcionamiento, leído en su código fuente (`plugins/hiscore/init.lua`):

- Al arrancar el juego, lee de la RAM el bloque donde vive la tabla de récords.
- Al salir, si la tabla **ha cambiado** respecto a como estaba al arrancar,
  la escribe a un fichero `<juego>.hi`.
- **Consecuencia crítica:** un juego que nadie ha superado no deja ningún
  fichero. Eso explica por qué durante mucho tiempo sólo existían 8 ficheros.

Dónde escribe: **`<homepath>/hiscore/<juego>.hi`**. Esto tiene trampa y se
explica en la sección 5.1.

### 2.2 Las tres fuentes de datos

Un juego puede tener su tabla en tres sitios distintos, y hay que probarlos:

| fuente | qué es | ejemplo |
|---|---|---|
| `.hi` | el fichero que escribe el plugin al rescatar | `berzerk.hi` |
| memoria persistente | la NVRAM/EEPROM de la placa, que MAME guarda | `nvram`, `saveram`, `eeprom`, `earom`, `x2212`, `at28c16` |
| tabla de fábrica | volcado de la RAM que hicimos nosotros al arrancar | `puntajes_fabrica.json` |

Los nombres de la memoria persistente varían **por chip**, no hay una lista
corta: los NeoGeo usan `saveram`, Star Wars `x2212`, Gauntlet `eeprom`,
Centipede `earom`, la Namco Classic Collection `at28c16`.

### 2.3 Las dos bases de datos externas

| base | qué aporta | tamaño |
|---|---|---|
| `hiscore.dat` (viene con MAME) | **DÓNDE** vive la tabla de cada juego: CPU, espacio de memoria, dirección y longitud | 5.859 juegos |
| `hi2txt-xml` (comunitaria, GPL-2) | **CÓMO** se lee ese bloque por dentro: cuántas entradas, BCD o binario, dónde el nombre | 3.102 estructuras |

`hi2txt-xml` trae además una segunda carpeta, `db_defaults`, con **2.697 tablas
de fábrica ya descifradas**. Eso es oro: permite comparar nuestro resultado
contra una referencia independiente, que es la base de la prueba de la sección
4.2.

`hi2txt-xml` **no está copiada al repositorio** (es GPL-2 y se actualiza sola);
se descarga aparte.

### 2.4 Nuestras herramientas

| fichero | qué hace |
|---|---|
| `creditos/puntajes.py` | el programa principal: lee, descifra y exporta a JSON |
| `creditos/hi2txt.py` | intérprete de los XML de la base comunitaria |
| `creditos/puntajes.dat` | nuestras recetas propias, para los juegos que la base no describe |
| `creditos/volcar.lua` | lee de la RAM el bloque de `hiscore.dat` (para la tabla de fábrica) |
| `creditos/buscar_tabla.py` | localiza tablas desconocidas buscando iniciales a intervalos regulares |
| `creditos/auditar_puntajes.py` | compara nuestro resultado con la referencia de la comunidad |
| `creditos/pruebas/rescate.lua` + `.sh` | prueba de extremo a extremo del rescate |

Añadir un juego nuevo es **añadir una línea a `puntajes.dat`**, sin tocar código.

---

## 3. Estado actual, en cifras

La tabla de la sección 8 lista **96 sets**. De ellos se apartan 7:

- **5 excluidos por no tener ranking**: `neogeo` (es la BIOS de Neo-Geo, no un
  juego), `goldnaxe` (su bloque guarda la *fuerza* de los tres personajes, no
  puntuaciones), `polepos` (100 valores de relleno sin un solo nombre),
  `tekken3` y `tektagt` (no están instalados).
- **2 no instalados** que aparecen sólo porque quedó algún dato suelto de una
  prueba antigua: `profpac` y `simpsons` (en la cabina está `simpsons2p`).

Quedan **89 juegos que pueden guardar puntuaciones**, y ése es el denominador
de todas las cifras siguientes:

| categoría | juegos |
|---|---|
| **Tabla leída correctamente** | **83** |
| — de ellos, verificados contra el marcador en pantalla | 19 |
| Sin resolver (hay datos, falta deducir el formato) | 4 |
| Sin datos (nadie ha jugado y no hay fichero) | 2 |

Eso es un **93 % de cobertura**.

En total se exportan **722 posiciones** (cada posición es una línea de una tabla
de récords). De ellas:

- **270 identificadas como de fábrica** (falsas, a descartar)
- **50 identificadas como de un jugador real**
- **402 sin determinar** — son juegos con NVRAM propia, donde no hay forma
  fiable de saberlo (ver sección 4.5)

---

## 4. Las pruebas realizadas

Esta es la parte central del informe. Cada prueba se describe con su **método**,
su **resultado** y **qué demuestra y qué no**.

### 4.1 Prueba de extremo a extremo del rescate

**Por qué hacía falta.** Que un fichero `.hi` se descifre bien no demuestra que
el rescate funcione: falta comprobar la otra mitad, que el plugin lo escriba de
verdad cuando alguien juega. Esa mitad nunca se había probado.

**Método.** Se escribió `creditos/pruebas/rescate.lua` + `rescate.sh`. Para cada
juego:

1. Se arranca el juego en el emulador con el plugin `hiscore` activo.
2. En el fotograma 1800 se **cambia un solo byte** del bloque de memoria que
   declara `hiscore.dat`. Esto es exactamente el disparador real del plugin,
   porque sólo escribe si la tabla difiere de como estaba al arrancar.
3. Se sale limpiamente.
4. Se comprueba que el fichero `.hi` resultante coincide **byte a byte** con lo
   que quedó en la RAM.

**Detalle de diseño que importa:** se toca el **último** byte del bloque, no el
primero. En muchas placas el primer byte es el dígito más significativo, y
cambiarlo da una puntuación absurda que el filtro de plausibilidad descartaría
— con lo que la prueba fallaría por un motivo distinto del que se está
probando.

**Resultado: 13 juegos de nueve fabricantes distintos, 13 en verde.**

```
kungfum  centiped  frogger  popeye  zaxxon  missile  joust
robotron mario     timeplt  snowbros gng    btime
```

Entre ellos, deliberadamente, los dos casos que más podían fallar:

- **`missile`**, cuyo bloque de memoria no es un espacio de CPU sino un
  *share* de memoria (un caso especial que se trata distinto en el código).
- **`joust` y `robotron`**, de Williams, que guardan los dígitos **en medios
  bytes (nibbles)** en vez de bytes enteros.

**Qué demuestra:** que la cadena completa funciona — el juego cambia su tabla,
el plugin la escribe, nuestro programa la encuentra y la lee. **Qué no
demuestra:** que el *valor* sea correcto; de eso se ocupa la prueba 4.2.

**Confirmación adicional en el mundo real.** Después de esta prueba, Eloy jugó
a varios juegos y aparecieron **tres ficheros `.hi` nuevos** (`berzerk`,
`nrallyx`, `mvsc`) en juegos que nunca habían guardado nada. El rescate
funciona en producción, no sólo en el banco de pruebas.

### 4.2 Auditoría contra una referencia independiente

**Método.** `auditar_puntajes.py` compara nuestro descifrado, juego a juego,
contra las **2.697 tablas de fábrica ya descifradas** que trae `hi2txt-xml` en
su carpeta `db_defaults`. Es una referencia escrita por otra gente, con otro
código, así que coincidir es una prueba de verdad y no una comprobación
circular.

**Resultado final: 54 coinciden, 5 no coinciden, 24 sin referencia disponible.**

Las cinco discrepancias, todas analizadas una a una:

| juego | nuestro resultado | referencia | veredicto |
|---|---|---|---|
| `centiped` | 13210, 13010, 12805… | 16543, 15432, 14320… | **no es un fallo**: leemos las posiciones 4 a 8 porque las tres primeras viven en su chip `earom`, que en esta cabina está sin escribir. Nuestros valores 4 y 5 coinciden exactos con los suyos. |
| `joust` | 23310, 22917, 22552… | 4000 ×5 | **probablemente la referencia está mal**: nuestros bytes codifican 23310 sin ninguna ambigüedad, y esos números *no redondos* son la firma característica de las tablas de fábrica de Williams. Un `4000` repetido cinco veces parece una tabla borrada. |
| `punchout` | 48000 … 47200 | 88700 … 84700 | escalera coherente pero distinta; lo más probable es que la referencia describa otra revisión de la placa. |
| `mk` / `mk2` | 13 de 15 posiciones exactas | 15 | **fallo parcial conocido**: dos posiciones concretas no se descifran bien; las otras trece coinciden al número. |

**Qué demuestra:** que el descifrado es correcto en la gran mayoría, y que las
excepciones están entendidas y documentadas, no ignoradas.

### 4.3 Verificación contra el marcador en pantalla

**Por qué hacía falta.** Una tabla puede descifrarse en algo perfectamente
plausible y estar mal. Ocurrió: a Donkey Kong se le había puesto un
multiplicador ×10 "porque sus puntuaciones son múltiplos de 100", y era falso.

**Método.** Se arranca el juego en el emulador, se captura su modo de atracción
(las pantallas que muestra solo) y **se lee con los ojos** el número que enseña,
comparándolo con lo que descifra nuestro programa.

**Resultado: 19 juegos verificados al número exacto.** Y la técnica cazó tres
recetas que parecían perfectas y estaban mal:

| juego | lo que enseña la pantalla | lo que dábamos | arreglo |
|---|---|---|---|
| `arkanoid` | `HIGH SCORE 50000` | 5000 | faltaba multiplicar por 10 |
| `commando` | `TOP SCORE 50000` | 5000 | faltaba multiplicar por 10 |
| `mappy` | `HIGH SCORE 20000` | 200000 | leía un dígito de más |

**Regla adoptada:** una receta **no cuenta como confirmada** hasta compararla
con lo que el juego enseña en pantalla. El razonamiento "esas puntuaciones no
pueden ser" no vale como prueba.

**Límite de esta técnica:** no todos los juegos enseñan su tabla. Se capturaron
170 segundos del modo atracción de `strhoop` y de `samsho` y **ninguno de los
dos la muestra** (alternan logos, demos e instrucciones). Con `mk3` pasa lo
mismo: su atracción sólo enseña «LONGEST WINNING STREAKS». En esos juegos esta
vía está cerrada y hay que apoyarse en otra cosa.

### 4.4 Barrido de coherencia sobre los 83 juegos

**Método.** Un comprobador automático revisa **todas** las tablas descifradas
buscando:

- valores que no van ordenados (una tabla de récords siempre lo está)
- magnitudes imposibles (más de cien millones)
- tablas enteras a cero
- nombres con caracteres no imprimibles
- posiciones duplicadas o con huecos

**Resultado: 12 avisos de 83 juegos, y diez eran falsos avisos.** Los diez
falsos eran tablas de fábrica en las que **todas las posiciones valen lo
mismo**, que es completamente normal — Bubble Bobble sale con 30000 en las
cinco, Galaga con 20000 — y además están verificadas contra la referencia.

Los dos avisos reales sí eran fallos, y se corrigieron:

- **`sfiii3` no tiene una tabla de 19 posiciones, sino CUATRO de cinco.**
  Street Fighter III guarda varias categorías de ranking (100000, 90000, 80000,
  70000, 60000 repetido cuatro veces con nombres distintos) y las estábamos
  pegando en una sola lista. Ahora se publica la primera.
- **`tekken2` declaraba 33 entradas y las últimas nueve eran basura**
  (327698, 262149, 196609, 131074, 65542 — patrones de bits, no puntuaciones).
  Su tabla útil son 24 entradas. Además, el valor `359999` que aparece repetido
  es su marcador de "sin récord", no una puntuación.

### 4.5 La prueba de la contaminación de las tablas de fábrica

Esta es la prueba que destapó el fallo más serio, y merece contarse entera.

**Síntoma.** Pac-Man aparecía con sus **48800 puntos reales marcados como "de
fábrica"**. Si eso llegaba al fichero final, el programa de Eloy los habría
descartado por falsos.

**Investigación.** La tabla de fábrica de cada juego se obtiene arrancándolo y
volcando de la RAM el bloque que declara `hiscore.dat`. Pero ese volcado se
hacía **con el plugin `hiscore` activo**, y ese plugin hace justo lo contrario
de lo que conviene: **reinyecta en la RAM la puntuación guardada nada más
arrancar**. O sea que no estábamos capturando la tabla de fábrica, sino el
récord restaurado.

**Prueba.** Se recapturaron los 11 juegos afectados con la opción
`-noplugins`:

| juego | antes (contaminado) | después (real) |
|---|---|---|
| `pacman` | 48800 | **0** |
| `mspacman` | 4500 | **0** |
| `nrallyx` | 96550 | **20000** |

El `0` de Pac-Man es correcto y estaba ya documentado: esa placa no tiene
memoria persistente, arranca siempre sin récord.

**Segundo hallazgo, que `-noplugins` NO arregla.** Un juego con **memoria
persistente propia** carga sus puntuaciones al arrancar, haya plugins o no.
Berzerk siguió volcando los 900 puntos de Eloy porque están en su NVRAM. En
esos juegos **no existe forma fiable de saber cuál era la tabla de fábrica**,
así que ahora se marcan como *"no se sabe"* en vez de arriesgarse a dar por
ficticia una puntuación real. Es deliberadamente el error barato: dejar pasar
un nombre de fábrica es molesto; descartar el récord de alguien es peor.

**Tercer hallazgo.** Existía un fichero `puntajes_defecto.json` con bases
capturadas a mano, y **envejece**: su entrada de `mvsc` decía
`[['05', 80003], ...]`, de cuando ese juego todavía no tenía receta. Ahora la
base **se deduce** con las recetas de hoy y manda sobre la capturada.

### 4.6 Prueba de fuerza bruta contra el corpus (resultado negativo)

**Idea.** Para los juegos que nadie ha descrito, probar las **3.102 estructuras
del corpus** contra sus datos, filtrando por tamaño y plausibilidad, a ver si
alguna encaja.

**Resultado: no funciona.** Salieron **437 "candidatas" para `mvsc`, 434 para
`ncv2` y 342 para `gaunt2`**, todas basura. **No se metió ninguna en el
sistema.**

**Qué demuestra:** que "va de mayor a menor" es una señal demasiado débil en un
fichero de kilobytes. La única vía que funciona es **anclar un número
conocido** — de la referencia, del marcador en pantalla, o de que Eloy juegue y
diga su puntuación.

### 4.7 La batería de pruebas del repositorio

Además de todo lo anterior, el repositorio tiene **339 comprobaciones
automáticas** (del monedero, del cerrojo de monedas, del arranque, de la lectura
de memoria, etc.). Se ejecutaron después de cada cambio.

**Resultado: 339 en verde, 0 fallos**, en todas las pasadas.

### 4.8 Prueba aparte: Ms. Pac-Man se pasaba los niveles sola

Eloy reportó que Ms. Pac-Man avanzaba de nivel sin tocar el mando.

**Método.** Se lanzó el juego metiendo moneda y START desde un script, **sin
tocar el mando**, y se trazó el byte de memoria que guarda el nivel:

| | frame 720 | 840 | 1680 | 1920 | 2160 |
|---|---|---|---|---|---|
| con la configuración vieja | 0 | **1** | **2** | **3** | **4** |
| corregida | 0 | 0 | 0 | 0 | 0 |

**Causa:** un interruptor de la propia placa, el `Rack Test (Cheat)`, que sirve
para que el técnico repase pantallas sin jugarlas. Estaba **guardado como
activado** en el fichero de configuración del juego. Se enciende con F1 y se
queda puesto para siempre, así que basta un teclado enchufado y un despiste.

**No era un fallo del código de la cabina.** Corregido y verificado en los dos
sentidos.

---

## 5. Los fallos encontrados y corregidos

Ordenados por gravedad. Varios eran errores del propio asistente.

### 5.1 Se buscaban los ficheros rescatados en el sitio equivocado

**Gravedad: alta.** Durante un tiempo se afirmó que "el rescate nunca había
rescatado nada". **Era falso.**

El plugin moderno escribe en `<homepath>/hiscore/`. El fichero `hiscore.ini`
declara otra ruta (`hi_path`), pero **eso es de la versión antigua del plugin y
hoy no lo lee nadie** — en esta cabina apunta a un directorio que ni siquiera
existe. Los ficheros rescatados estaban al lado, y había ocho.

Se reforzó la búsqueda: ahora la ruta **se le pregunta a MAME** en vez de
suponerla.

### 5.2 La marca "de fábrica" estaba mal calculada

Ver sección 4.5. Es el fallo que más habría dolido, porque descartaba
puntuaciones reales.

### 5.3 Un fichero con bytes no es un fichero con la tabla

El programa se quedaba con la **primera fuente que tuviera datos**. Pero que un
fichero no esté vacío no significa que lleve la tabla: **la NVRAM de Golden Axe
sólo guarda la fuerza de los tres personajes** — su propia documentación lo dice
— y las puntuaciones irían en el `.hi`. Ahora se prueban **todas** las fuentes y
vale la que **descifre**, no la que pese.

### 5.4 El `.hi` debe ir siempre primero

Descubierto gracias a los datos de Eloy. Berzerk descifraba **mal y sin dar
ningún error**: daba `J O 990` y `C4ETGt 990` donde el jugador había marcado
`JO 900` y `CEG 900`.

La causa no era la receta sino la fuente elegida: la NVRAM de Berzerk **guarda
cada byte partido en dos** (`09 90`, `4a a4`, `43 34`), así que de ahí sale un
número plausible y equivocado. Su fichero `.hi` da los dos valores exactos.

**Regla:** un `.hi` que existe de verdad va siempre primero, porque es el
fichero que produce el rescate.

### 5.5 Otros fallos silenciosos del descifrador

Todos daban resultados **sin error**, que es lo peligroso:

| fallo | efecto | ejemplo |
|---|---|---|
| `byte-trim` sin implementar | el byte de relleno se leía como una cifra más | Galaga daba `240200000000` en vez de `20000` |
| `<loop start="N">` ignorado | las posiciones se numeraban desde 1 aunque el bloque empezara más abajo | Centipede publicaba su 4ª posición como si fuera el récord |
| `base="16"` mal interpretado | se leía en hexadecimal lo que eran cifras decimales | Mario Bros daba 73728 donde marca 12000 |
| orden inverso ignorado | la tabla salía del revés | Kung-Fu Master ponía el peor arriba |
| `byte-swap` sin implementar | bytes intercambiados por parejas | los NeoGeo daban `ABKCPUR MAO` en vez de `BACKUP RAM` |
| corte demasiado agresivo | se tiraban 13 posiciones buenas por 2 malas | Mortal Kombat quedaba en 2 posiciones de 15 |
| "tabla vacía" contada como fracaso | juegos resueltos figuraban como fallidos | `berzerk`, `tapper`, `rbtapper` |

---

## 6. Técnicas que funcionaron, y en qué orden probarlas

Esto es lo más reutilizable del trabajo. Ordenado de más a menos fiable:

1. **Que un humano juegue y diga su puntuación.** Con un número conocido, la
   estructura se localiza buscándolo en el binario. Es lo que resolvió
   `fatfury1`, `samsho3`, `nrallyx`, `mvsc` y `samsho`. **Imbatible.**
2. **La tabla de fábrica ya descifrada de la base comunitaria** (`db_defaults`).
   Da el número que tiene que salir sin necesidad de jugar.
3. **El marcador en pantalla.** Casi todos los juegos enseñan el récord en el
   HUD permanentemente; con una captura basta para validar la magnitud.
4. **Buscar iniciales a intervalos regulares.** Una tabla de récords es de las
   pocas cosas con esa forma. Hay que probar tanto ASCII como iniciales
   guardadas por índice (`0x00`='A' en SNK, `0x0a`='A' en Capcom).
5. **Parentesco entre placas de la misma familia**, con cuidado: funciona a
   veces (`rbtapper` ← `tapper`) y falla otras.
6. **Patrones por fabricante.** Se descubrió que en **todos** los NeoGeo la
   tabla vive entre las direcciones `0x320` y `0x340` de su `saveram`, con los
   bytes intercambiados por parejas. Con esa pista se mira un tramo de 32 bytes
   en vez de un fichero de 64 KB.

**Lo que NO funciona:** probar el corpus entero a ciegas (sección 4.6).

---

## 7. Lo que queda pendiente

### 7.1 Juegos sin resolver (4)

| juego | por qué |
|---|---|
| `gaunt2`, `gaunt22p` | su EEPROM de 512 bytes no tiene ni una cadena de texto ni escaleras numéricas, y `hiscore.dat` no cubre esa familia, así que tampoco hay bloque de RAM que volcar |
| `mk3` | su modo de atracción sólo enseña «LONGEST WINNING STREAKS», no puntuaciones; su NVRAM no da una lectura coherente |
| `ncv2` | su EEPROM sólo contiene su firma (`NamcoClassic2Ar0`); no hay tabla escrita. Descartado a petición de Eloy: son seis juegos en uno |

### 7.2 Juegos sin datos (2)

`gauntlet` y `gauntlet2p`: nadie ha jugado y no hay fichero. **Se resuelven
jugando.**

### 7.3 Recetas sin confirmar en pantalla

`strhoop` y `samsho` tienen receta y dan resultados coherentes, pero **ninguno
de los dos enseña su tabla en el modo atracción**, así que no se han podido
verificar visualmente. Para `samsho` hay un apoyo fuerte: sus iniciales
descifran **SNK**, que es el relleno de fábrica de esa casa, sobre una escalera
redonda de 50000/30000/10000.

### 7.4 Una duda menor

Eloy anotó "RbTapper 50125, Tapper 40975" y los ficheros dicen lo contrario
(`tapper` 50125, `rbtapper` 40975). Cada juego escribe en su propia carpeta, así
que cruzarse es imposible por parte del sistema. Eloy ya confirmó que
probablemente se le intercambiaron al anotarlos: son dos juegos casi idénticos.

---

## 8. Estado juego a juego

Leyenda:

- **LEIDA** — su tabla se lee correctamente
- **SIN RESOLVER** — hay datos guardados pero falta deducir el formato
- **SIN DATOS** — nadie ha jugado y no hay fichero
- **EXCLUIDO** — no es un juego con ranking
- **NO INSTALADO** — no está en la cabina; aparece porque quedó algún dato
  suelto de una prueba antigua. No cuenta en las cifras de la sección 3.

En la columna *fuente*: `hi` = fichero rescatado por el plugin; `nvram`,
`saveram`, `eeprom`, `earom`, `x2212`, `at28c16` = memoria persistente de la
placa; `fabrica` = volcado de la RAM hecho por nosotros.

| set | estado | posiciones | fuente | receta | detalle |
|---|---|---|---|---|---|
| 1942 | LEIDA | 25 | hi | hi2txt | mejor: CAPCOM 40000 |
| 1943 | LEIDA | 5 | hi | hi2txt | mejor: TAE 20000 |
| 19xxu | LEIDA | 17 | fabrica | hi2txt | mejor: UAEAN 100000 |
| arkanoid | LEIDA | 5 | fabrica | hi2txt | mejor: SSB 50000 |
| asteroid | LEIDA | 1 | hi | hi2txt | mejor: 590 |
| atetris | LEIDA | 10 | fabrica | propia | mejor: KFT 7000 |
| avsp | LEIDA | 49 | fabrica | hi2txt | mejor: CHM 300000 |
| berzerk | LEIDA | 2 | hi | hi2txt | mejor: JO 900 |
| btime | LEIDA | 5 | fabrica | hi2txt | mejor: 28000 |
| btoads | LEIDA | 10 | nvram | propia | mejor: pm. 6000 |
| bublbobl | LEIDA | 5 | hi | hi2txt | mejor: I.F 30000 |
| centiped | LEIDA | 5 | fabrica | hi2txt | mejor: 13210 |
| commando | LEIDA | 7 | fabrica | hi2txt | mejor: VULGUS.... 50000 |
| contra | LEIDA | 8 | fabrica | hi2txt | mejor: KKK 25800 |
| ddragon | LEIDA | 5 | hi | hi2txt | mejor: GLF 20000 |
| defender | LEIDA | 8 | nvram | hi2txt | mejor: 21270 |
| digdug | LEIDA | 5 | fabrica | hi2txt | mejor: 10000 |
| dkong | LEIDA | 5 | hi | hi2txt | mejor: 7650 |
| dkong3 | LEIDA | 5 | fabrica | hi2txt | mejor: WIN 12000 |
| dkongjr | LEIDA | 5 | fabrica | hi2txt | mejor: HAM 7650 |
| doubledr | LEIDA | 5 | saveram | propia | mejor: TAC 10000 |
| elevator | LEIDA | 1 | fabrica | hi2txt | mejor: 10000 |
| fatfury1 | LEIDA | 5 | saveram | propia | mejor: PON 1600 |
| ffight | LEIDA | 5 | fabrica | hi2txt | mejor: NIN 20000 |
| frogger | LEIDA | 5 | fabrica | hi2txt | mejor: 4630 |
| galaga | LEIDA | 5 | fabrica | hi2txt | mejor: 20000 |
| galaxian | LEIDA | 1 | fabrica | propia | mejor: 0 |
| gaunt2 | SIN RESOLVER | - | eeprom | - | hay datos, falta el formato |
| gaunt22p | SIN RESOLVER | - | eeprom | - | hay datos, falta el formato |
| gauntlet | SIN DATOS | - | - | - | no hay fichero guardado |
| gauntlet2p | SIN DATOS | - | - | - | no hay fichero guardado |
| gng | LEIDA | 10 | fabrica | hi2txt | mejor: Yuk 10000 |
| goldnaxe | EXCLUIDO | - | - | - | guarda la FUERZA de los personajes, no puntuaciones |
| gradius | LEIDA | 10 | fabrica | hi2txt | mejor: H.M 57300 |
| joust | LEIDA | 6 | fabrica | hi2txt | mejor: 23310 |
| kof2000 | LEIDA | 5 | saveram | hi2txt | mejor: ICH 100 |
| kof97 | LEIDA | 6 | saveram | hi2txt | mejor: S.I 100000 |
| kof98 | LEIDA | 5 | saveram | hi2txt | mejor: S.I 100000 |
| kof99 | LEIDA | 5 | saveram | hi2txt | mejor: TAK 100 |
| kungfum | LEIDA | 20 | fabrica | hi2txt | mejor: N.A 48520 |
| mappy | LEIDA | 5 | fabrica | hi2txt | mejor: BEH 20000 |
| mario | LEIDA | 5 | fabrica | hi2txt | mejor: AKI 12000 |
| megaman | LEIDA | 5 | fabrica | hi2txt | mejor: OKO 50000 |
| megaman2 | LEIDA | 5 | fabrica | hi2txt | mejor: OKO 20000 |
| missile | LEIDA | 8 | fabrica | hi2txt | mejor: 7500 |
| mk | LEIDA | 13 | nvram | hi2txt | mejor: CARALA 3356790 |
| mk2 | LEIDA | 13 | nvram | hi2txt | mejor: CARALA 3356790 |
| mk3 | SIN RESOLVER | - | nvram | - | hay datos, falta el formato |
| mslug | LEIDA | 10 | saveram | hi2txt | mejor: 107400 |
| mslug2 | LEIDA | 10 | saveram | hi2txt | mejor: APE 107400 |
| mslug3 | LEIDA | 10 | saveram | hi2txt | mejor: APE 107400 |
| mspacman | LEIDA | 1 | hi | propia | mejor: 4500 |
| mvsc | LEIDA | 10 | hi | propia | mejor: ABC 371702 |
| mwalk | LEIDA | 10 | nvram | hi2txt | mejor: M.J 50000 |
| ncv2 | SIN RESOLVER | - | at28c16 | - | hay datos, falta el formato |
| nemesis | LEIDA | 10 | fabrica | hi2txt | mejor: H.M 57300 |
| neogeo | EXCLUIDO | - | - | - | BIOS, no es un juego |
| nrallyx | LEIDA | 1 | hi | propia | mejor: 96550 |
| outrun | LEIDA | 20 | fabrica | hi2txt | mejor: YU. 5000000 |
| pacman | LEIDA | 1 | hi | propia | mejor: 48800 |
| polepos | EXCLUIDO | - | - | - | 100 valores de relleno y ningun nombre |
| popeye | LEIDA | 5 | fabrica | hi2txt | mejor: GET 32600 |
| profpac | NO INSTALADO | - | nvram | - | no está en la cabina; sólo quedó su NVRAM de una prueba |
| punchout | LEIDA | 10 | fabrica | hi2txt | mejor: NCL 48000 |
| qbert | LEIDA | 23 | nvram | hi2txt | mejor: TJC 3000 |
| rampage | LEIDA | 3 | nvram | hi2txt | mejor: 75840 |
| rbtapper | LEIDA | 1 | nvram | hi2txt | mejor: CEG 40975 |
| robocop | LEIDA | 10 | fabrica | hi2txt | mejor: MURPHY 50000 |
| robotron | LEIDA | 38 | nvram | hi2txt | mejor: 10000 |
| samsho | LEIDA | 5 | saveram | propia | mejor: SNK 50000 |
| samsho2 | LEIDA | 3 | saveram | propia | mejor: 7000 |
| samsho3 | LEIDA | 1 | saveram | propia | mejor: ACD 50400 |
| samsho4 | LEIDA | 13 | saveram | propia | mejor: SIN 600000 |
| samsho5 | LEIDA | 28 | saveram | propia | mejor: HAO 600000 |
| sf | LEIDA | 9 | fabrica | propia | mejor: HRO 10180 |
| sf2 | LEIDA | 6 | fabrica | hi2txt | mejor: NIN 50000 |
| sfiii3 | LEIDA | 5 | fabrica | propia | mejor: SDM 100000 |
| simpsons | NO INSTALADO | - | - | - | en la cabina está `simpsons2p`, no este set |
| simpsons2p | LEIDA | 10 | fabrica | hi2txt | mejor: BAT 108 |
| snowbros | LEIDA | 5 | fabrica | hi2txt | mejor: 40000 |
| ssf2t | LEIDA | 6 | fabrica | propia | mejor: POO 50000 |
| ssriders | LEIDA | 10 | fabrica | propia | mejor: KID 100000 |
| starwars | LEIDA | 3 | x2212 | hi2txt | mejor: 1285353 |
| strhoop | LEIDA | 5 | saveram | propia | mejor: 60 |
| tapper | LEIDA | 1 | nvram | hi2txt | mejor: CEG 50125 |
| tekken | LEIDA | 15 | fabrica | propia | mejor: AGR 180000 |
| tekken2 | LEIDA | 24 | fabrica | propia | mejor: KAZ 359999 |
| tekken3 | EXCLUIDO | - | - | - | no instalado en la cabina |
| tektagt | EXCLUIDO | - | - | - | no instalado en la cabina |
| timeplt | LEIDA | 5 | fabrica | hi2txt | mejor: K.O 10000 |
| tmnt | LEIDA | 10 | fabrica | propia | mejor: HID 312 |
| tmnt2po | LEIDA | 10 | fabrica | propia | mejor: HID 312 |
| tron | LEIDA | 10 | nvram | hi2txt | mejor: 2000 |
| wboy | LEIDA | 20 | fabrica | hi2txt | mejor: BUC 30000 |
| xevious | LEIDA | 4 | fabrica | propia | mejor: M.Nakamura 40000 |
| zaxxon | LEIDA | 6 | fabrica | hi2txt | mejor: 8900 |


---

## 9. Dónde está cada cosa

| qué | dónde |
|---|---|
| Fichero de salida legible | JSON generado por `creditos/puntajes.py` |
| Estado resumido para revisar | `~/Desktop/listaArcade.xlsx`, hoja **«Puntajes»** |
| Todas las posiciones, una por fila | `~/Desktop/listaArcade.xlsx`, hoja **«Puntajes detalle»** (722 filas; las de fábrica van sombreadas en gris) |
| Razonamiento completo del proyecto | `CLAUDE.md` en la raíz del repositorio |
| Recetas por juego | `creditos/puntajes.dat` |
| Repositorio | `github.com/Kotaix0807/attractplus-creditos`, rama `master` |

---

## 10. Glosario para la IA que resume

- **Set / romset:** el nombre corto de un juego en MAME (`pacman`, `kof97`).
- **Tabla de récords / ranking:** la lista de mejores puntuaciones con
  iniciales que enseña una recreativa.
- **Tabla de fábrica:** la que trae la ROM de origen, con nombres inventados por
  el fabricante. No es de nadie.
- **NVRAM:** memoria de la placa que sobrevive al apagado. Cada fabricante la
  llama distinto.
- **`.hi`:** el fichero donde el plugin `hiscore` de MAME guarda la tabla
  rescatada.
- **BCD:** forma de guardar números donde cada medio byte es una cifra decimal.
  Muy común en placas de los 80.
- **Receta:** una línea de `puntajes.dat` que describe cómo leer la tabla de un
  juego concreto.
- **Modo atracción:** lo que la recreativa enseña sola cuando nadie juega.

---

## 11. Resumen en cinco frases, por si hace falta

1. Las puntuaciones **se rescatan y se leen bien en 83 de los 89 juegos** que
   pueden guardarlas, un 93 %.
2. El rescate está **probado de extremo a extremo** en 13 juegos de nueve
   fabricantes, y confirmado en producción: aparecieron tres ficheros nuevos en
   cuanto Eloy jugó.
3. El descifrado está **auditado contra una referencia independiente** (54
   coinciden, 5 discrepancias todas explicadas) y **19 juegos verificados
   mirando el marcador en pantalla**.
4. Se encontraron y corrigieron **once fallos, y ninguno daba error**: el
   programa devolvía números perfectamente formados y equivocados. El peor
   marcaba puntuaciones reales como falsas de fábrica, y las habría descartado.
5. Lo que queda son **cuatro juegos sin resolver y dos sin datos**; los dos
   últimos se arreglan simplemente jugando a Gauntlet.
