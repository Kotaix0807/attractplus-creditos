# Los scripts Python del proyecto, explicados a fondo

Este documento explica **qué hace cada línea que importa** de los `.py` propios
del proyecto (no los de Attract-Mode Plus, que son de terceros). Está escrito
para alguien que programa pero no ha visto este código antes. El *por qué*
histórico de cada decisión (qué falló, qué se probó y se descartó, qué dijo
Eloy) vive en `CLAUDE.md`; aquí se documenta **lo que el código hace hoy**,
función por función.

No se ha modificado ningún fichero para escribir esto: es lectura y
documentación pura.

## Índice

1. [Panorama: cómo encajan estos scripts entre sí](#1-panorama-cómo-encajan-estos-scripts-entre-sí)
2. [`creditos/puntajes.py` — el programa central de puntuaciones](#2-creditospuntajespy--el-programa-central-de-puntuaciones)
3. [`creditos/hi2txt.py` — el intérprete del formato hi2txt-xml](#3-creditoshi2txtpy--el-intérprete-del-formato-hi2txt-xml)
4. [`creditos/buscar_tabla.py` — encontrar la tabla por las iniciales](#4-creditosbuscar_tablapy--encontrar-la-tabla-por-las-iniciales)
5. [`creditos/auditar_puntajes.py` — comparar contra la referencia](#5-creditosauditar_puntajespy--comparar-contra-la-referencia)
6. [`creditos/importar_cheats.py` — sacar direcciones de la colección de cheats](#6-creditosimportar_cheatspy--sacar-direcciones-de-la-colección-de-cheats)
7. [`creditos/escribir_ajuste.py` — editar una clave de `arranque.dat`](#7-creditosescribir_ajustepy--editar-una-clave-de-arranquedat)
8. [`contador_arduino.py` — el saldo hacia el Arduino](#8-daemonpy--el-saldo-hacia-el-arduino)
9. [`pantalla.py` — dejar el CRT como única pantalla](#9-pantallapy--dejar-el-crt-como-única-pantalla)
10. [`patron.py` — patrón de calibración del CRT](#10-patronpy--patrón-de-calibración-del-crt)
11. [`arduino/sandbox.py` — el banco de pruebas del puerto serie](#11-arduinosandboxpy--el-banco-de-pruebas-del-puerto-serie)
12. [Resumen de trampas y decisiones no obvias](#12-resumen-de-trampas-y-decisiones-no-obvias)

---

## 1. Panorama: cómo encajan estos scripts entre sí

Hay dos familias completamente separadas:

**A) Las puntuaciones** (todo en `creditos/`): `puntajes.py` es el programa
principal. No sabe descifrar nada por sí solo — delega en dos fuentes de
conocimiento externas y en una carpeta de recetas propia:

```
hiscore.dat (de MAME)          dice DÓNDE vive la tabla de cada juego
                                (CPU, espacio de memoria, dirección, longitud)
        │
        v
  puntajes.py  ──usa──>  hi2txt.py  ──lee──>  hi2txt-xml/src/main/db/*.xml
        │                                     (dice CÓMO se lee esa tabla,
        │                                      para ~3100 juegos)
        │
        └──si hi2txt no lo describe──>  puntajes.dat (nuestras recetas a mano)
```

`buscar_tabla.py` y `auditar_puntajes.py` son herramientas satélite que
**ayudan a construir o verificar** esas recetas, pero no las aplica nadie en
producción salvo `puntajes.py`. `importar_cheats.py` no toca puntuaciones: saca
direcciones de **créditos** (para `creditos.dat`, que usa `creditos.lua`, no
`puntajes.py`) de una fuente completamente distinta (los cheats de MAME).
`escribir_ajuste.py` tampoco toca puntuaciones: edita `arranque.dat`, el
fichero que lee `ajustes.lua` dentro de MAME para saber cuánto tapar el
arranque de cada juego.

**B) La cabina física** (en la raíz del repo y en `arduino/`): `contador_arduino.py` lee
`~/.attract/creditos.txt` (el mismo fichero que escribe el plugin del
frontend y que lee `creditos.lua`, documentado en `CLAUDE.md`) y manda el
saldo al Arduino por el puerto serie. `arduino/sandbox.py` es una versión
anterior y más simple del mismo programa, que se conserva como banco de
pruebas. `pantalla.py` y `patron.py` no tienen nada que ver con créditos: son
utilidades para la pantalla CRT de la cabina (conmutar el monitor, pintar un
patrón de calibración).

Ningún script de este documento se ejecuta *dentro* de MAME: todos corren como
procesos Python normales, fuera del emulador. Eso es deliberado en varios de
ellos (`puntajes.py` lo dice explícitamente en su docstring): así no dependen
de la versión de Lua del emulador y se pueden lanzar con la cabina apagada.

---

## 2. `creditos/puntajes.py` — el programa central de puntuaciones

### 2.1 Propósito y cuándo se usa

Traduce las tablas de puntuación que MAME guarda para cada juego (en el
fichero `.hi` del plugin `hiscore`, o en la memoria persistente NVRAM/EEPROM
de la placa) a un JSON legible por otro programa. Es la pieza que cierra el
ciclo: MAME guarda bytes crudos, `puntajes.py` los convierte en
`{"puesto": 1, "nombre": "ABC", "puntos": 50000}`.

Se usa de dos formas: **en producción**, sin argumentos, para regenerar
`~/.attract/puntajes.json` cada vez que se quiere consultar el estado de las
tablas; y **en modo herramienta**, con `--detectar`/`--proponer`/`--fabrica`/
`--capturar`/`--listar`, cuando se está dando de alta un juego nuevo o
depurando por qué uno no descifra.

### 2.2 Uso: línea de comandos

```
./puntajes.py                      todos los juegos que tengan datos
./puntajes.py pacman 1943          solo esos
./puntajes.py --listar             qué se sabe decodificar y qué no
./puntajes.py --capturar defecto   apunta la tabla ACTUAL como la de fábrica
```

Argumentos (vía `argparse`, con `add_help=False` porque el `-h`/`--help` se
gestiona a mano para poder imprimir el docstring completo del módulo en vez del
formato automático de argparse):

| Argumento | Qué hace |
|---|---|
| `juegos` (posicional, `nargs="*"`) | lista de sets de MAME; si se omite, se usan todos los "disponibles" |
| `--listar` | no descifra para exportar: solo informa de qué juego descifra y de cuál no |
| `--detectar` | ejecuta el heurístico automático de formato y **propone** líneas de receta por pantalla, sin escribir nada |
| `--proponer` | como `--detectar`, pero **añade** la mejor propuesta de cada juego sin receta a `puntajes.dat` (marcada `confirmado=no`) |
| `--fabrica` | arranca cada juego en MAME y vuelca de la RAM su tabla "de fábrica" (antes de que nadie juegue) |
| `--mame RUTA` | el ejecutable de MAME a usar con `--fabrica` |
| `--roms RUTA` | el `rompath` a usar con `--fabrica` (si no, se le pregunta a MAME) |
| `--capturar` | congela la tabla de fábrica **descifrada** como base de comparación, en `puntajes_defecto.json` |
| `--salida RUTA` | dónde escribir el JSON final (por defecto `~/.attract/puntajes.json`, o la variable de entorno `SALIDA`) |
| `--hi RUTA` | carpeta donde el plugin `hiscore` deja los `.hi` (si no, se autodetecta) |
| `--nvram RUTA` | carpeta con la memoria persistente de MAME (por defecto `~/.mame/nvram`; sirve para descifrar un volcado traído de otra máquina) |
| `--hi2txt RUTA` | carpeta `db/` de hi2txt-xml |

Ficheros que lee: `hiscore.dat` (de MAME), `puntajes.dat` (recetas propias),
`puntajes_fabrica.json`, `puntajes_defecto.json`, los `.hi` del plugin
`hiscore`, la carpeta de NVRAM de MAME, y opcionalmente los XML de
`hi2txt-xml`. Ficheros que escribe: `puntajes_fabrica.json` (con `--fabrica`),
`puntajes.dat` (con `--proponer`, solo añade), `puntajes_defecto.json` (con
`--capturar`), y el JSON de salida (por defecto `~/.attract/puntajes.json`).

### 2.3 Rutas: cómo se encuentran los ficheros de MAME sin suponerlos

**`mame_opcion(clave, mame=None)`.** Le pregunta a MAME el valor de una opción
de su `.ini` ejecutando `<mame> -showconfig` y buscando la línea
`^<clave>\s+(.*)$` con una expresión regular. Prueba en orden: el binario
pasado explícitamente, `~/.local/share/groovymame-cabina/mame` (donde
`instalar.sh` compila el GroovyMAME parcheado), `groovymame` y `mame` del
`PATH`. Si un candidato no existe o falla al ejecutarse (`OSError`,
`subprocess.SubprocessError`), simplemente prueba el siguiente. El valor se
devuelve con `os.path.expandvars(os.path.expanduser(...))` porque
`-showconfig` da el valor **crudo** del `.ini`: en GroovyArcade, por ejemplo,
`hi_path` está escrito como `$HOME/shared/...` sin expandir. Es la misma
técnica que usan `instalar.sh` y `videos.sh` en Bash, aquí traducida a Python.

**`ruta_hi()`.** Dónde deja el plugin `hiscore` sus ficheros `.hi`. La fuente
de verdad es `<homepath>/hiscore` (así lo escribe el plugin moderno,
`init.lua`, función `get_data_path`). Construye una lista de candidatos, en
este orden:

1. `<homepath>/hiscore`, con `homepath` sacado de `mame_opcion("homepath")`.
2. `~/.mame/hiscore` (por si el `homepath` no se pudo consultar).
3. Lo que diga `hi_path` dentro de `~/.mame/hiscore.ini`, si ese fichero
   existe — **pero esto es del plugin viejo y hoy no lo lee nadie**; se deja
   como candidato de más baja prioridad a propósito.
4. `~/.mame/hi` (otro nombre histórico).

Después recorre los candidatos y devuelve el **primero que sea una carpeta y
contenga al menos un `.hi`**; si ninguno tiene `.hi` todavía, devuelve el
primero que exista como carpeta (aunque esté vacía), o `None` si no hay
ninguna. Esta función existe porque `hiscore.ini` mintió una vez (ver
`CLAUDE.md`, «el `hi_path` es de otro plugin») y llevó a creer que la cabina no
había rescatado ninguna puntuación cuando en realidad estaban en otro sitio.

**`ruta_hiscore_dat()`.** Prueba cuatro rutas fijas donde puede estar
`hiscore.dat` (la copia local del repo primero, luego las típicas de Debian y
GroovyArcade) y devuelve la primera que exista, o `None`.

### 2.4 Los dos ficheros `.dat` que da de comer al programa

**`leer_hiscore_dat(ruta)` → `{juego: [(cpu, espacio, dirección, longitud), ...]}`.**
Parsea el fichero de MAME línea a línea. Su formato es:

```
pacman:
@:maincpu,program,4e6e,3,0,0
```

Una línea que termina en `:` abre un grupo de nombres (puede haber varios
alias seguidos apuntando al mismo bloque, típico de clones); una línea que
empieza por `@` añade un bloque de memoria `(cpu, espacio, dirección_hex,
longitud_hex)` a **todos** los nombres pendientes del grupo actual. Cualquier
otra línea no vacía cierra el grupo (limpia `pendientes`).

Dos trampas ya resueltas, explícitas en el propio código:

- Los comentarios `;` se quitan con `linea.split(";")[0]` **antes** de mirar si
  la línea acaba en `:`, porque hay entradas como `pacmini:  ; missing` que sin
  esto no se reconocían como apertura de grupo y dejaban al juego siguiente sin
  ningún bloque.
- Las líneas en blanco también cierran el grupo (`if not linea: continue` las
  salta, pero como no resetea `pendientes`... en realidad el corte de grupo lo
  hace únicamente el `else` final y las líneas con contenido que no son ni
  `:` ni `@`; las líneas vacías se descartan con `continue` sin tocar el
  estado). El propio comentario del código avisa: sin cerrar el grupo a
  tiempo, un juego heredaba los bloques de **todos** los anteriores (Donkey
  Kong salía con 32 KB de bloque en vez de 179 bytes).

**`leer_puntajes_dat(ruta)` → `{juego: {clave: valor}}`.** Mismo espíritu que
`creditos.dat`: una línea por juego, primer token es el nombre del set, el
resto son pares `clave=valor` separados por espacios. Quita comentarios con
`re.sub(r"#.*$", "", linea)`. Si el primer token contiene un `=` (indicio de
que a la línea le falta el separador, el mismo fallo mudo que ya mordió en
`arranque.dat` con `pacman?arranque=5`), avisa por `stderr` y descarta la
línea en vez de crear un juego fantasma con ese nombre.

El formato de `puntajes.dat`, documentado en su propia cabecera (y ampliado
por lo que usa el código):

| Clave | Significado |
|---|---|
| `bloque=N` | cuál de los bloques de `hiscore.dat` lleva la tabla (0 = el primero, el caso normal) |
| `entradas=N` | cuántas posiciones tiene la tabla |
| `bytes=N` | cuánto ocupa cada entrada, en bytes |
| `puntos=O,L,F` | desplazamiento, longitud y formato del campo de puntuación **dentro de cada entrada** |
| `nombre=O,L,F` | desplazamiento, longitud y alfabeto de las iniciales, si van intercaladas en la misma entrada |
| `nombres=O,L,F` | igual, pero para juegos que NO intercalan: todas las puntuaciones van seguidas y luego, en otro bloque, todos los nombres (Atari Tetris). `O` es el desplazamiento **absoluto** de ese segundo bloque |
| `nivel=O,L` | opcional: dónde vive la ronda/fase alcanzada, si el juego la guarda junto a la puntuación |
| `multiplica=N` | opcional: si el juego guarda la puntuación dividida por N (típicamente 10, porque el último cero se omite) |
| `orden=asc` | opcional: la tabla está guardada de menor a mayor (Kung-Fu Master); sin esto se asume mayor a menor |
| `swap=N` | opcional: los bytes vienen intercambiados por parejas de N (placas de 16 bits, ver más abajo) |
| `rotar=N` | opcional: el bloque empieza N bytes más allá de donde dice `hiscore.dat`, y lo que sobra por delante da la vuelta al final (New Rally-X) |
| `desde=0xNN` | opcional: desplazamiento absoluto del bloque, ignorando lo que diga `hiscore.dat` (para NVRAM, o para un `.hi` cuya tabla no empieza al principio, como Tekken) |
| `fuente=hi\|nvram\|<nombre>` | opcional: fuerza a leer de una fuente concreta, ignorando el resto |
| `confirmado=si` | la receta se comparó con lo que el juego enseña en pantalla y es exacta |

### 2.5 Los formatos de puntuación y de nombre

**`campo(spec)` → `(offset, longitud, formato)`.** Parsea una cadena tipo
`"0,3,bcd"` partiéndola por comas; el tercer elemento es opcional (cadena
vacía si falta).

**`texto(datos, modo)` → cadena.** Decodifica un nombre/iniciales:

- `"ascii"`: cada byte se pasa por `chr()` si está en el rango imprimible
  (32–126), si no se sustituye por un espacio; el resultado se recorta
  (`strip()`).
- `"idx:<alfabeto>"`: cada byte es un **índice** dentro de una tabla de
  caracteres propia de la placa, no un código ASCII. `<alfabeto>` busca
  primero en el diccionario `ALFABETOS`; si no está ahí, la propia cadena que
  sigue a `idx:` se usa directamente como tabla (para alfabetos ad-hoc que no
  merece la pena nombrar).

El diccionario `ALFABETOS` trae cuatro tablas deducidas a mano:

- `"namco"` — dígitos 0-9 en `0x00`, mayúsculas en `0x0a`, 18 huecos (espacio)
  en `0x24`, minúsculas en `0x36` y el punto en `0x50`. Se dedujo de
  `"M.Nakamura"`, el nombre que trae de fábrica Xevious.
- `"snk"` — el byte es directamente el índice de letra, `0x00` = `'A'`.
- `"capcom"` — dígitos, luego letras, luego puntuación, empezando en `0x00`.
- `"dkong"` — dígitos en `0x00`, seis bytes de relleno (el carácter `·`
  repetido, deducido de los sufijos ordinales `ST/ND/RD/TH/TH` que Donkey Kong
  guarda junto al puesto), espacio en `0x10` y letras desde `0x11`.

**`numero(datos, modo)` → entero.** Decodifica la puntuación:

- `"bcd"`: BCD empaquetado, dos dígitos decimales por byte. El truco está en
  `int(datos.hex())`: `datos.hex()` convierte cada byte a **dos caracteres
  hexadecimales**, y como en BCD válido esos nibbles son siempre `0`-`9`, la
  representación hexadecimal y la decimal son el mismo texto — así que
  interpretar esa cadena como un entero en base 10 da directamente el número
  BCD sin tener que desempaquetar nibble a nibble. Es una equivalencia, no una
  coincidencia: `bytes([0x00, 0x30, 0x00]).hex()` es `"003000"`, y
  `int("003000")` es `3000`.
- `"texto"`: los dígitos están escritos como caracteres ASCII (`"007000"`
  literal, byte a byte). Se decodifica con `.decode("ascii", "ignore")`,
  se comprueba que **todo** sea numérico (`.isdigit()`) y si no, se lanza
  `RecetaNoEncaja` — importante porque de lo contrario un campo que no es
  texto numérico daría un `ValueError` distinto y no encajaría con el
  contrato de la función.
- `"digitos"`: **un dígito decimal por byte entero** (no BCD): cada byte vale
  0-9 y se concatena como texto (`"".join(str(b) for b in datos)`). Es el
  formato que usan las placas que malgastan un byte entero para guardar medio
  dígito.
- `"bcdle"`: BCD pero con el byte menos significativo primero; se invierte la
  cadena de bytes (`datos[::-1]`) y se aplica el mismo truco de `int(...hex())`.
- `"le"` / `"be"`: entero binario normal, `int.from_bytes(datos, "little"/"big")`.

Cualquier `ValueError` que surja al convertir (por ejemplo, un nibble fuera de
0-9 en BCD, que hex() sigue representando como letra a-f y por tanto
`int(...)` en base 10 falla) se relanza como `RecetaNoEncaja` con el byte
crudo en el mensaje, para que el llamador sepa que **esta receta concreta no
sirve para estos datos**, sin abortar el programa entero.

**`class RecetaNoEncaja(Exception)`.** Señal específica de "esta receta no
sabe leer estos bytes". No es un fallo del programa: pasa sobre todo con las
propuestas automáticas del detector, que se dedujeron de una tabla y pueden no
encajar al aplicarlas sobre otra. El código que la captura simplemente marca
ese juego como no descifrable y sigue con los demás.

**`descifrar(datos, cfg)` → lista de `dict`.** El núcleo de la traducción
byte→tabla, usado por el camino de receta propia (no por hi2txt, que tiene su
propio intérprete). Recibe el bloque de bytes ya recortado a la tabla y el
diccionario de configuración de ese juego (`cfg`, tal como lo dejó
`leer_puntajes_dat`). Pasos:

1. Lee `entradas` (n), `bytes` (ancho de cada entrada), y descompone
   `puntos=`/`nombre=` con `campo()`.
2. Si hay `nombres=` (bloque de nombres separado), lo guarda aparte en `par`.
3. `mult = multiplica` (por defecto 1).
4. Decide el orden de recorrido: normalmente `range(n)` (entrada 0 primero =
   mejor puntuación); si `orden=asc`, recorre `range(n-1, -1, -1)` — es decir,
   lee la tabla **del final hacia el principio**, para que la posición 1 que
   se reporta siga siendo siempre la mejor puntuación aunque la placa la
   guarde al revés.
5. Para cada entrada `i` (en el orden que toque), recorta
   `e = datos[i*ancho:(i+1)*ancho]`; si sobran menos bytes de los que mide una
   entrada completa, **corta el bucle ahí** (`break`) — no falla, simplemente
   deja de producir filas cuando el bloque se queda corto.
6. Construye la fila: `puesto` (1-indexado según el orden ya resuelto),
   `puntos` (vía `numero()` sobre el campo de puntuación, multiplicado por
   `mult`), `confirmado` (booleano, de `cfg.get("confirmado", "no") == "si"`).
7. El nombre sale de tres sitios posibles, en este orden de preferencia: si
   hay bloque `nombres=` separado (`par`), lo lee de
   `datos[base + i*largo : base + (i+1)*largo]` (nótese que aquí se indexa
   sobre `datos` completo, no sobre `e`, porque el bloque de nombres vive fuera
   de las entradas de puntuación); si no, y hay `nombre=` dentro de la entrada,
   lo lee de `e[on:on+ln]`.
8. Si hay `nivel=`, lo añade con un truco: `campo(cfg["nivel"] + ",,")` —
   como `campo()` espera tres componentes separadas por coma y `nivel=` solo
   trae dos (`offset,longitud`), se le añade una coma extra a mano para que el
   `split(",")` no falle; el tercer valor (formato) se descarta con `_`, y el
   valor se lee siempre como entero grande-endian (`int.from_bytes(..., "big")`),
   sin pasar por `numero()`.
9. Guarda `crudo` (los bytes de la entrada en hexadecimal), útil para depurar
   a mano una receta que no cuadra.

### 2.6 El detector automático de formato

Esta sección del código (comentada extensamente en el propio fichero) resuelve
un problema distinto: **cuando nadie ha escrito todavía una receta**, ¿se
puede adivinar el formato mirando solo los bytes? La respuesta es "casi", y
solo sirve para **proponer**, nunca para dar por buena una receta sin que un
humano la compare con la pantalla del juego.

**`FORMATOS`** es la lista de formatos candidatos a probar, cada uno con un
rango de longitudes de campo razonable: `("bcd", 2, 4)`, `("bcdle", 2, 4)`,
`("digitos", 4, 8)`, `("be", 2, 4)`, `("le", 2, 4)`.

**`_descendente(v)`** — `True` si la lista está ordenada en cualquiera de los
dos sentidos (todo no-creciente, o todo no-decreciente). Hace falta porque no
todas las placas guardan el récord primero: Kung-Fu Master lo guarda al
revés.

**`_valido(trozo, fmt)`** — filtro barato **antes** de intentar decodificar:
para `"digitos"`, ningún byte puede pasar de 9; para `"bcd"`/`"bcdle"`, ningún
nibble puede ser A-F. Sin este filtro previo, el detector proponía leer como
BCD campos que no lo eran, y el resultado parecía un número plausible pero
mal (documentado: "15000 leído como 10500").

**`_plausible(puntos)`** — descarta lo que no puede ser una tabla de
puntuaciones ya decodificada: si el máximo es ≤ 0 (nadie puntúa nunca); si la
primera posición pasa de 99.999.999 (ninguna recreativa llega ahí); si **todos
los valores son iguales y positivos**, se acepta directamente (es el patrón
típico de una tabla de fábrica sin jugar: todas las posiciones a 20000, por
ejemplo); en cualquier otro caso, exige que esté ordenada (`_descendente`).

**`_nombre_posible(datos, w, n, prohibido)`** — busca, dentro del ancho de
entrada `w`, un desplazamiento de 3 caracteres que parezca iniciales. Prueba
los alfabetos `"ascii"` e `"idx:capcom"` en cada desplazamiento posible (salvo
los que se solapan con el campo de puntuación ya elegido, vía `prohibido`).
Cuenta cuántas de las `n` entradas producen algo "útil" (alfanumérico, con
espacio, punto o guion permitidos, y no vacío); si al menos la mitad de las
entradas (o 2, lo que sea mayor) lo cumplen, se queda con ese desplazamiento.
Devuelve `(nota, desplazamiento, alfabeto)` o `None`.

**`detectar(datos)` → lista de candidatos, el mejor primero.** El bucle
central: para cada número de entradas `n` entre 3 y 20 que **divida
exactamente** la longitud total (`L % n == 0`) y dé un ancho de entrada `w`
entre 4 y 64 bytes; para cada formato candidato y cada longitud de campo de
puntuación dentro de su rango; para cada desplazamiento posible dentro de la
entrada: extrae el campo de las `n` entradas, comprueba `_valido` en todas,
decodifica con `numero()`, filtra con `_plausible()`, y busca un campo de
nombre con `_nombre_posible()`. Si sobrevive todo eso, calcula una **nota**
heurística que combina:

- `n*2 + lp` (premia tablas más largas y campos más anchos);
- `+12` si todos los valores son múltiplos de 10 (casi toda recreativa
  puntúa así);
- `-12` si el máximo pasa de un millón (síntoma típico de haber leído 4 bytes
  como un entero binario grande sin sentido);
- `-10` si el máximo **no llega** a 1000 (para no confundir la tabla de
  puntuaciones con el campo de "ronda alcanzada", que también va ordenado);
- `+3` por cada valor distinto (una tabla de fábrica con relleno repetido
  puntúa menos que una con valores variados, salvo que ya haya pasado el
  filtro de "todos iguales" de `_plausible`);
- `+4` si además de ordenada tiene más de un valor distinto;
- la nota del nombre encontrado, si lo hay.

Al final ordena todos los candidatos por nota descendente y **quita
duplicados** que solo difieren en el formato pero producen exactamente los
mismos valores decodificados (mismo `(entradas, bytes, valores)`).

**`region_util(datos, margen=16)`** — para un fichero de NVRAM (kilobytes,
casi todo ceros o `0xff`), acota la zona que tiene contenido de verdad:
localiza el primer y el último byte que no sean `0x00` ni `0xff`, y devuelve
ese rango con un margen. Barrer el fichero entero sería caro y encontraría
basura por todas partes.

**`detectar_en_ventana(datos, tope=2048)`** — la versión de `detectar()` para
cuando la tabla **no** ocupa el bloque entero (el caso típico de la NVRAM: la
tabla es un rincón de un fichero de muchos kilobytes, y no tiene sentido
exigir que la longitud total se divida exactamente entre el número de
entradas). Primero acota con `region_util()` y recorta a `tope` bytes si hace
falta. Luego, para cada ancho de entrada `w` (4 a 32) y cada combinación de
formato/longitud/desplazamiento, lee **de una sola pasada** todos los valores
de esa rejilla a lo largo de todo el bloque (en vez de llamar a `detectar()`
en cada posición posible, que el propio comentario dice que sería inviable —
"minutos por fichero"). Luego busca **tramos contiguos** de esa secuencia que
no suban (candidatos a tabla real), de longitud entre 4 y 12, exigiendo además
que tengan al menos 3 valores distintos y que no sean "basura" (repetición de
`0xffff`/`0xffffff`, o más de un cero — patrones típicos de memoria borrada).
Calcula una nota parecida a la de `detectar()` y devuelve los 6 mejores
candidatos únicos, cada uno con su desplazamiento absoluto (`desde`) dentro
del fichero original.

### 2.7 El grueso: elegir la fuente, descifrar, marcar lo de fábrica

**`VERIFICADOS`** — conjunto fijo de sets cuya receta **se ha comparado con lo
que el juego enseña en pantalla**. Solo estos se marcan `confirmado=True`
cuando la receta viene de hi2txt (para las recetas propias, `confirmado` sale
directamente de la clave `confirmado=si` de `puntajes.dat`).

Variables de estado a nivel de módulo, todas mutadas desde `main()`:
`DB_HI2TXT` (carpeta de XML, o `None`), `DIR_NVRAM` (por defecto
`~/.mame/nvram`), `FABRICA` (dict del `puntajes_fabrica.json` cargado),
`_BLOQUES`/`_RECETAS` (copias de `bloques`/`recetas` para que
`_defecto_de_fabrica()` pueda usarlas sin que se le pasen como argumento en
cada llamada).

**`_recortar(filas)`** — quita del final de la lista las filas cuya
`puntos` sea "falsy" (0 o ausente): son relleno de la estructura, no
puntuaciones.

**`_cortar_donde_deja_de_ordenar(filas)`** — cuando el XML/receta declara más
posiciones de las que la tabla tiene de verdad, lo que sobra detrás no son
puntuaciones (son bytes de otra cosa, o basura). Con menos de 3 filas, no hay
nada que cortar. Si hay 3 o más:

1. Decide el sentido de la tabla (`baja`) por **mayoría** de los pares
   consecutivos, no por el primer par — si justo la segunda posición se
   descifra mal, mirar solo las dos primeras daría el sentido equivocado.
2. Busca la **subsecuencia más larga que respete ese orden**, con una
   programación dinámica clásica de tipo "subsecuencia creciente/decreciente
   más larga" (`mejor_hasta[i]` = longitud de la mejor cadena que termina en
   `i`; `previo[i]` para reconstruirla). Esto es preferible a cortar en el
   primer fallo, porque **descarta las filas sueltas que rompen el orden en
   vez de tirar todo lo que viene después de la primera** (el caso
   documentado: Mortal Kombat tenía 15 posiciones, solo 2 estaban mal, y
   cortar en la primera habría tirado las 13 buenas de detrás).
3. Si el número de filas descartadas por este método es mayor que 0 pero no
   pasa de un cuarto del total (y quedan al menos 3), se queda con esa
   subsecuencia "casi perfecta". Si el desajuste es mayor, **vuelve al corte
   seco**: se queda con el primer tramo continuo que respeta el orden desde
   el principio (`while fin < len(p) and encaja(p[fin-1], p[fin]): fin += 1`)
   — este es el comportamiento que mantiene limpias las tablas donde de verdad
   sobran muchas posiciones de relleno.

**`VACIA`** — constante de texto usada como "motivo" especial: significa que
la receta **funciona** pero la tabla decodificada sale entera a cero, porque
nadie ha jugado todavía. Se distingue de "no se pudo descifrar" para que esos
juegos no figuren como fallidos en los informes.

**`_parece_tabla(filas)`** — el último filtro antes de aceptar un descifrado
como bueno (se aplica tanto a resultados de hi2txt como a los de receta
propia... en realidad solo se aplica al camino de hi2txt, ver más abajo).
Rechaza si la lista está vacía o tiene más de 64 filas (el tope de 64, y no
40, existe porque Alien vs Predator tiene una tabla real de 49 posiciones).
Rechaza si el máximo es ≤ 0. Exige que la lista esté ordenada en un sentido o
en el otro (`baja` o `sube`, calculados a pelo con comprensiones de lista, sin
reutilizar `_descendente`).

**`candidatos_de(juego, cfg, dir_hi, fabrica=None)` → `(lista_de_(bytes, origen), aviso)`.**
Decide de qué fichero(s) sacar los bytes, y en qué orden probarlos. Hay tres
tipos de fuente posibles: el `.hi` que escribe el plugin `hiscore`; la tabla
"de fábrica" que `--fabrica` volcó de la RAM (sirve de sustituto del `.hi`
mientras nadie ha jugado); y cualquier fichero de la carpeta
`<DIR_NVRAM>/<juego>/` (nvram, saveram, eeprom, earom, x2212, at28c16...).

El orden de preferencia lo dice el propio XML de hi2txt
(`hi2txt.fuentes_declaradas(...)`, función que devuelve la lista de
`<structure file="...">` declarados para ese juego, ya resolviendo redirecciones
`<sameas>`). Si el XML no dice nada (`quiere` vacío), se prueba `.hi` primero y
luego **cualquier fichero suelto** que haya en la carpeta de NVRAM de ese
juego — esto último únicamente cuando el XML no declaró nada, porque si el
XML sí pide una fuente concreta y esa fuente no está, leer un fichero
cualquiera "porque estaba ahí" da datos garantizadamente equivocados sin
avisar (el caso documentado de Arkanoid, que pasaba a marcar 0 en vez de
50000 leyendo su NVRAM en lugar de su `.hi`).

`leer(ruta)` (función anidada) abre el fichero si existe y no está vacío, y lo
descarta (devuelve `None`) si **todo** el contenido es `0x00` o **todo** es
`0xFF` — memoria que la placa nunca ha escrito de verdad (el caso de
Centipede, cuya `earom` sin usar son 64 bytes a `0xFF`).

Al final, si hay un `.hi` de verdad entre los candidatos recogidos, se
**reordena para que vaya siempre primero**, sin importar lo que diga el XML:
es la fuente canónica porque es la que produce el rescate. La razón concreta
está documentada con Berzerk: su NVRAM guarda cada byte partido en dos mitades
y da un número plausible pero equivocado; el `.hi` da el valor real.

**`puntajes_de(juego, bloques, cfg, dir_hi)` → `(filas, origen, aviso)`.**
Envoltorio de alto nivel: pide los candidatos con `candidatos_de()` y **prueba
cada fuente hasta que una descifre**, en vez de quedarse con la primera que
tenga bytes (razón documentada: la NVRAM de Golden Axe tiene bytes de verdad
pero son la fuerza de los personajes, no puntuaciones; el `.hi` al lado sí
tiene la tabla). Si ninguna decodifica, devuelve el mejor "aviso" que se haya
recogido por el camino.

**`_descifrar_fuente(juego, bloques, cfg, datos, origen)` → `(filas, origen, aviso)`.**
El intento de descifrado sobre **una** fuente concreta. Primero intenta
hi2txt, si `DB_HI2TXT` está configurado y existe el XML de ese juego:

1. Llama a `hi2txt.puntuaciones(xml, datos, fuente)`, traduciendo `origen`
   ("hi"/"fabrica" → `".hi"`, cualquier otro nombre se pasa tal cual, porque
   así es como hi2txt distingue de qué fichero viene el dato).
2. Comprueba si el resultado es "vacío" (`max(puntos) <= 0`) **antes** de
   recortar filas vacías del final — el orden importa: si se recorta
   primero, una tabla toda a cero se queda sin ninguna fila y ya no se puede
   distinguir de "no descifra".
3. Aplica `_cortar_donde_deja_de_ordenar(_recortar(filas))`.
4. Si era vacía, devuelve `(None, origen, VACIA)`.
5. Si pasa `_parece_tabla`, marca cada fila con `receta="hi2txt"` y
   `confirmado = juego in VERIFICADOS`, y devuelve el resultado.
6. Cualquier excepción se convierte en un aviso de texto, sin propagar.

Si hi2txt no aplica o no descifra, cae al camino de **receta propia**
(`cfg`, de `puntajes.dat`). Si no hay `cfg` en absoluto, devuelve un aviso
"sin receta" con el tamaño de los datos disponibles. Si hay `cfg`:

1. **`swap=N`**: si N > 1, intercambia los bytes por parejas de N (misma idea
   que el `byte-swap` de hi2txt, para placas de 16 bits que también necesitan
   esto en sus recetas propias, como un NeoGeo leído por `saveram`).
2. **`rotar=N`**: rota el bloque N bytes (`datos[-rot:] + datos[:-rot]`) para
   los casos donde el dígito más significativo está al final en vez de al
   principio (New Rally-X).
3. Calcula el desplazamiento (`desde`) y la longitud (`largo`) del trozo útil:
   - Para fuentes de memoria persistente (`nvram`, `saveram`, `eeprom`,
     `earom`, `x2212`, `at28c16`), no hay bloques de `hiscore.dat` que valgan:
     se usa `desde=` de la receta (o 0 si no está) y el resto del fichero.
   - Si la receta trae `desde=` explícito aunque la fuente sea un `.hi`,
     también manda (para tablas que no arrancan al principio del bloque
     declarado, como Tekken, que empieza en `0xc0`).
   - Si no, se suman las longitudes de los bloques anteriores de
     `hiscore.dat` hasta el índice `bloque=` (por defecto 0) para obtener
     `desde`, y se toma la longitud de ese bloque concreto como `largo`.
4. Si el trozo resultante es más corto que una sola entrada
   (`entradas × bytes`... en realidad la comprobación es contra `cfg["bytes"]`,
   el ancho de **una** entrada), devuelve un aviso explicando que no cabe ni
   una entrada — pero si cabe al menos una, **se descifra lo que haya**
   (el caso de Xevious, cuyo bloque real son 77 bytes y sus 5 entradas de 16
   piden 80: se sacan las que quepan).
5. Llama a `descifrar(trozo, cfg)`; si lanza `RecetaNoEncaja`, lo convierte en
   un aviso de texto.

**`datos_de(juego, cfg, dir_hi, fabrica=None)` → `(bytes, origen, aviso)`.**
Atajo para `--detectar`/`--proponer`: solo necesita **algunos** bytes con los
que jugar (no le importa descifrarlos todavía), así que se queda con el
**primer** candidato de `candidatos_de()`.

**`marcar_defectos(juego, filas, defectos)` → filas (mutadas in-place, y
devueltas).** Añade a cada fila un campo `defecto` (`True`/`False`/`None`):
compara `(nombre, puntos)` contra la base de "tabla de fábrica" de ese juego.
Esa base se **deduce primero** (`_defecto_de_fabrica`, ver abajo) y solo si
eso falla se usa el fichero `puntajes_defecto.json` capturado a mano en el
pasado. Si no hay base de ningún tipo, marca `None` ("no se sabe"), nunca
asume que es real ni que es de fábrica sin datos.

**`_defecto_de_fabrica(juego)` → lista de `[nombre, puntos]` o `None`,
cacheada en `_CACHE_FABRICA`.** Calcula la tabla de fábrica **descifrándola**
con las recetas de hoy, en vez de fiarse de un volcado capturado hace tiempo
(que envejece: la razón documentada es que `puntajes_defecto.json` tenía una
entrada de `mvsc` de cuando ese juego aún no tenía receta, y quedaba marcando
como "de fábrica" una partida real). Dos casos que devuelven `None` sin
intentar nada:

- Si el juego **tiene** una carpeta en `DIR_NVRAM`: significa que tiene
  memoria persistente propia, y esa memoria carga las puntuaciones guardadas
  al arrancar **aunque se apaguen los plugins** — no hay forma fiable de saber
  cuál era la tabla de fábrica (Berzerk sigue mostrando los puntos reales de
  Eloy porque están en su NVRAM). Es preferible decir "no se sabe" que marcar
  una puntuación real como falsa.
- Si no hay volcado de fábrica (`FABRICA.get(juego)` es `None`).

Si hay volcado, lo decodifica con `_descifrar_fuente(juego, ..., "fabrica")` y
construye la lista `[nombre, puntos]` por fila. Cualquier excepción se traga y
devuelve `None`.

**`capturar_fabrica(juegos, bloques, mame, rompath)` → `{juego: hex}`.**
Arranca cada juego en MAME de verdad para volcar su tabla de fábrica de la
RAM. Hace falta porque el plugin `hiscore` **solo** escribe su `.hi` cuando la
tabla cambia respecto a como estaba al arrancar — un juego que nadie ha
jugado nunca deja fichero, así que sin esto no hay ni receta que deducir ni
base de fábrica con la que comparar.

Para cada juego con bloques conocidos en `hiscore.dat`, construye la variable
de entorno `GA_D_BLOQUES` (formato `cpu,espacio,dir_hex,largo_hex;...`, uno
por bloque, quitando los `:` iniciales del nombre de CPU) y `GA_D_FRAME=1800`,
y lanza:

```
mame <juego> -rompath <roms> -noplugins -video none -sound none
     -noswitchres -str 45 -nothrottle -skip_gameinfo
     -autoboot_script volcar.lua -autoboot_delay 0
```

`-noplugins` es **imprescindible**: sin él, el propio plugin `hiscore`
reinyectaría en la RAM la puntuación guardada de la sesión anterior, y lo que
se volcaría no sería la tabla de fábrica sino el récord restaurado (el caso
documentado: Pac-Man, cuya tabla de fábrica real es 0, salía marcando 48800 de
una partida real). El script Lua auxiliar (`volcar.lua`, no es Python, pero
es su contraparte necesaria) espera al frame 1800, vuelca los bloques pedidos
en hexadecimal por `stdout` como `[volcado] <hex>` y sale.

`capturar_fabrica` busca esa línea con una expresión regular
(`r"^\[volcado\] ([0-9a-f]*)$"`) en la salida capturada; si no aparece,
distingue por el contenido si "faltan roms" (busca `NOT FOUND|missing|Fatal
error` en la salida) o simplemente "sin volcado" por otro motivo, y sigue con
el siguiente juego (`timeout=180` segundos por juego, capturado con
`subprocess.run`).

**`_fabrica_disponible()` → lista de juegos.** Lee las claves de
`puntajes_fabrica.json` directamente (sin pasar por el resto del programa),
porque hace falta construir la lista de "juegos disponibles" antes de que el
resto del `main()` cargue ese fichero por completo.

### 2.8 `main()`: cómo se atan todos los cabos

1. Parsea argumentos (ver 2.2). Si `--help`, imprime el docstring del módulo y
   sale con código 0.
2. Resuelve `hiscore.dat` (`ruta_hiscore_dat()`) y la carpeta de `.hi`
   (`--hi` o `ruta_hi()`); si falta cualquiera de los dos, sale con error.
3. Fija los globales `DIR_NVRAM` (si se pasó `--nvram`) y `DB_HI2TXT`
   (importando `hi2txt` y llamando a `hi2txt.buscar_db([...])`; si el módulo
   no se puede importar, `DB_HI2TXT` queda en `None` y todo el sistema sigue
   funcionando solo con las recetas propias).
4. Carga `bloques` (de `hiscore.dat`) y `recetas` (de `puntajes.dat`), y los
   deja también en los globales `_BLOQUES`/`_RECETAS` para que
   `_defecto_de_fabrica` los pueda usar. Carga `puntajes_defecto.json` si
   existe.
5. Imprime una cabecera informativa (rutas y tamaños de las bases usadas).
6. Construye `disponibles`: la unión de tres conjuntos — juegos con `.hi`
   en la carpeta correspondiente, juegos con tabla de fábrica capturada
   (`_fabrica_disponible()`), y subcarpetas de `DIR_NVRAM`. Esto es
   deliberado: mirar solo los `.hi` dejaría la lista casi vacía en la cabina
   real, donde el plugin apenas ha escrito ficheros pero **59 juegos** tienen
   su tabla en memoria persistente o en un volcado de fábrica.
7. `juegos = a.juegos or disponibles`.
8. Carga `puntajes_fabrica.json` en el global `FABRICA`.
9. **Rama `--fabrica`**: resuelve el ejecutable de MAME y el `rompath` (por
   defecto `~/.local/share/groovymame-cabina/mame` y lo que diga
   `mame_opcion("rompath", mame)`); si no se pasaron juegos explícitos, los
   saca de `~/.attract/romlists/groovymame.txt` (una lista `;`-separada,
   descartando la cabecera con `[1:]` y quedándose con el primer campo de
   cada línea). Llama a `capturar_fabrica`, funde el resultado con lo que ya
   hubiera en `puntajes_fabrica.json` y lo vuelve a guardar. Termina ahí.
10. **Rama `--proponer`**: para cada juego de `fabrica ∪ disponibles` que
    **no** tenga ya receta en `puntajes.dat`, obtiene bytes crudos (de
    `datos_de`, o directamente del volcado de fábrica), los recorta al
    tamaño del primer bloque de `hiscore.dat` si existe, ejecuta `detectar()`
    y se queda con el mejor candidato. Construye la línea de texto de la
    receta (con `confirmado=no` siempre) y la **añade** al final de
    `puntajes.dat`, precedida de un bloque de comentario explicando que son
    propuestas automáticas sin confirmar y cómo confirmarlas. Imprime un
    resumen (primeras 15 propuestas). Termina ahí.
11. **Rama `--detectar`**: para cada juego pedido, obtiene bytes, ejecuta
    `detectar()` y muestra hasta 4 candidatos con sus valores y la línea de
    receta sugerida, sin escribir nada. Si no hay ningún candidato, avisa de
    que puede que el bloque mezcle tabla y estado (como Asteroid) o que el
    juego guarde una sola puntuación. Termina ahí.
12. **Rama `--listar`**: para cada juego "disponible", llama a la función
    completa `puntajes_de()` (el mismo camino que produce el resultado final,
    a propósito — el propio comentario recuerda el error de medir por una
    ruta y publicar por otra) y clasifica en cuatro cubos: `ok` (descifra),
    `sin_jugar` (descifra pero la tabla está vacía, aviso `VACIA`), `sin`
    (hay datos pero no descifra) y `vacios` (no hay ni datos). Imprime una
    tabla y los resúmenes. Termina ahí.
13. **Camino por defecto** (sin ninguna de las ramas anteriores): para cada
    juego en `juegos`, llama a `puntajes_de()`. Si no descifra, **aun así**
    intenta sacar los bytes crudos con `datos_de()` y los guarda en el
    resultado como `{"descifrado": False, "origen": ..., "motivo": ...,
    "crudo": hex}` — así el JSON final cubre **todos** los juegos desde el
    primer día, y cuando aparezca la receta correcta, la misma entrada pasa a
    traer los puntajes descifrados sin cambiar la forma del fichero. Si
    descifra, guarda `{"descifrado": True, "origen": ..., "puestos":
    marcar_defectos(...)}`.
14. **Rama `--capturar`** (se ejecuta después del bucle anterior, usando
    `bloques`/`recetas` ya cargados): para cada juego con volcado de fábrica
    **y** receta en `puntajes.dat`, decodifica su tabla de fábrica con
    `descifrar()` (no con `_descifrar_fuente`, aquí se hace a mano porque solo
    aplica a recetas propias, no a hi2txt) y la guarda como base en
    `defectos[juego]`. Escribe `puntajes_defecto.json`. Termina ahí — **no**
    llega a escribir el JSON de salida principal.
15. Si no hubo ninguna rama especial: escribe el resultado a `a.salida` de
    forma **atómica** (`tmp = a.salida + ".tmp"`, se escribe ahí y se hace
    `os.replace(tmp, a.salida)`), para que nadie que esté leyendo el fichero
    en ese instante se encuentre un JSON a medias. Después imprime un resumen
    legible por pantalla: por cada juego descifrado, sus primeras 3
    posiciones con la marca `(de fábrica)`/`(?)` si aplica; y, para los que
    tienen datos pero no receta, un aviso con cuántos son y cómo sacarles la
    receta (`--detectar`).

### 2.9 El formato del JSON de salida

```json
{
  "pacman": {
    "descifrado": true,
    "origen": "hi",
    "puestos": [
      {"puesto": 1, "puntos": 48800, "confirmado": true, "crudo": "...", "defecto": false}
    ]
  },
  "juegoquenodescifra": {
    "descifrado": false,
    "origen": "nvram",
    "motivo": "...",
    "crudo": "..."
  }
}
```

`origen` indica de dónde salió el dato (`hi`, `fabrica`, `nvram`, `saveram`,
`eeprom`, `earom`, `x2212`, `at28c16`...). `defecto` es `true`/`false`/`null`
según la comparación con la tabla de fábrica deducida.

---

## 3. `creditos/hi2txt.py` — el intérprete del formato hi2txt-xml

### 3.1 Propósito y cuándo se usa

Implementa **un subconjunto** del formato de descripción de tablas de
puntuación de la base comunitaria [hi2txt-xml](https://github.com/GreatStoneEx/hi2txt-xml)
(GPL-2, ~3.100 juegos descritos). No se copia al repositorio (licencia y
porque se actualiza sola); se descarga aparte y se le indica la ruta a
`puntajes.py` con `--hi2txt <carpeta>/src/main/db`. Este módulo **no se
ejecuta solo**: es una librería que importa `puntajes.py` (y también
`auditar_puntajes.py`).

### 3.2 El formato XML, resumido

```xml
<hi2txt>
  <sameas id="tapper"/>          <!-- opcional: este juego es un alias de otro -->
  <charset id="c1"><char src="0" dst="A"/>...</charset>
  <structure file=".hi">          <!-- o "nvram", "saveram", "eeprom"... -->
    <check><size>179</size></check>
    <loop count="5">
      <elt size="2" type="int" id="SCORE" decoding-profile="bcd"/>
      <elt size="3" type="text" id="NAME" charset="c1"/>
    </loop>
  </structure>
  <output>
    <table>
      <column id="SCORE" format="*10"/>
      <column id="NAME"/>
    </table>
  </output>
</hi2txt>
```

Un `<structure>` describe de qué fichero se lee (`file=`) y su contenido como
una secuencia de `<elt>` (campos sueltos) y `<loop>` (tablas repetidas). Cada
`<elt>` tiene un `size` en bytes, un `type` (`int`, `text` o `raw`) y un `id`
con el que luego se identifica el valor. El bloque `<output>` dice qué
columnas son la tabla "de verdad" (puede haber campos de depuración que no lo
son) y qué transformación (`format=`) se le aplica a cada una.

### 3.3 Utilidades de bajo nivel

**`_entero(txt, defecto=0)`** — convierte texto a entero, aceptando hexadecimal
si empieza por `0x`/`0X`; si falla o `txt` es `None`, devuelve `defecto`.

**`_quitar_nibbles(datos, modo)`** — para `nibble-skip`: cada byte guarda un
solo dígito decimal en un nibble y desperdicia el otro. `modo == "odd"` se
queda con el nibble bajo (`b & 0x0F`); cualquier otro valor, con el alto
(`b >> 4`). Devuelve una **lista de enteros 0-15** (no bytes), uno por byte de
entrada.

**`_intercambiar(datos, paso)`** — invierte el orden de los bytes dentro de
cada grupo de `paso` bytes consecutivos (para `byte-swap`). Igual que la
función homónima de `puntajes.py`, pero implementada de forma independiente
en este módulo.

**`_quitar_bytes(datos, valor)`** — filtra (elimina) todos los bytes iguales a
`valor` de la secuencia (para `byte-trim`/`byte-skip`).

**`BASE40`** — una tabla de alfabeto de 40 caracteres está definida pero
**no se usa en ningún sitio del fichero**: el docstring del módulo menciona
`decoding-profile=base-40` entre lo que "debería" soportarse, pero
`_leer_int` no implementa esa rama (cualquier perfil que no sea `bcd`/`bcd-le`
lanza `NoSeSabe`). Es código muerto / una pieza dejada a medio hacer para un
perfil que, de aparecer en algún XML, hoy no se descifraría.

### 3.4 Decodificar un campo: `_leer_int` y `_leer_text`

**`_leer_int(trozo, elt)` → entero.** Lee el atributo `decoding-profile`, la
`base` (por defecto 10) y si es *little endian*. El orden de aplicación de los
atributos importa:

1. **`byte-trim="0xNN"`**: quita del trozo **todos** los bytes que valgan ese
   relleno, **antes** de nada más. Sin esto el relleno se lee como si fuera
   una cifra más: en Galaga el relleno es `0x24` (el espacio de su propio
   juego de caracteres) y sin quitarlo la puntuación salía como
   `240200000000` en vez de `20000` — un número perfectamente formado y
   completamente falso.
2. **`byte-skip="0xNN"`**: lo mismo, pero para otro atributo del formato (en
   la práctica hace la misma operación de filtrado; el estándar los distingue
   semánticamente, aquí se implementan con la misma función `_quitar_bytes`).
3. **`nibble-skip`**: si está presente, extrae un dígito decimal por nibble
   con `_quitar_nibbles`, invierte el orden si es *little endian*, y devuelve
   **directamente** `int("".join(f"{d:x}" for d in digitos) or "0", 10)` —
   nótese: cada dígito (0-15, aunque en la práctica siempre 0-9) se formatea
   con `{d:x}` (un carácter hexadecimal) y luego el texto resultante se
   interpreta **en base 10**, no en base 16. Esto es a propósito y está
   explicado extensamente en un comentario: el atributo `base="16"` en estos
   XML **no** significa "el valor final es hexadecimal", significa "cada
   nibble es un dígito decimal codificado como si fuera un carácter hex".
   Interpretarlo en base 16 de verdad daba `0x12000 = 73728` donde Mario Bros
   marca `12000`, y `0x10000 = 65536` donde Robotron marca `10000` — afectaba
   a toda la familia Williams.
4. Si `decoding-profile` es `"bcd"` o `"bcd-le"`: invierte el trozo si es
   `bcd-le` o *little endian*. Aquí hay una comprobación extra que no está en
   `puntajes.py`: si **todos** los bytes ya valen 0-9, se trata como si fuera
   un dígito por byte (concatenación de `str(b)`), en vez de como BCD
   empaquetado — porque en esos XML, `decoding-profile="bcd"` **no siempre**
   significa empaquetado de verdad; a veces la placa ya guarda un dígito por
   byte entero, y leerlo como BCD empaquetado multiplicaría el resultado por
   diez mil (el ejemplo documentado: 1943 daba `200000000` en vez de
   `20000`). Si algún nibble se sale de 0-9, se usa el mismo truco de
   `int(t.hex())` que en `puntajes.py`, y si eso falla (`ValueError`, nibble
   A-F) se lanza `NoSeSabe`.
5. Si hay un `decoding-profile` pero no es ninguno de los dos anteriores, se
   lanza `NoSeSabe(f"decoding-profile={perfil}")` — aquí es donde
   `base-40` (u otro perfil no implementado) fallaría explícitamente en vez
   de dar un resultado silenciosamente incorrecto.
6. Sin `decoding-profile`: invierte si es *little endian*; si `base == 16`,
   aplica **el mismo truco** de interpretar el hexadecimal como si fuera
   decimal (`int(t.hex())`), y si eso falla cae a un entero binario de verdad
   (`int.from_bytes(t, "big")`); si `base` es cualquier otro valor, se trata
   siempre como entero binario grande-endian, sin importar qué base se haya
   declarado (no hay soporte real para bases arbitrarias, solo para el caso
   especial 16 = "BCD sin declarar como tal").

**`_leer_text(trozo, elt, charsets)` → cadena.** Busca la tabla de caracteres
por `charset=` en el diccionario `charsets` (construido por `_charsets()`); si
el juego declara `nibble-skip` también para el texto, primero extrae los
nibbles. Para cada byte: si está en la tabla de charset, usa el carácter
mapeado; si no, le suma `ascii-offset` y lo interpreta como ASCII si cae en el
rango imprimible, o espacio si no. El resultado se recorta con `.strip()`.

### 3.5 El recorrido de la estructura

**`_charsets(raiz)` → `{id: {byte_origen: carácter_destino}}`.** Construye,
para cada `<charset id>` del XML, un diccionario que traduce cada `<char
src dst>`.

**`_recorrer(nodo, datos, pos, charsets, filas, sueltos, dentro_bucle=None)` →
posición nueva.** Recorre recursivamente los hijos de `nodo` consumiendo bytes
desde `pos`:

- Para un `<loop count="N" start="S">`: por cada `i` en `range(n)`, crea una
  fila `{"__puesto": desde + i + 1}` (donde `desde` es el atributo `start`,
  por defecto 0) y se recorre recursivamente su contenido, acumulando los
  campos leídos en esa fila (pasada como `dentro_bucle`). El atributo
  `start=` importa porque, sin él, las posiciones se numeran siempre desde 1
  aunque el bloque físico que se está leyendo no sea el principio de la
  tabla: Centipede reparte su tabla en dos sitios (las 3 mejores en su
  `earom`, y de la 4ª a la 8ª en el `.hi`, declarado como
  `<loop count="5" start="3">`), y sin respetar `start` la cuarta posición se
  publicaría como si fuera el récord de la máquina. Si en mitad de una
  iteración del bucle salta `NoSeSabe` (los datos se acabaron antes de
  completar la estructura), se **corta el bucle ahí** (`break`), conservando
  las filas ya completas en vez de descartarlo todo — es el mecanismo que
  permite descifrar "lo que quepa" cuando el XML describe una versión de
  `hiscore.dat` con más campos de los que hay en el volcado real (Xevious).
  Solo se añade la fila si tiene más de la clave `__puesto` (es decir, si
  llegó a leer algo).
- Para un `<elt size type id>`: recorta `tam` bytes desde `pos` y avanza
  `pos`; si no quedan suficientes bytes, lanza `NoSeSabe` (esto es lo que
  activa el `break` del `<loop>` de arriba cuando el bloque se acaba a
  mitad). Si `type="raw"`, simplemente se descartan esos bytes (se consumen
  para mantener la posición correcta, pero no se guarda ningún valor). Para
  `"int"` llama a `_leer_int`, para `"text"` a `_leer_text`; cualquier otro
  tipo lanza `NoSeSabe(f"type={tipo}")`. El valor resultante se guarda con la
  clave `id` en `dentro_bucle` si se está dentro de un `<loop>`, o en
  `sueltos` si es un campo de nivel superior (por ejemplo, el nombre del
  juego grabado una sola vez, fuera de cualquier tabla).

### 3.6 Elegir la estructura correcta y seguir redirecciones

**`_estructuras(raiz, datos, fuente)` → lista de nodos `<structure>`
candidatos, ordenados.** Filtra por `file=` (comparando con `fuente`, con el
caso especial de que `fuente == "hi"` también encaja con `file=".hi"`, el
valor por defecto). Clasifica en tres grupos según si declaran un
`<check><size>` que **coincide exactamente** con `len(datos)` (`con_tam`), no
declaran tamaño en absoluto (`sin_tam`), o declaran un tamaño que **no**
coincide (`resto`) — y devuelve `con_tam + sin_tam + resto`, es decir,
probando primero las que encajan de tamaño, luego las que no dicen nada, y
solo al final las que dicen un tamaño distinto (por si acaso encajan igual).

**`_elegir_estructura(raiz, datos, fuente)`** — una función parecida, más
simple (se queda solo con la primera estructura exacta, o la primera sin
tamaño, o la primera de todas), que está **definida pero no se llama desde
ningún sitio** del módulo: quedó como código muerto, sustituida por el bucle
de `descifrar_con_xml` que prueba **todas** las candidatas de `_estructuras`
hasta que una funcione, en vez de comprometerse con una sola elegida de
antemano.

**`resolver(ruta_xml, saltos=8)` → `(ruta_final, raíz_XML)`.** Sigue la cadena
de `<sameas id="otro"/>` (redirecciones a otro fichero XML que describe la
misma estructura) hasta encontrar un XML sin redirección, hasta 8 saltos. Esto
**no es un caso raro**: 2322 de los 3102 XML de la base son puras
redirecciones (clones y variantes que comparten estructura con el original,
p. ej. `rbtapper → tapper → journey`). Detecta bucles (un `id` de destino ya
visitado) y ficheros inexistentes o ilegibles, lanzando `NoSeSabe` en ambos
casos.

**`descifrar_con_xml(ruta_xml, datos, fuente=None)` → `(filas, sueltos)`.**
Resuelve la redirección, comprueba que el XML tenga al menos un
`<structure>` (si no, `NoSeSabe("ese juego aun no tiene estructura descrita")`).
Obtiene las estructuras candidatas con `_estructuras()` y las prueba **todas
en orden**, no solo la primera: para cada una, aplica `byte-swap` si lo
declara (`_intercambiar`) y llama a `_recorrer`. Si una estructura lanza
`NoSeSabe`, se recuerda como `ultimo` y se prueba la siguiente — esto es lo
que permite recuperar un juego cuando el XML describe **varias versiones**
de `hiscore.dat` (por ejemplo, distintas revisiones de MAME) y solo una de
ellas encaja con los datos reales instalados (el caso documentado: `tmnt`,
`xevious` y `galaxian` se recuperaron así). En cuanto una produce `filas` o
`sueltos` no vacíos, se devuelve. Si ninguna funciona, se relanza el último
error (o uno genérico).

### 3.7 Presentación: formatos, columnas y orden

**`_formatos(raiz)` → `{id: (multiplicador, suma)}`.** Lee cada `<format id>`
del XML (con `raiz.iter("format")`, **no** `findall`, porque en algunos XML
los `<format>` cuelgan de `<output>` y no de la raíz — buscar solo en la raíz
los dejaba vacíos sin avisar y las puntuaciones perdían su factor de escala en
silencio). Cada uno trae hijos `<multiply>`/`<add>` que se acumulan en
`(mult, suma)`.

**`_columnas(raiz)` → lista de `(id, formato)`.** Lee `<output><table>
<column id format/></table></output>`, **descartando** las columnas marcadas
`display="debug"` — importa porque muchos XML guardan el mismo dato dos
veces (por ejemplo `SCORE` y `SCORE_LONG`), y solo una de las dos es la que
hay que presentar.

**`_al_reves(raiz)` → booleano.** Busca si algún `<elt>` de todo el XML tiene
`table-index="loop_reverse_index"` (lo declaran 55 XML, entre ellos Kung-Fu
Master, Missile Command y Q*bert): significa que la tabla está guardada del
peor al mejor puesto.

**`puntuaciones(ruta_xml, datos, fuente=None)` → `(filas_normalizadas,
sueltos)`.** La función pública que usa `puntajes.py`. Pasos:

1. `descifrar_con_xml()` para obtener `filas`/`sueltos` en crudo.
2. Vuelve a resolver `ruta_xml`/`raiz` (los `<format>` viven en el XML
   **final**, después de seguir las redirecciones, no en el original).
3. Si `_al_reves(raiz)`, invierte `filas`.
4. Calcula `fmts` (`_formatos`) y `cols` (`_columnas`).
5. **`op_implicita(f)`** — función anidada: interpreta identificadores de
   formato como `"*10"`, `"+1"`, `"-5"` **sin que exista un `<format
   id="*10">` declarado en ningún sitio**: el propio identificador de formato
   ES la operación (con una expresión regular `r"([*+/-])(\d+)"`). Esto hace
   falta porque **706 de los 3102 XML** referencian un formato así sin
   definirlo explícitamente — no es un descuido de la base, es parte del
   formato. Sin esto, Commando salía a 5000 en vez de 50000 sin ningún error.
6. **`aplica(ident, valor)`** — busca en `cols` el `format=` asociado a esa
   columna, resuelve el multiplicador/suma (primero mirando `fmts`, si no,
   `op_implicita`) y aplica `valor * mult + suma`.
7. Identifica qué columna es la puntuación (`id_punt`, la primera cuyo `id`
   contiene `"SCORE"` en mayúsculas) y cuál el nombre (`id_nom`, la primera
   que contiene `"NAME"` o `"INITIAL"`) **a partir del orden declarado en
   `<output>`**, no adivinando sobre las claves del diccionario — así se
   descarta correctamente el gemelo de depuración.
8. Para cada fila: si `id_punt` está identificado y presente en esa fila, usa
   ese valor; si no, busca cualquier clave que contenga `"SCORE"` pero no
   `"LONG"` y sea un entero (red de seguridad si `<output>` no lo definió
   bien). Si no hay ningún entero de puntuación, **la fila se descarta**. Se
   le aplica `aplica()`. El nombre se busca igual, con `id_nom` o el
   equivalente heurístico. Construye
   `{"puesto": f.get("__puesto", i), "puntos": ..., "nombre": ... (si hay)}`.

**`buscar_db(rutas=())` → carpeta o `None`.** Prueba, en orden: las rutas que
se le pasen, la variable de entorno `HI2TXT_DB`, `~/hi2txt-xml/src/main/db`,
`~/.mame/hi2txt/db`, `/usr/share/hi2txt/db`. Devuelve la primera que sea un
directorio existente. **Nota explícita en el código**: esta lista está
acoplada a mano con la función `hay_hi2txt()` de `instalar.sh` (en Bash), que
mira los mismos cuatro sitios para decidir si avisa de que falta descargar la
base — si se cambia aquí, hay que cambiarlo también allí.

**`fuentes_declaradas(ruta_xml)` → lista de cadenas (`".hi"`, `"nvram"`,
`"saveram"`...).** Resuelve redirecciones y devuelve, en el orden en que
aparecen en el XML, el `file=` de cada `<structure>` declarada. Es lo que usa
`candidatos_de()` de `puntajes.py` para decidir el orden de preferencia de
fuentes de un juego concreto. Importa porque MAME no llama "nvram" a todo
(NeoGeo usa `saveram`, Star Wars `x2212`, Gauntlet `eeprom`) y sin preguntarle
al XML se quedaban fuera juegos que sí tenían datos escritos con otro nombre
de fichero.

---

## 4. `creditos/buscar_tabla.py` — encontrar la tabla por las iniciales

### 4.1 Propósito

La metodología general para localizar una dirección de memoria desconocida
(en RAM o en un fichero de NVRAM) está documentada a fondo en
`docs/direcciones-ram.md`; este apartado **no la repite**, solo explica qué
hace *este script en concreto*.

La idea puntual de esta herramienta: en vez de buscar "números que bajan"
sobre un binario de kilobytes (lo que da falsos positivos por todas partes,
como ya pasó buscando en la NVRAM a ciegas), busca **grupos de letras a
intervalos regulares**. Una tabla de récords con iniciales es de las poquísimas
estructuras que tienen esa forma: tres caracteres imprimibles, repetidos cada
N bytes, N veces. Localizada esa rejilla, la puntuación se busca **solo**
dentro de los bytes de esa misma entrada (un puñado), donde sí es barato
probar todos los formatos posibles.

### 4.2 Uso

```
./buscar_tabla.py <juego1> [<juego2> ...]
```

Sin flags ni opciones. Por cada nombre de juego en `sys.argv[1:]`, reúne
"fuentes" de bytes candidatas: el volcado de `puntajes_fabrica.json` si ese
juego está ahí, y cualquier fichero de `~/.mame/nvram/<juego>/*` (o de la
carpeta que diga la variable de entorno `NVRAM_PATH`) que pese menos de
200.000 bytes. Para cada fuente, llama a `analiza()`; en cuanto una da un
resultado, lo imprime y pasa al siguiente juego. Si ninguna fuente de ningún
juego produce nada, imprime `"nada con forma de tabla"`.

No escribe nada en ningún `.dat`: solo imprime por pantalla la receta que
habría que copiar a mano en `puntajes.dat`.

### 4.3 Funciones

**`swap(d, paso=2)`** — igual que `_intercambiar` de `hi2txt.py`: invierte los
bytes por parejas de `paso`. Se usa para probar también la variante
"intercambiada" de cada fuente (placas de 16 bits).

**`LETRAS`** — conjunto de códigos ASCII aceptados como "parece una letra":
mayúsculas (`0x41`-`0x5A`), espacio, punto, guion, y dígitos (`0x30`-`0x39`).

**`INDICES`** — desplazamientos de los tres alfabetos "por índice" más
comunes: `capcom` (`0x0a` = 'A'), `snk` (`0x00` = 'A'), `dkong` (`0x11` =
'A'). Sin probar estos desplazamientos, en los juegos que no guardan
iniciales en ASCII el buscador no vería ningún texto en absoluto.

**`iniciales(d, i, n=3, modo="ascii")` → cadena o `None`.** Comprueba si los
`n` bytes en la posición `i` "parecen" iniciales: si están todos vacíos
(espacios o ceros) o el trozo es más corto que `n`, no cuenta. En modo
`"ascii"`, exige que todos los bytes estén en `LETRAS` y decodifica
directamente. En modo indexado, exige que todos los bytes caigan en el rango
`[base, base+26)` de ese alfabeto y traduce cada uno a `chr(ord('A') + c -
base)`.

**`rejillas(d, minimo=4, modo="ascii")` → lista de `(n, paso, inicio)`.**
Encuentra todas las posiciones donde hay "iniciales" (con `iniciales()`), y
para cada una prueba todos los pasos (tamaño de entrada) entre 6 y 64,
contando cuántas veces se repite esa marca exactamente cada `paso` bytes.
Si se repite `minimo` veces o más **y no es "texto corrido"**
(`texto_corrido`, ver abajo), se guarda como candidato `(n, paso, inicio)`.

`texto_corrido(ini, paso, n)` (anidada) distingue una tabla real de una
cadena de texto seguida (el ejemplo del propio comentario: el nombre del
juego, `" DOUBLE DRAGON "`, también parece una rejilla si se mira de tres en
tres letras). El criterio: entre una "inicial" y la siguiente, en una tabla de
verdad hay **hueco** (ceros, la puntuación, cualquier cosa que no sean más
letras); en una cadena de texto, no. Cuenta cuántas de las transiciones tienen
ese hueco (`huecos`) y exige que la mayoría lo tengan (`huecos < n - 1`).

Al final, `rejillas()` ordena los candidatos por longitud descendente y
**elimina solapes**: si dos candidatos están a menos de 64 bytes de distancia
con el mismo paso, se descarta el segundo (se queda con la rejilla más larga
de cada zona). Devuelve como máximo 6.

**`FORMATOS`/`valor(t, fmt)`** — copia local (no importada) de la misma lista
de formatos y la misma lógica de decodificación básica que
`numero()`/`FORMATOS` de `puntajes.py`, pero más simple: sin `RecetaNoEncaja`,
sin `"texto"`, y devolviendo `None` en vez de lanzar excepción si algo falla.

**`puntuacion(d, ini, paso, n, ancho=24)` → `(nota, desplazamiento_relativo,
longitud, formato, valores)` o `None`.** Una vez localizada la rejilla de
nombres (`ini`, `paso`, `n` entradas), busca el campo numérico **cerca** de
esa posición: prueba desplazamientos desde `ini - ancho` hasta `ini + 4` (o
sea, tanto antes como justo después del nombre), cada formato de `FORMATOS` y
cada longitud dentro de su rango. Para cada combinación, lee el valor de las
`n` entradas; descarta si no se pudieron leer las `n`, si hay menos de 3
valores distintos (evita relleno constante), si el máximo no llega a 100 o
pasa de 10 millones, o si la secuencia no es **descendente** (`baja`, sin
tolerancia de sentido ascendente aquí, a diferencia de `puntajes.py`). Calcula
una nota similar a la de `detectar()` (valores distintos ×3, +12 si todo son
múltiplos de 10, + la longitud del campo) y se queda con la de mayor nota.

**`analiza(nombre, datos)` → booleano (si encontró algo).** Prueba **8
combinaciones** de datos: los bytes normales y los intercambiados por parejas
(`swap`), cruzados con los cuatro modos de alfabeto (`ascii`, `capcom`, `snk`,
`dkong`). Para cada combinación, busca rejillas con `rejillas()` y, para cada
una, intenta encontrarle un campo numérico con `puntuacion()`; si lo
encuentra, lo añade a una lista de candidatos. Ordena por nota y, con el
mejor candidato de la **primera** combinación que produjo alguno, imprime:

```
  doubledr   [normal/snk] 5 entradas de 16B desde 0x325
     puntos=0,3,bcd  [10000, 9000, 8000, 7000, 6000]
     nombres en +0  ['TAC', 'KSI', 'MAR', 'SZU', 'OHS']
```

y devuelve `True` inmediatamente (no sigue probando las demás combinaciones
una vez que una ya dio resultado).

### 4.4 Punto de entrada

El bloque `if __name__ == "__main__":` calcula las rutas relativas al propio
fichero (`os.path.dirname(os.path.abspath(__file__))`) y al entorno
(`NVRAM_PATH`), no a una copia concreta del repo — la misma disciplina que
`puntajes.py` y `auditar_puntajes.py`, para que el script sirva igual en la
cabina y sobre un volcado traído de otra máquina. Carga
`puntajes_fabrica.json` si existe, y para cada juego pasado por línea de
comandos reúne sus fuentes (fábrica + ficheros de NVRAM ordenados) y llama a
`analiza()` sobre cada una hasta que alguna tenga éxito.

---

## 5. `creditos/auditar_puntajes.py` — comparar contra la referencia

### 5.1 Propósito y cuándo se usa

Compara lo que `puntajes.py` descifra **hoy** contra las tablas de fábrica que
la propia base `hi2txt-xml` ya trae descifradas en su carpeta hermana
`db_defaults` (2697 juegos). Es una referencia **independiente**: escrita por
otra gente, con otro código. Si coincide, la receta es correcta; si no, hay
algo que revisar. Se usa después de tocar una receta o de añadir juegos
nuevos, como una comprobación de regresión.

### 5.2 Uso

No usa `argparse`: solo mira si `"--hi2txt"` está literalmente en
`sys.argv` y, si está, toma el siguiente elemento como la ruta de la base. Si
no, usa la variable de entorno `HI2TXT_DB` o `hi2txt.buscar_db()`. No acepta
ningún otro argumento; no filtra por juego.

```
./auditar_puntajes.py
./auditar_puntajes.py --hi2txt ~/hi2txt-xml/src/main/db
```

### 5.3 Cómo se monta el entorno

Es un script "de un solo uso" que no está pensado como librería: al principio
hace `sys.path.insert(0, AQUI)` y `os.chdir(AQUI)` (se cambia al directorio de
`creditos/`, así las rutas relativas como `"puntajes.dat"` funcionan sin
importar desde dónde se lance). En vez de un `import puntajes` normal, usa
`importlib.util.spec_from_file_location` para cargar `puntajes.py` **como
módulo dinámico bajo el nombre `pj`** — un detalle deliberado, casi seguro
para evitar el choque de nombres con el propio `sys.argv`/parsing de
`puntajes.py` si se importara de la forma normal, o simplemente para no
depender de que `creditos/` esté en el `PYTHONPATH`.

Después:

- Fija `pj.DB_HI2TXT` a la base resuelta.
- Calcula `DEF` como `<hermano de _db>/db_defaults` (la carpeta de
  referencia).
- Si hay `NVRAM_PATH` en el entorno, se lo pasa también a `pj.DIR_NVRAM`.
- Carga `bloques` (`pj.leer_hiscore_dat`), `recetas` (`pj.leer_puntajes_dat`),
  `fabrica` (`puntajes_fabrica.json`, y lo asigna a `pj.FABRICA`).
- Calcula `dir_hi` igual que hace `puntajes.py`.
- Construye el universo de `juegos` con la **misma regla** que
  `--listar` de `puntajes.py`: unión de juegos con `.hi`, juegos con volcado
  de fábrica, y subcarpetas de NVRAM.

**`TOCADOS`** — conjunto fijo de juegos que Eloy o las pruebas ya jugaron, así
que su tabla real **ya no es** la de fábrica y no tiene sentido compararla
contra `db_defaults` (se contarían como discrepancia sin serlo).

### 5.4 Las funciones

**`referencia(j)` → lista de enteros o `None`.** Busca `<DEF>/<j>.xml`
(mismo nombre de fichero que la estructura, pero en la carpeta `db_defaults`,
que trae los datos ya volcados en formato de **tabla HTML-como**, con
`<row><cell>...</cell></row>`). Para cada `<row>`, recoge las celdas cuyo
texto es puramente numérico (`re.fullmatch(r"\d+", ...)`); si hay dos o más
celdas numéricas, se queda con la **segunda** (normalmente puesto + puntos, y
la segunda es la puntuación); si solo hay una, se queda con esa. Devuelve la
lista de puntuaciones en orden, o `None` si el fichero no existe, no se puede
parsear, o no salió ninguna fila.

### 5.5 El bucle principal

Para cada `j` en `juegos`: llama a `pj.puntajes_de(...)` (la función completa
de `puntajes.py`, exactamente la misma que produce el JSON final — otra vez
la disciplina de "medir por la misma ruta que se publica"). Si no descifra,
se salta. Si descifra, compara `mios = [f["puntos"] for f in filas]` contra
`referencia(j)`; si no hay referencia, cuenta como `sinref` y sigue. Si hay
referencia, compara los primeros `min(len(ref), len(mios), 5)` valores
**exactamente** (`mios[:n] == ref[:n]`). Si coinciden, `ok += 1`. Si no
coinciden pero `j` está en `TOCADOS`, se cuenta como `sinref` (se jugó, no es
una discrepancia real). Si no coinciden y no está tocado, `mal += 1` y se
guarda `(j, mios[:5], ref[:5])` en `problemas`.

Al final imprime el resumen (`ok`, `mal`, `sinref`) y, si hay problemas, los
lista uno a uno con los valores propios y de referencia para poder comparar a
simple vista.

---

## 6. `creditos/importar_cheats.py` — sacar direcciones de la colección de cheats

### 6.1 Propósito y cuándo se usa

Este script **no tiene nada que ver con las puntuaciones**: alimenta
`creditos.dat`, el fichero que usa `creditos.lua` dentro de MAME para saber
dónde vive el **contador de créditos** de cada juego (no la tabla de
récords). Se ejecuta una vez, o cada vez que se quiere ampliar la cobertura de
`creditos.dat` con nuevos juegos, a partir de la colección de cheats de
Pugsy/MAME (mamecheat.co.uk).

### 6.2 Uso

```
./importar_cheats.py cheat.7z
./importar_cheats.py cheat.zip
./importar_cheats.py carpeta_con_xmls/
./importar_cheats.py cheat.zip --salida creditos.dat
./importar_cheats.py cheat.zip --solo pacman dkong
```

Argumentos: `origen` (posicional, obligatorio: un `.7z`, `.zip`, `.xml` o
carpeta); `--salida` (por defecto `creditos.dat` al lado del script);
`--solo JUEGO [JUEGO...]` (limita la importación a esos sets).

### 6.3 El formato de los cheats de Pugsy

Cada `.xml` de la colección describe los cheats de **un** juego (el nombre del
fichero es el nombre del set). Dentro, cada `<cheat desc="...">` puede tener
uno o más `<script state="...">`, y cada script una o más `<action>` con el
formato:

```xml
<cheat desc="Infinite Credits">
  <script state="run">
    <action>maincpu.pb@4E6E=09</action>
  </script>
</cheat>
```

`maincpu.pb@4E6E=09` significa: en el espacio de memoria `program` de la CPU
`maincpu` (`pb` = "program byte"), en la dirección `4E6E`, forzar el valor
`09` en cada frame mientras el script esté en marcha (`state="run"`, el que
corre de continuo, a diferencia de `state="on"`/`"off"` que serían disparos
puntuales).

### 6.4 Las funciones

**`ACCION`** — expresión regular que extrae `(cpu, ancho, dirección)` de una
línea de acción: `^\s*([\w:.]+)\.(p[bwdq])@([0-9A-Fa-f]+)\s*=`. El `ancho`
(`pb`/`pw`/`pd`/`pq` = byte/word/dword/qword) se captura pero **no se usa**
(el `_` al desempaquetar): el script solo necesita la CPU y la dirección, no
cuántos bytes ocupa el contador.

**`INTERESA`/`DESCARTA`** — dos expresiones regulares sobre la descripción del
cheat (`desc=`). `INTERESA` exige que contenga la palabra `credit` (con
límites de palabra, insensible a mayúsculas). `DESCARTA` excluye los que,
aunque mencionen "credit", no son lo que se busca: `coin counter`, `no
credit`, `credit to continue` — cheats que hablan de créditos pero no son "el
contador que sube y baja al jugar".

**`de_xml(texto, nombre_fichero)` → `(juego, cpu, dirección)` o `None`.**
Parsea el XML (si falla el parseo, devuelve `None` sin abortar). El nombre del
juego sale del propio nombre de fichero, sin la extensión
(`os.path.splitext(os.path.basename(...))`). Recorre todos los `<cheat>`,
filtra por descripción con `INTERESA`/`DESCARTA`, y dentro de los que pasan el
filtro, busca **solo** los `<script>` cuyo `state` sea `None` o `"run"` (el
que se ejecuta de forma continua — un cheat "de una vez" no sirve para leer
el contador en todo momento). Dentro de ese script, busca la primera
`<action>` que encaje con `ACCION`; si la encuentra, devuelve
`(juego, cpu_con_dos_puntos, dirección_en_minúsculas_sin_ceros_a_la_izquierda)`.
El `cpu` se normaliza para empezar siempre con `:` (`cpu if cpu.startswith(':')
else ':' + cpu`). La dirección se pasa por `.lower().lstrip('0') or '0'` —
quita ceros a la izquierda salvo que la dirección entera sea cero, en cuyo
caso deja un único `'0'` (para no dejar una cadena vacía).

**`recorrer(origen)` → generador de `(nombre, texto)`.** Según el tipo de
`origen`:

- **Carpeta**: recorre recursivamente con `os.walk`, en orden alfabético
  (`sorted(ficheros)`), y produce cada `.xml` que encuentre.
- **`.zip`** (comprobado con `zipfile.is_zipfile`, no solo por extensión):
  recorre el índice del zip en orden alfabético, produciendo cada `.xml`
  leído directamente de memoria (`z.read(...)`).
- **Un `.xml` suelto**: lo produce directamente.
- **`.7z`**: aquí no hay soporte nativo en la librería estándar de Python, así
  que se busca un binario de 7-Zip (`descompresor_7z()`), se extrae a una
  carpeta temporal (`tempfile.mkdtemp`) con `7z x -y -o<tmp> <origen>`, y se
  **recurre** sobre esa carpeta ya extraída (`yield from recorrer(tmp)`),
  borrando el temporal al terminar (`shutil.rmtree(..., ignore_errors=True)`
  en un `finally`, así que se limpia incluso si algo falla a mitad).
- Cualquier otra cosa: `sys.exit()` con un mensaje de error.

**`SIETEZ`/`descompresor_7z()`** — el nombre del binario de 7-Zip **no es el
mismo en todas las distros**: `p7zip` trae `7z`/`7za`, el `7zip` oficial que
empaquetan Arch/Fedora trae `7zz`. `descompresor_7z()` prueba los cuatro
nombres con `shutil.which()` y se queda con el primero que exista.
`COMO_INSTALAR_7Z` es el texto de ayuda con el paquete correcto por distro, que
se muestra si no se encuentra ninguno.

**`leer_existentes(ruta)` → `{juego: línea_completa}`.** Lee el
`creditos.dat` actual (si existe) y, con una regex simple (`^\s*([\w\-]+)\s+@`),
extrae qué juegos **ya** tienen una línea (venga de donde venga, comprobada o
importada) y guarda la línea entera tal cual estaba, sin tocarla.

### 6.5 `main()`

1. Parsea argumentos.
2. `ya = leer_existentes(args.salida)`.
3. Recorre todos los XML de `args.origen` con `recorrer()`. Para cada uno,
   `de_xml()`; si no encuentra nada útil, se salta. Si `--solo` está puesto y
   el juego no está en la lista, se salta. **Si el juego ya tiene línea en
   `creditos.dat`, se salta y cuenta como `saltados`** — la regla explícita es
   que **lo comprobado manda sobre lo importado**: una dirección verificada
   ejecutando el juego (por `buscar_creditos.sh`) nunca se sobrescribe con una
   importada sin comprobar.
4. Las líneas nuevas se guardan en `nuevas[juego]` con el formato:
   `"<juego> @<cpu>,program,<dirección>   # (cheat)"` — la marca `(cheat)` al
   final es la que le dice a `creditos.lua` que **nunca escriba** en esa
   dirección (solo la lee, y encima solo tras comprobar por comportamiento que
   sube con las monedas).
5. Si no hay nada nuevo, imprime un resumen y termina sin tocar el fichero.
6. Si hay algo nuevo: funde `ya` + `nuevas` (`todas = dict(ya); todas.update(nuevas)`)
   y **reescribe el fichero entero**, ordenado alfabéticamente por nombre de
   juego, con una cabecera fija explicando la convención de las marcas. Esto
   es justo lo que documenta la advertencia de `CLAUDE.md`: este script
   **reescribe `creditos.dat` entero**, así que si se lanza sin filtrar
   (`--solo`) sobre una colección completa, se lleva por delante cualquier
   línea que no reconozca como "ya existente" bajo su propia regex — aunque,
   al fundir `ya` (que sí captura *todas* las líneas existentes, comprobadas o
   no, siempre que empiecen por `nombre @`) antes de reescribir, en la
   práctica conserva lo que ya había y solo añade lo nuevo.
7. Imprime un resumen final: cuántos ficheros se miraron, cuántos se
   añadieron, cuántos ya estaban.

---

## 7. `creditos/escribir_ajuste.py` — editar una clave de `arranque.dat`

### 7.1 Propósito y cuándo se usa

Pone o cambia **una** clave de **un** juego en `arranque.dat` (el fichero que
lee `ajustes.lua` dentro de MAME para decidir cuánto tapar el arranque de cada
placa), sin tocar el resto del fichero. Se hace con un programa en vez de con
`sed` porque `arranque.dat` lleva comentarios extensos y una línea especial
`defecto` que no hay que confundir con un juego real; un `sed` a ciegas
podría reventar cualquiera de los dos. Lo usan otros scripts del proyecto
(como `videos.sh`) para volcar en masa valores medidos (por ejemplo,
`video=N`) sin tener que editar el fichero a mano juego por juego.

### 7.2 Uso

```
./escribir_ajuste.py <arranque.dat> <juego> <clave> <valor>
```

Cuatro argumentos posicionales obligatorios, comprobados a mano
(`if len(sys.argv) != 5: sys.exit(...)`), no con `argparse`. No hay flags.

### 7.3 `escribir(ruta, juego, clave, valor)`

1. Lee todas las líneas del fichero con `splitlines(True)` (conserva los
   saltos de línea de cada una) si el fichero existe; si no, empieza de una
   lista vacía (permite crear el fichero desde cero).
2. Construye el par a escribir: `"%s=%s" % (clave, valor)`.
3. Recorre línea a línea:
   - Si la línea, una vez recortada (`strip()`), está vacía o empieza por
     `#`, se copia **tal cual** al resultado, sin tocarla — esto conserva la
     indentación y el formato de los comentarios de cabecera exactamente
     como estaban.
   - Si no es la línea del juego que se busca (comparando el primer campo,
     insensible a mayúsculas), también se copia tal cual.
   - Si **es** la línea del juego: se reconstruye campo a campo. Para cada
     par `clave=valor` ya presente en esa línea, si su clave coincide con la
     que se está cambiando, se sustituye por el nuevo par; si no, se conserva
     igual. Si la clave buscada **no** estaba en la línea, se añade al final.
     Se reescribe la línea completa: `"%s %s\n" % (nombre_del_juego,
     " ".join(nuevos))`. Se marca `hecho = True`.
4. Si tras recorrer todo el fichero **no** se encontró la línea del juego
   (`hecho` sigue `False`): se añade una línea nueva al final,
   `"<juego> <clave>=<valor>\n"`, asegurándose antes de que la última línea
   existente termine en salto de línea (si no, se le añade uno) para no
   pegar la nueva línea al final de la anterior.
5. Escribe el resultado a un fichero temporal (`ruta + ".tmp.%d" %
   os.getpid()`, el PID en el nombre evita colisiones si dos instancias
   corrieran a la vez) y hace `os.replace(tmp, ruta)` — en POSIX esto es
   **atómico**: si el proceso se interrumpe a mitad, `arranque.dat` no queda
   nunca a medio escribir, se queda con la versión vieja completa o con la
   nueva completa.

**Nota sobre una discrepancia con `CLAUDE.md`.** El propio `CLAUDE.md` (sección
"La calibración de `arranque.dat`") atribuye a este guion un fallo mudo:
*"aplasta la sangría de todos los comentarios de cabecera (los deja pegados al
margen)"* al volcar valores en masa. Leyendo el código de `escribir_ajuste.py`
tal como está hoy (único commit del fichero en el historial de git), **no se
observa ese comportamiento**: las líneas de comentario se copian
literalmente, carácter a carácter, sin tocarlas. Es posible que esa
observación se refiera a un mecanismo distinto (por ejemplo, cómo otro script
en Bash volcaba valores antes de que existiera este `.py`, o a una
circunstancia concreta del fichero de la cabina que no se reproduce aquí). Se
deja constancia de la discrepancia en vez de asumir cuál de las dos fuentes
tiene razón.

### 7.4 Punto de entrada

```python
if __name__ == "__main__":
    if len(sys.argv) != 5:
        sys.exit("uso: escribir_ajuste.py <arranque.dat> <juego> <clave> <valor>")
    escribir(*sys.argv[1:])
```

Sin manejo de excepciones adicional: si el fichero no se puede escribir (por
permisos, por ejemplo), la excepción de `io.open`/`os.replace` se propaga tal
cual y el proceso termina con traza de Python.

---

## 8. `contador_arduino.py` — el saldo hacia el Arduino

### 8.1 Propósito y cuándo se usa

Es el proceso que hace visible el saldo de monedero en el contador físico de
la cabina (hoy un LED, pensado para un display más adelante). Vigila
`~/.attract/creditos.txt` (el mismo fichero que escribe el plugin del
frontend y lee `creditos.lua`, documentado en `CLAUDE.md`) y, cada vez que el
`saldo` cambia, lo manda por el puerto serie al Arduino. Se lanza como un
proceso de fondo permanente en la cabina (pendiente, según `CLAUDE.md`, de
convertirse en un servicio de `systemd` de usuario); hoy se arranca a mano.

Corresponde al diseño "monedero visible en el Arduino" descrito en
`CLAUDE.md` — nótese que ese diseño está hoy **apagado** por defecto (la
cabina usa monedas de verdad), así que este script, aunque sigue siendo
correcto, no tiene nada que enseñar salvo que se reactive `GA_MONEDERO=1` y
el plugin del frontend.

### 8.2 Uso

No tiene argumentos de línea de comandos ni `argparse`: es un script que se
ejecuta directamente (`./contador_arduino.py`) y corre para siempre en un bucle
infinito. No hay forma de pararlo salvo matar el proceso.

Ficheros/dispositivos:

- **Lee**: `~/.attract/creditos.txt` (constante `CREDITS_PATH`).
- **Escribe**: el puerto serie en
  `/dev/serial/by-id/usb-1a86_USB2.0-Serial-if00-port0` (constante `PORT`,
  compuesta de `ARDUINO_PATH + ARDUINO_ID`) a 9600 baudios. Usar la ruta
  **por id** (`/dev/serial/by-id/...`) en vez de `/dev/ttyUSB0` es más
  robusto: ese enlace simbólico identifica el Arduino por su chip USB-serie
  concreto y no cambia si se conecta a otro puerto físico o si hay más de un
  adaptador serie enchufado — a diferencia de `/dev/ttyUSB0`, que puede
  renumerarse. Es una mejora respecto a la versión de `arduino/sandbox.py`
  (ver sección 11), que sigue usando el nombre de dispositivo fijo.
- **Escribe** un fichero de log en el directorio de trabajo actual, con
  nombre `log<AAAA-MM-DD_HH:MM:SS>.txt` (la marca de tiempo se calcula **una
  vez** al importar el módulo, en la constante `LOG_NAME`, así que todo el
  log de una ejecución va al mismo fichero).

Dependencia externa: el paquete `pyserial` (`import serial`).

### 8.3 Constantes

```python
CREDITS_PATH = os.path.expanduser("~/.attract/creditos.txt")
ARDUINO_PATH = "/dev/serial/by-id/"
ARDUINO_ID = 'usb-1a86_USB2.0-Serial-if00-port0'
PORT = ARDUINO_PATH + ARDUINO_ID
BAUD_RATE = 9600
LOG_NAME = <marca de tiempo al arrancar>
UPDATE_TIME = 0.1      # segundos entre lecturas del fichero
ARDUINO_TIME = 3       # segundos de espera tras abrir el puerto (reinicia la placa)
RETRY_TIME = 5         # segundos entre reintentos de conexión
```

`1a86` en el identificador USB es el fabricante del chip serie (CH340/CH341,
muy común en placas Arduino chinas/clones).

Variables de estado globales: `userCredits` (último valor leído, informativo),
`conection` (el objeto `serial.Serial` abierto, o `None`), `lastError` (para
no repetir el mismo mensaje de error en el log), `lastCredit` (el último valor
que se **envió con éxito** al Arduino).

### 8.4 Las funciones

**`log(logString)`.** Escribe una línea con marca de hora en el fichero de
log — **pero solo si el mensaje es distinto del último ya registrado**
(compara `castedString` contra `lastError`). Esto evita que un error
persistente (el Arduino desconectado durante horas, por ejemplo) llene el
log con la misma línea miles de veces; solo se anota la **primera vez** que
aparece ese error concreto.

**`logOk()`.** Si no había ningún error pendiente (`lastError is None`), no
hace nada. Si lo había, escribe la línea `"recuperado"` en el log y limpia
`lastError`. Se llama en cada punto donde una operación que antes podía fallar
**ha tenido éxito** — así el log cuenta una historia completa: "empezó a
fallar con tal mensaje... se recuperó", sin necesidad de que el mensaje de
error se repita.

**`initArduino() → bool`.** Si `conection` ya está abierta (`is not None`),
devuelve `True` inmediatamente sin hacer nada — **abrir el puerto de nuevo
reinicia la placa Arduino**, así que solo se abre una vez y se mantiene
abierto entre lecturas. Si no está abierta, intenta `serial.Serial(PORT,
BAUD_RATE)`; si tiene éxito, espera `ARDUINO_TIME` (3 s, el tiempo que tarda
la placa en reiniciarse tras la apertura del puerto y quedar lista para
recibir), **resetea `lastCredit` a `None`** (para que el próximo valor leído
se envíe siempre, aunque coincida por casualidad con el último que se había
enviado antes de la desconexión — la placa acaba de reiniciarse y muestra 0,
así que hay que forzar un reenvío), llama a `logOk()` y devuelve `True`. Si
falla (`SerialException`/`SerialTimeoutException`), lo registra con `log()` y
devuelve `False`.

**`getFileData(path)` → contenido del fichero como texto.** Abre, lee y
cierra el fichero en cada llamada — **se reabre el fichero cada vez**, nunca
se mantiene un descriptor abierto entre lecturas. Esto es necesario porque el
fichero de créditos se **reemplaza** (temporal + `os.replace`, atómico), no
se modifica en el sitio: con un descriptor abierto de antes, en Linux se
seguiría leyendo el inodo viejo (ya desenlazado del directorio) para siempre,
en vez de los datos nuevos.

**`getUserCredits() → int` o `None`.** Llama a `getFileData()`, parte el
contenido por líneas, y busca la primera que empiece por `"saldo"`
(formato del fichero: `"saldo 4"`). Extrae el segundo campo separado por
espacio y lo convierte a entero. Si todo va bien, llama a `logOk()` (el
fichero se pudo leer y tenía el formato esperado) y devuelve el crédito. Si
algo falla (fichero no existe, sin permisos, encoding raro, error de E/S, el
número no es un entero válido, o falta el segundo campo — el conjunto de
excepciones capturadas es `FileNotFoundError, PermissionError,
UnicodeDecodeError, OSError, ValueError, IndexError`), lo registra con `log()`
y devuelve `None`. **Ojo**: si ninguna línea empieza por `"saldo"`, la
función no entra en el bucle `for` de forma que devuelva nada explícito, y
cae al final de la función sin `return` — en Python eso devuelve `None`
implícitamente, igual que en el camino de error, pero **sin pasar por
`log()`**, así que ese caso concreto (fichero legible pero sin línea
`"saldo"`) no queda registrado en el log de errores.

**`sendToArduino(credits) → bool`.** Codifica `str(credits) + "\n"` y lo
escribe en el puerto serie. Si falla (excepción de serie u `OSError`), lo
registra, **pone `conection = None`** (fuerza a que la próxima vuelta del
bucle principal vuelva a intentar `initArduino()`, con su espera de 3 s y su
reset de `lastCredit`) y devuelve `False`. Si tiene éxito, llama a `logOk()` y
devuelve `True`.

### 8.5 El bucle principal

No está envuelto en una función `main()`, ni protegido por
`if __name__ == "__main__":` — el bucle `while True:` corre directamente al
nivel del módulo, así que **cualquier cosa que importe este fichero lo
ejecutaría también** (no está pensado para usarse como librería, solo como
script).

```python
while True:
    time.sleep(UPDATE_TIME)          # 0.1 s entre vueltas

    if initArduino() is False:
        time.sleep(RETRY_TIME)       # 5 s extra si no hay conexión
        continue

    userCredits = getUserCredits()
    if userCredits == lastCredit or userCredits is None:
        continue                      # nada que enviar

    if sendToArduino(userCredits) is True:
        lastCredit = userCredits      # solo se apunta si el envío tuvo éxito
        print("Creditos:", userCredits)
```

El detalle importante, ya señalado en `CLAUDE.md`: **`lastCredit` solo se
actualiza si el envío devolvió `True`**. Si se actualizara antes de confirmar
el envío, un fallo de escritura dejaría el contador físico desincronizado
para siempre (el programa creería que ya mandó el valor N, y no lo
reintentaría aunque el Arduino nunca lo haya recibido). Con la lógica actual,
mientras el envío siga fallando, `userCredits != lastCredit` sigue siendo
cierto en cada vuelta y se reintenta cada 0.1 s.

---

## 9. `pantalla.py` — dejar el CRT como única pantalla

### 9.1 Propósito y cuándo se usa

Bajo GNOME Wayland, `xrandr` no tiene autoridad real sobre qué monitor se usa
ni dónde se coloca: la disposición la controla `mutter` (el gestor de
ventanas de GNOME) a través de una interfaz D-Bus propia
(`org.gnome.Mutter.DisplayConfig`). Este script hace exactamente lo que la
cabina necesita en esa sesión: dejar el CRT como única pantalla mientras dura
la partida, y devolver el escritorio a como estaba al terminar. Lo invoca
`cabina.sh` (fuera del alcance de este documento) y también `patron.py` (ver
sección 10).

Los cambios se aplican en modo **temporal** (`TEMPORAL = 1`, uno de los tres
valores que acepta `ApplyMonitorsConfig`: 0 verificar sin aplicar, 1 aplicar
sin persistir, 2 aplicar y guardar), así que un reinicio de sesión los
deshace solos sin dejar rastro permanente en la configuración de GNOME.

### 9.2 Uso

```
./pantalla.py cabina       -> deja solo el CRT encendido
./pantalla.py escritorio   -> restaura todas las pantallas
./pantalla.py estado       -> imprime la disposición actual (por defecto, sin argumento)
```

No usa `argparse`: lee `sys.argv[1]` a pelo, con `"estado"` como valor por
defecto si no se pasa nada, y despacha con un diccionario
`{"cabina": cabina, "escritorio": escritorio, "estado": imprimir}.get(orden,
lambda _p: sys.exit(__doc__))` — cualquier palabra que no sea una de esas
tres imprime el docstring del módulo (a modo de ayuda) y sale.

Depende de `PyGObject` (`import gi`; `gi.require_version("Gio", "2.0")`;
`from gi.repository import Gio, GLib`), la envoltura Python de las librerías
GLib/GObject, necesaria para hablar D-Bus desde Python de esta forma.

Lee/escribe: `~/.attract/pantalla_previa.json` (constante `PREVIA`), donde
guarda la disposición de monitores que había **antes** de forzar el modo
cabina, para poder devolverla tal cual al salir.

### 9.3 Las funciones

**`proxy() → Gio.DBusProxy`.** Crea el proxy D-Bus sobre el bus de **sesión**
(`Gio.BusType.SESSION`, no el de sistema) apuntando al objeto
`/org/gnome/Mutter/DisplayConfig` con la interfaz
`org.gnome.Mutter.DisplayConfig`. Es el objeto que se pasa a todas las demás
funciones.

**`estado(p)` → `(serial, monitores, logicos)`.** Llama al método D-Bus
`GetCurrentState` (síncrono, sin timeout — `-1`) y desempaqueta la tupla que
devuelve. `serial` es un número que mutter usa para detectar cambios
concurrentes (hay que pasarlo de vuelta en cualquier `ApplyMonitorsConfig`
para que sepa sobre qué estado se está aplicando el cambio). `monitores` es
la lista de monitores físicos conocidos (con su información de modos
soportados); `logicos` es la disposición **actual** (qué monitores están
encendidos, en qué posición, a qué escala, con qué monitor asignado a cada
"pantalla lógica").

**`modo_actual(monitor)` → identificador de modo.** Recorre los modos de
vídeo que soporta un monitor (`monitor[1]`) buscando el que tenga
`is-current` en sus propiedades; si ninguno está marcado como actual (puede
pasar si el monitor está apagado), se queda con el marcado `is-preferred`; si
tampoco hay ninguno así, usa el primero de la lista sin más.

**`conector(monitor)` → cadena** (p. ej. `"VGA-1"`). Es simplemente
`monitor[0][0]`, el primer campo de la tupla que identifica al monitor.

**`aplicar(p, serial, logicos)` → la disposición realmente aplicada.**
Envoltorio de `_aplicar()` con un mecanismo de reintento: si mutter rechaza el
cambio con el error concreto `"closed laptop panel"` (`Refusing to activate a
closed laptop panel`, algo que ocurre en portátiles con la tapa cerrada),
**no** propaga la excepción sin más — reconstruye la lista de pantallas
lógicas **quitando** cualquiera que use un conector de panel interno
(`eDP`/`LVDS`), recoloca las que quedan una al lado de otra empezando en el
origen (el primero como primaria), y reintenta. Si tras quitar el panel no
queda ninguna pantalla, sale con un mensaje de error explicando la situación.
Cualquier otro tipo de error D-Bus (`GLib.GError` con otro mensaje) se
propaga tal cual, sin intentar nada especial.

**`_aplicar(p, serial, logicos)`.** La llamada D-Bus en crudo:
`ApplyMonitorsConfig` con la firma de tipo `"(uua(iiduba(ssa{sv}))a{sv})"` —
literalmente: `serial` (uint), el modo (`TEMPORAL`, uint), y la lista de
pantallas lógicas, cada una como
`(x, y, escala, transformación, es_primaria, [(conector, modo, propiedades)])`.

**`externo(monitores)` → el primer monitor o `None`.** Devuelve el primer
monitor de la lista cuyas propiedades **no** indiquen `is-builtin` — en la
práctica, el CRT conectado por VGA, distinguiéndolo del panel interno del
portátil.

**`guardar(monitores, logicos)`.** Traduce la disposición actual (identificada
por `GetCurrentState`, que usa `(conector, marca, modelo, serie)` para cada
monitor) al formato que espera `ApplyMonitorsConfig` (que identifica cada
monitor por `(conector, modo)`), y la vuelca a JSON en `PREVIA`. Si algo falla
al escribir (permisos, o que un conector referenciado en `logicos` no
aparezca en el diccionario `porconector` — `KeyError`), **no aborta**: solo
avisa por pantalla y sigue (perder la disposición previa es molesto, pero no
debe impedir que la cabina arranque).

**`recuperar()` → disposición leída de `PREVIA`, o `None`.** Lee el JSON y la
reconstruye en el formato de tuplas que espera `aplicar()` (con un
diccionario vacío de propiedades por cada asignación). Si el fichero no
existe o no es JSON válido (`OSError`, `ValueError`), devuelve `None` sin
propagar el error.

**`cabina(p)`.** La acción del subcomando `cabina`. Obtiene el estado actual;
**si hay más de una pantalla lógica activa** (o sea, si de verdad hay algo
que restaurar luego), llama a `guardar()` **antes** de tocar nada — así, si ya
estaba en modo "solo CRT" de una sesión anterior, no sobrescribe la
disposición buena guardada previamente con la de "solo CRT" (que sería
inútil como referencia para restaurar). Busca el CRT con `externo()`; si no
hay ninguno, sale con error. Aplica una disposición de una sola pantalla
lógica: el CRT, en `(0,0)`, escala `1.0`, sin rotación, marcada como primaria,
a su modo actual.

**`escritorio(p)`.** La acción del subcomando `escritorio`. Primero intenta
`recuperar()` la disposición previa guardada; si existe **y** el conjunto de
conectores que menciona coincide exactamente con el conjunto de monitores que
hay ahora conectados (para no intentar aplicar una disposición que mencione un
monitor que ya no está), la aplica tal cual y termina. Si no hay disposición
previa válida (primera vez que se usa, o los monitores conectados han
cambiado), construye una disposición **desde cero**: ordena los monitores
poniendo primero los que **no** son `is-builtin`... en realidad al revés —
`sorted(monitores, key=lambda m: not m[2].get("is-builtin"))` ordena `False`
(es builtin) antes que `True` (no es builtin), así que el panel del portátil
va **primero** y se marca primario, y el resto (el CRT) se coloca a su
derecha. Para cada monitor calcula su modo actual, y **la escala se elige
como la que deja el ancho lógico resultante más cerca de 1920 píxeles**
(`min(escalas, key=lambda e: abs(ancho / e - 1920))`) — así un panel 4K se
pone a un 200% razonable en vez de al 100% (ilegible) o a una escala
arbitraria, y un CRT normal se queda al 100%.

**`imprimir(p)`.** La acción del subcomando `estado` (y valor por defecto).
Recorre las pantallas lógicas actuales y, para cada monitor asignado,
imprime el conector, su modo actual, su posición, su escala, y si es la
primaria y si es el panel interno o el CRT.

---

## 10. `patron.py` — patrón de calibración del CRT

### 10.1 Propósito y cuándo se usa

Genera una imagen de calibración a resolución fija (1024×768, la resolución
de trabajo de la cabina según `CLAUDE.md`) y la muestra a pantalla completa en
el CRT, para responder a dos preguntas de ajuste físico del monitor a la vez:
si la geometría es correcta (círculo redondo, no ovalado) y si el tubo
resuelve líneas de barrido finas (si la banda de 1 px se ve como gris liso, no
las resuelve). Se usa a mano, puntualmente, al instalar o reajustar el CRT —
no es parte del arranque normal de la cabina.

### 10.2 Uso

```
./patron.py          genera el patrón, cambia a modo "solo CRT" y lo muestra a pantalla completa
./patron.py --solo   solo genera el PNG, no toca la pantalla ni lo muestra
```

Escribe: `~/.attract/patron_crt.png` (constante `SALIDA`). Depende de `Pillow`
(`from PIL import Image, ImageDraw, ImageFont`).

### 10.3 Las funciones

**`fuente(tam)` → `ImageFont`.** Prueba dos rutas fijas de DejaVu Sans (Bold y
normal) a un tamaño dado; si ninguna existe en el sistema, cae a la fuente por
defecto de Pillow (`ImageFont.load_default()`, una fuente bitmap muy básica).

**`dibujar()` → ruta del PNG generado.** Construye una imagen RGB de
1024×768, negra, y dibuja sobre ella con `ImageDraw`:

1. Una **rejilla** de líneas cada 64 px, en azul oscuro (`(0,0,80)`) — sirve
   de referencia visual de fondo, no aporta información de calibración por sí
   sola más allá de dar textura a la imagen.
2. Un **marco doble** (dos rectángulos concéntricos en verde) en el borde
   exacto de la imagen: si el tubo recorta ("come") los bordes, no se verá
   entero.
3. **Arriba: líneas de barrido de 1, 2 y 3 px de grosor**, en tres bandas
   horizontales de 56 px de alto cada una, separadas por 18 px. Cada banda
   dibuja rectángulos horizontales blancos de `grosor` píxeles de alto,
   separados por el mismo grosor de hueco negro (`range(y0, y0+alto, grosor*2)`),
   y rotula el grosor a la izquierda y a la derecha de la banda. El texto de
   cabecera explica el diagnóstico: si la banda de 1 px se ve gris lisa
   (los blancos y los negros se mezclan a la vista), el tubo no resuelve 768
   líneas de verdad.
4. **Abajo: la prueba de geometría.** Un círculo blanco de radio 220 centrado
   en `(512, 500)`, con un cuadrado gris circunscrito, una cruz central, y
   marcas en las cuatro esquinas de la imagen (para detectar distorsión de
   cojín/almohadilla, *pincushion*, no solo estiramiento uniforme). El texto
   explica que un óvalo tumbado indica que el tubo estira y se corrige en el
   ajuste `H-SIZE`/`H-WIDTH` del propio monitor, **no por software** (MAME ya
   dibuja la proporción correcta; el patrón solo sirve para verlo).

Guarda la imagen en `SALIDA` y devuelve la ruta.

### 10.4 Punto de entrada

Llama a `dibujar()` e imprime la ruta y el tamaño. Si se pasó `--solo`,
termina ahí (código 0). Si no, calcula la ruta de `pantalla.py` (en el mismo
directorio que este script) y la invoca como subproceso con el argumento
`"cabina"` (deja el CRT como única pantalla). Luego intenta abrir la imagen a
pantalla completa con `eog --fullscreen <ruta>` (el visor de imágenes de
GNOME) — bloqueante: el script espera a que `eog` termine (se cierre con
Escape, tal como indica el propio patrón dibujado). **Pase lo que pase** con
`eog` (incluso si no está instalado y `subprocess.run` no lanza excepción
porque se usa `check=False`, o si fallara por cualquier otro motivo), el
bloque `finally` se asegura de volver a invocar `pantalla.py escritorio` para
restaurar la disposición de monitores normal.

---

## 11. `arduino/sandbox.py` — el banco de pruebas del puerto serie

### 11.1 Propósito y cuándo se usa

Es una versión **anterior y más simple** de `contador_arduino.py` (así lo dice
`ESTRUCTURA.md` explícitamente: *"una versión temprana de `contador_arduino.py`"*). Se
conserva en `arduino/`, junto al firmware `Arcade.ino`, como banco de pruebas
del puerto serie — un sitio donde experimentar con la comunicación serie sin
tocar el script que corre de verdad en la cabina.

### 11.2 Uso

Igual que `contador_arduino.py`: sin argumentos, se ejecuta directamente y corre para
siempre. Lee `~/.attract/creditos.txt` (constante `FILE_PATH`) y escribe en
`/dev/ttyUSB0` (constante `PORT`, **el nombre de dispositivo fijo**, sin la
ruta estable `/dev/serial/by-id/` que usa `contador_arduino.py`) a 9600 baudios. Escribe
un log de errores en `logError<marca_de_tiempo>.txt` en el directorio de
trabajo (nombre de fichero calculado una vez al importar, en `timeNow`).

### 11.3 Diferencias con `contador_arduino.py`, función a función

La estructura es casi idéntica (mismas cuatro funciones:
`initArduino`/`openFile`+`getUserCredits`/`sendToArduino`, mismo bucle
principal), con variables en inglés y comentarios más escasos. Las
diferencias que importan:

- **No separa `log()`/`logOk()` en funciones reutilizables**: cada función
  que puede fallar repite su propio bloque `with open(f"logError{timeNow}.txt",
  "a") as file: ...` y su propia comparación con `lastError`, en vez de
  llamar a una función común. Funciona igual, pero es código duplicado tres
  veces.

- **Ninguna función marca la recuperación** (no hay equivalente a `logOk()`):
  si un error se resuelve solo, el log de `sandbox.py` no dice
  `"recuperado"` en ningún sitio, a diferencia de `contador_arduino.py`.

- **`initArduino()` no devuelve `True`/`False`**: siempre devuelve `None`
  (implícito), tanto si conecta con éxito como si falla. El bucle principal
  no comprueba el valor de retorno, comprueba directamente si `conection is
  not None`.

- **Trampa real en `initArduino()`**: el `return` que evita el resto del
  bloque `except` está anidado **dentro** del `if lastError != str(e):`, no
  directamente bajo el `except`:

  ```python
  except (serial.SerialException, serial.SerialTimeoutException) as e:
      with open(f"logError{timeNow}.txt", "a") as file:
          if lastError != str(e):
              file.write(...)
              lastError = str(e)
          return
  time.sleep(3)
  return
  ```

  Si el **mismo** error se repite dos veces seguidas (`lastError == str(e)`),
  el `return` interior **no se ejecuta** (porque está dentro del `if` que no
  entra), así que el control sigue hasta `time.sleep(3)` y el `return` final
  de la función — exactamente el mismo camino que sigue una conexión
  **exitosa**. El efecto práctico no es catastrófico (la variable `conection`
  ya se ha quedado en `None` porque la asignación `conection =
  serial.Serial(...)` nunca llegó a completarse, así que el bucle principal
  seguirá viendo `conection is None` y reintentando), pero sí introduce una
  espera de 3 segundos **extra e injustificada** en cada reintento fallido
  consecutivo, además del `time.sleep(5)` que ya pone el bucle principal en
  la rama de "conexión fallida" — un patrón de reintento de facto de 8
  segundos en vez de 5 cuando el mismo error persiste. Es una trampa sutil de
  indentación, no un fallo de diseño: `contador_arduino.py` no la reproduce porque
  reestructuró la función devolviendo `True`/`False` explícitamente en cada
  camino.

- **`sendToArduino(credits)` ignora su propio parámetro**: la firma recibe
  `credits`, pero el cuerpo construye el mensaje a partir de la variable
  **global** `userCredits` (`stringData = str(userCredits) + '\n'`), no del
  parámetro recibido. En la práctica no causa ningún problema porque el único
  sitio donde se llama es `sendToArduino(userCredits)` — es decir, siempre se
  le pasa exactamente esa misma variable global como argumento, así que
  ambas lecturas coinciden. Pero es un parámetro que no hace nada: si algún
  día se llamara con otro valor (por ejemplo, para probar el envío de un
  número concreto sin pasar por el fichero), se enviaría silenciosamente el
  valor equivocado. `contador_arduino.py` corrige esto usando el parámetro
  (`str(credits)`).

- **El sentinela `lastCredit = -1`**: en vez de simplemente "no actualizar
  `lastCredit`" cuando el envío falla (lo que hace `contador_arduino.py`), `sandbox.py`
  fija `lastCredit = -1` explícitamente tras un fallo de envío, y además
  **también** comprueba `lastCredit == -1` en la condición de "nada que
  hacer" (`if userCredits is None or lastCredit == -1 or userCredits ==
  lastCredit: continue`). Esto es contradictorio a primera vista: si
  `lastCredit` vale `-1`, la condición se cumple y el bucle hace `continue`
  **saltándose el reintento de envío** en la siguiente vuelta también,
  aunque `userCredits` sea distinto de `-1`. En la práctica el bucle nunca
  llega a ese estado de forma persistente porque **cada vuelta primero
  reevalúa `getUserCredits()`**, y si el valor leído sigue siendo el mismo
  que antes del fallo, tampoco habría nada que reenviar de todas formas;
  sigue siendo una diferencia de diseño frente al enfoque más simple y
  correcto de `contador_arduino.py` (no tocar `lastCredit` en absoluto si el envío
  falla, dejando que la comparación `userCredits == lastCredit` decida por sí
  sola si hay que reintentar).

- **`getUserCredits()` no cubre `IndexError`**: la lista de excepciones
  capturadas es `(FileNotFoundError, PermissionError, UnicodeDecodeError,
  OSError, ValueError)`, sin `IndexError`. Si la línea `"saldo"` existiera
  pero no tuviera un segundo campo separado por espacio (un fichero
  corrupto o truncado a medio escribir), `parsedData[1]` lanzaría
  `IndexError` **sin capturar**, y el script terminaría con una traza no
  manejada. `contador_arduino.py` sí añade `IndexError` a la lista.

### 11.4 El bucle principal

```python
initArduino()          # se conecta una vez, a nivel de módulo, antes del bucle

while True:
    if conection is not None:
        time.sleep(0.1)
        userCredits = getUserCredits()
        if userCredits is None or lastCredit == -1 or userCredits == lastCredit:
            continue
        else:
            print("User Credits: ", userCredits)
            if sendToArduino(userCredits) is False:
                lastCredit = -1
                continue
            lastCredit = userCredits
    else:
        print("Conection failed, retrying...\n")
        time.sleep(5)
        initArduino()
```

A diferencia de `contador_arduino.py`, aquí `initArduino()` se llama **una vez antes
del bucle** (no dentro de cada vuelta), y dentro del bucle solo se reintenta
si `conection` sigue siendo `None` en la rama `else`. El resultado práctico es
equivalente al de `contador_arduino.py`, pero la estructura es menos uniforme: el
primer intento de conexión vive fuera del bucle y los siguientes dentro.

---

## 12. Resumen de trampas y decisiones no obvias

Para tenerlas todas juntas, sin repetir la explicación completa (que está en
la sección de cada script):

1. **`int(datos.hex())` es el truco central de todo el sistema de
   puntuaciones.** BCD empaquetado y hexadecimal comparten representación de
   texto cuando los nibbles son 0-9, así que convertir a hex y parsear como
   decimal decodifica BCD sin desempaquetar nibble a nibble. Aparece en
   `puntajes.py` (`numero()`) y en `hi2txt.py` (`_leer_int()`), de forma
   independiente en cada uno.
2. **`base="16"` en los XML de hi2txt no significa hexadecimal**: significa
   "BCD sin declararlo con `decoding-profile`". Ignorarlo multiplica algunos
   resultados por potencias de 16 sin ningún error.
3. **Un fichero de memoria persistente enteramente a `0x00` o a `0xFF` no es
   una fuente válida**, aunque exista y pese lo que declara `hiscore.dat`
   (`puntajes.py`, `candidatos_de.leer()`).
4. **El `.hi` manda siempre sobre la NVRAM cuando ambos existen**, sin
   importar el orden en que el XML de hi2txt declare las fuentes.
5. **Comprobar si una tabla está "vacía" (recién descifrada, toda a cero) hay
   que hacerlo ANTES de recortar las filas vacías del final**, o la lista se
   queda sin nada con lo que distinguir "vacía" de "no descifra".
6. **`_defecto_de_fabrica()` se niega a dar una base para cualquier juego con
   memoria persistente propia**: no hay forma fiable de saber cuál era la
   tabla "de verdad" de fábrica una vez que la placa ha podido cargar una
   partida guardada.
7. **`capturar_fabrica()` necesita `-noplugins`**, porque el propio plugin
   `hiscore` reinyecta la puntuación guardada al arrancar y contaminaría el
   volcado "de fábrica".
8. **Los ficheros que produce el sistema (`puntajes.json`, `arranque.dat`
   vía `escribir_ajuste.py`, `creditos.dat`) se escriben siempre a un
   temporal y se renombran** (`os.replace`), nunca se sobrescriben en el
   sitio: es la misma disciplina que documenta `CLAUDE.md` para
   `creditos.txt`, aplicada también en Python.
9. **`contador_arduino.py` reabre el fichero de créditos en cada lectura** porque el
   escritor lo reemplaza entero (no lo modifica): con un descriptor abierto de
   antes se leería para siempre el fichero viejo ya desenlazado.
10. **Abrir el puerto serie reinicia el Arduino**: por eso se abre una sola
    vez y se espera 3 segundos tras abrirlo antes de mandar nada.
11. **`sandbox.py` tiene tres fallos menores de los que `contador_arduino.py` ya no
    adolece**: un `return` mal anidado que añade una espera extra en errores
    repetidos, un parámetro (`credits`) que se ignora a favor de una variable
    global, y una lista de excepciones capturadas incompleta
    (`IndexError`). Ninguno es grave en la práctica actual, pero son la
    prueba de por qué `contador_arduino.py` se reescribió con las funciones separadas
    en `log()`/`logOk()` y devolviendo `True`/`False` explícitos.
12. **`BASE40` en `hi2txt.py` está definida pero no se usa**: el
    `decoding-profile="base-40"` que menciona el docstring del módulo no está
    implementado; cualquier XML que lo use fallaría con `NoSeSabe`.
13. **`_elegir_estructura()` en `hi2txt.py` es código muerto**: no la llama
    nadie; la sustituyó el bucle de `descifrar_con_xml()` que prueba todas
    las estructuras candidatas de `_estructuras()` en vez de comprometerse
    con una elegida de antemano.
14. **`importar_cheats.py` reescribe `creditos.dat` entero** en cada
    ejecución que encuentre algo nuevo: es seguro porque funde con
    `leer_existentes()` antes de reescribir, pero conviene no lanzarlo sobre
    la colección completa sin querer y sin haber hecho copia de seguridad del
    fichero, tal como ya advierte `CLAUDE.md`.
15. **La discrepancia sobre `escribir_ajuste.py` y la sangría de los
    comentarios** (sección 7.3): el código actual del script no reproduce el
    fallo que `CLAUDE.md` le atribuye. Queda anotada para que se investigue
    si vuelve a aparecer.
