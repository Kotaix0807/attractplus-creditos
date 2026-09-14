# Los scripts de shell del proyecto

Documentación de cada script `.sh` propio del proyecto (no los de Attract-Mode
Plus upstream, ni `util/`, ni `extlibs/`). Está pensada para alguien que sabe
programar pero no conoce este código: para cada script se explica qué hace,
cómo se usa, qué variables de entorno lee, qué ficheros toca, a qué otros
scripts llama, y las trampas que el propio código (o sus comentarios) revela.

El "por qué" de fondo —la historia, las decisiones de Eloy, lo medido en la
cabina— está en `CLAUDE.md`. Aquí se documenta el código tal como está escrito
hoy.

## Índice

1. [`instalar.sh`](#instalarsh) — el instalador completo, con whiptail
2. [`cabina.sh`](#cabinash) — arranca el frontend mandando la imagen al CRT
3. [`pantalla-auto.sh`](#pantalla-autosh) — servicio que conmuta CRT/panel solo
4. [`parches/compilar-en-arch.sh`](#parchescompilar-en-archsh) — compila
   GroovyMAME parcheado en Arch/GroovyArcade
5. [`creditos/comun.sh`](#creditoscomunsh) — utilidades compartidas (rutas de MAME)
6. [`creditos/video_comun.sh`](#creditosvideo_comunsh) — compartido por
   `videos.sh` y `grabar.sh`
7. [`creditos/videos.sh`](#creditosvideossh) — graba vídeos de muestra en serie
8. [`creditos/grabar.sh`](#creditosgrabarsh) — graba tu partida con una tecla
9. [`creditos/aspecto.sh`](#creditosaspectosh) — corrige la proporción de lo ya descargado
10. [`creditos/arte.sh`](#creditosartesh) — descarga marquesinas/capturas
11. [`creditos/poner_1c1c.sh`](#creditosponer_1c1csh) — deja el DIP en 1C/1C
12. [`creditos/buscar_creditos.sh`](#creditosbuscar_creditossh) — localiza la
    dirección de RAM del contador
13. [`creditos/pruebas/correr.sh`](#creditospruebascorrersh) — batería principal de pruebas
14. [`creditos/pruebas/aviso_mame.sh`](#creditospruebasaviso_mamesh) — pruebas del
    cuadro de aviso dentro de MAME real
15. [`creditos/pruebas/integracion.sh`](#creditospruebasintegracionsh) — prueba
    de integración AM+ + GroovyMAME de punta a punta
16. [`creditos/pruebas/prueba_importar.sh`](#creditospruebasprueba_importarsh) —
    prueba del importador de cheats
17. [`creditos/pruebas/rescate.sh`](#creditospruebasrescatesh) — prueba del
    rescate de puntuaciones vía `hiscore`

---

## `instalar.sh`

**Propósito en una frase:** deja la cabina lista en una máquina nueva —
dependencias, compilación, configuración de Attract-Mode Plus, lista de
juegos, artes, ajustes de vídeo/audio/teclado— preguntando lo justo con
`whiptail`, y se usa una sola vez por máquina (o cuando se quiere repasar/
rehacer un paso concreto).

Es, con diferencia, el script más grande del proyecto (1790 líneas). Se
ejecuta así:

```bash
git clone https://github.com/Kotaix0807/attractplus-creditos.git
cd attractplus-creditos && ./instalar.sh
```

### Uso

```
./instalar.sh                  # modo interactivo con whiptail
./instalar.sh -s|--sin-preguntar   # no pregunta nada, usa los valores por defecto
./instalar.sh -d|--diagnostico     # solo informa del estado de la máquina y sale
./instalar.sh -h|--ayuda           # imprime la cabecera de comentarios y sale
```

`-h/--ayuda` no es un `--help` genérico: literalmente hace
`sed -n '2,/^set -u/p' "$0" | sed '$d; s/^# \?//'`, es decir, imprime las
líneas de comentario entre la línea 2 y el `set -u` del propio fichero
(quitando el `# ` inicial). Es la cabecera de documentación del script, no un
texto aparte.

`-d/--diagnostico` es un modo de solo lectura para depurar una máquina remota:
imprime `/etc/os-release`, el listado de `$HOME` y de los directorios de
GroovyArcade si existen, qué ejecutables de frontend/emulador hay en el PATH
(y a qué apuntan si son symlinks), qué ficheros de `gasetup` mencionan
`attract`/`frontend`/`shared`, la configuración de MAME vía `-showconfig
-verbose` (rutas de rom/cfg/nvram/ini/bgfx/home/snapshot), y el estado de la
sesión gráfica (`DISPLAY`, `WAYLAND_DISPLAY`, `XDG_SESSION_TYPE`). Sale
inmediatamente después, sin instalar nada.

### Variables de entorno

Todas son opcionales; si no se fijan, el script las detecta o las pregunta.

| Variable | Efecto |
|---|---|
| `MAME` | Ruta al ejecutable de GroovyMAME. Si no se fija, se busca en varias rutas candidatas (ver más abajo) |
| `ROMS` | Carpeta con las roms. Si no se fija, se pregunta a MAME y se elige la que más roms tenga |
| `CREDITOS` | Ruta al repo/subcarpeta `creditos/` (con `creditos.lua` dentro) |
| `DESTINO` | Carpeta de configuración de Attract-Mode Plus (`~/.attract` normalmente, o `~/shared/frontends/attract` en GroovyArcade) |
| `TAREAS` | Lista de tareas a ejecutar, separadas por espacio (ver la tabla de tareas). Si se fija, **se salta el checklist de whiptail** |

`TAREAS="config romlist" ./instalar.sh --sin-preguntar` es, según el propio
comentario del script, "como se prueba sin ir tarea por tarea": permite
invocar una sola tarea sin pasar por todo el diálogo interactivo.

### Salvaguarda: no correr como root

Antes de nada, si `id -u` es 0 **y** hay `SUDO_USER` fijado (o sea, se invocó
con `sudo`), el script se niega a seguir e imprime en rojo el motivo: con
`sudo`, `HOME` pasa a ser `/root`, así que toda la configuración se escribiría
en `/root/.attract`, donde el frontend (que corre como el usuario normal)
jamás la ve. Además el sonido y la sesión gráfica son del usuario, no de root.
El propio script pide `sudo` él solo, únicamente para instalar paquetes.

### Diálogos: `whiptail` con salvedades

Cuatro funciones envuelven toda la interacción:

- **`hay_dialogo()`** — cierto solo si `PREGUNTAR=1` (no se pasó
  `--sin-preguntar`), la entrada y la salida son terminales interactivos
  (`-t 0`, `-t 1`), y `whiptail` está instalado. Si falta cualquiera de las
  tres condiciones, todo el resto cae a comportamiento "usa el defecto sin
  preguntar".
- **`d_texto`** (`titulo mensaje defecto`) — `whiptail --inputbox`; si no hay
  diálogo, o el usuario cancela, o deja el campo vacío, se queda con el
  defecto.
- **`d_si`** (`titulo mensaje defecto[si|no]`) — `whiptail --yesno` (con
  `--defaultno` si el defecto es "no"); sin diálogo, devuelve directamente si
  el defecto era "si".
- **`d_aviso`** (`titulo mensaje`) — `whiptail --msgbox`; sin diálogo, un
  `printf '%b\n'` en texto plano.

**Trampa documentada en el propio código:** `whiptail` interpreta cualquier
argumento que empiece por `-` como una opción de línea de órdenes, no como
texto del mensaje. El mensaje final del script (la lista de "queda por
hacer") empieza con una lista de guiones (`- El frontend no está...`), así que
sin cuidado `whiptail` respondería `- ...: unknown option` y no dibujaría
nada. La solución, repetida en `d_texto`, `d_si` y `d_aviso`, es anteponer un
salto de línea al mensaje cuando empieza por `-` (`case "$m" in -*) m=$'\n'"$m"
;; esac`).

### Detección de la máquina

1. **Gestor de paquetes** (`GESTOR`): se prueba `pacman`, `apt-get`, `dnf`,
   `zypper` en ese orden (el primero que exista en el PATH gana).
2. **Distro** (`DISTRO`): `PRETTY_NAME` de `/etc/os-release`.
3. **`whiptail` ausente**: si se puede preguntar por terminal pero no hay
   `whiptail`, se ofrece instalarlo **en texto plano** (todavía no hay con qué
   dibujar un cuadro). El paquete que lo trae varía: en Arch es `libnewt`, en
   las distros RPM es `newt`, en el resto se asume que el paquete se llama
   `whiptail`.
4. **GroovyArcade** (`ES_GROOVYARCADE`): se detecta por la **disposición de
   directorios**, no por el nombre de la distro — si existen
   `~/shared/frontends/attract` **y** `~/shared/roms`, se asume GroovyArcade.
   Esto significa que si alguien reproduce esa disposición de carpetas en otra
   distro, también se detecta como tal (a propósito).
5. **`ga.conf`**: en GroovyArcade se lee (nunca se escribe)
   `~/shared/configs/ga.conf`, que dice qué frontend lanza `gasetup`
   (`frontend=`), el tipo de monitor (`monitor=`) y el backend de vídeo
   (`video.backend=`). La función `ga_valor()` hace un `sed` sencillo
   `s/^clave=//p` sobre ese fichero.
6. **`DESTINO`**: en GroovyArcade, `$COMPARTIDO/frontends/attract`
   (`$COMPARTIDO=$HOME/shared`); si no, `$HOME/.attract`.
7. **`CREDITOS`**: se busca `creditos.lua` dentro de `$AQUI/creditos` o de
   `$AQUI/../groovyarcade-creditos` (el nombre del repo de antes de fundirse
   los dos), por si alguien tiene una copia de trabajo con la disposición
   vieja de dos repos.
8. **`MAME`**: se prueba, en orden, `$AQUI/../groovymame_src/mame`,
   `$HOME/groovymame_src/mame`, `/usr/local/bin/groovymame`,
   `/usr/bin/groovymame`, `/usr/bin/mame`, `/usr/games/mame` — el primero que
   sea ejecutable.
9. **`ROMS`** (si no se fijó): se construye una lista de rutas candidatas —
   primero **el `rompath` que declara el propio MAME** (vía `-showconfig`,
   expandiendo `$HOME` a mano porque `-showconfig` lo devuelve literal),
   partiendo por `;` (el rompath son VARIAS rutas), y luego varios defectos
   típicos (`/usr/share/games/mame/roms`, `~/roms`,
   `/usr/local/share/games/mame/roms`, `~/shared/roms/mame`). **No se elige la
   primera candidata que exista**, sino la que tenga **más roms** (contando
   `.zip`/`.7z` con `find -maxdepth 1`): el propio comentario explica que en
   una máquina real la primera ruta declarada tenía 11 juegos y la tercera
   104, así que "la primera que exista" habría elegido mal y en silencio. Si
   ninguna candidata tiene ninguna rom, se cae a la primera que simplemente
   exista.
10. La ruta de `MAME` se normaliza con `cd "$(dirname ...)" && pwd` para
    quitar cualquier `..`: esa ruta queda escrita tal cual en el `.cfg` del
    emulador y en `mame.ini`, y un `..` ahí sería frágil.

### Las tablas de dependencias, y cómo se resuelven por distro

Tres tablas de texto (variables multilínea), cada línea con columnas separadas
por espacios:

- **`LIBRERIAS`** — bibliotecas de compilación (X11, Xinerama, freetype,
  FFmpeg, etc.). Columnas: `módulo-de-pkg-config  paquete-debian
  paquete-arch`.
- **`HERRAMIENTAS`** — binarios que hacen falta para compilar/procesar
  (`git`, `make`, `g++`, `pkg-config`, `cmake`, `ffmpeg`, `curl`,
  `magick|convert`). Columnas: `binario(s)  debian  arch  fedora  opensuse`.
  La primera columna admite **alternativas separadas por `|`**: basta con que
  exista uno de los binarios listados. Es el caso de ImageMagick, que en su
  versión 7 dejó de instalar `convert` y solo trae `magick`.
- **`LIBRERIAS_EMULADOR`** — las `.so` de **ejecución** que necesita el
  binario de MAME para arrancar (SDL2, SDL2_ttf, SDL2_image, fontconfig,
  ALSA, PulseAudio, PipeWire). Estas no se detectan con `pkg-config` (eso mira
  cabeceras de compilación, no bibliotecas ya instaladas) sino con `ldd` sobre
  el propio binario.

**Por qué la primera columna es el módulo de pkg-config y no el nombre del
paquete:** el nombre de paquete cambia de una distro a otra, pero el módulo
`.pc` que declara una biblioteca no. Así que la comprobación de "¿ya está
instalado?" siempre es `pkg-config --exists <módulo>`.

**Truco para Fedora/openSUSE:** en las distros basadas en RPM, `rpm` genera un
"provides" virtual por cada `.pc` que instala un paquete, así que en vez de
mantener una columna de nombres para `dnf`/`zypper`, se pide directamente
`dnf install "pkgconfig(x11)"` o el equivalente de `zypper`, y es el propio
gestor quien busca qué paquete lo trae, sea cual sea su nombre. Solo las dos
tablas que no llevan `.pc` (`HERRAMIENTAS` y `LIBRERIAS_EMULADOR`) necesitan
de verdad las cuatro columnas de nombres.

**Funciones clave:**

- **`elige()`** (`de-que-fila deb arch fedora opensuse`) — según `$GESTOR`,
  devuelve la columna que toca; si esa columna está vacía para el gestor
  actual, avisa por `stderr` ("en la tabla, '<fila>' no tiene nombre de
  paquete para $GESTOR") y no rompe nada (solo esa dependencia queda sin
  traducir).
- **`hay_binario()`** — soporta `"nombre1|nombre2"`, cierto si cualquiera está
  en el PATH.
- **`paquetes_que_faltan()`** — recorre `LIBRERIAS` comprobando
  `pkg-config --exists`; para lo que falte, en `dnf`/`zypper` emite
  `pkgconfig(mod)`, en el resto usa `elige()`. Recorre `HERRAMIENTAS`
  comprobando `hay_binario`. Y si `$MAME` ya es ejecutable, añade también lo
  que devuelva `paquetes_del_emulador` (las `.so` de ejecución que le faltan a
  ESE binario concreto). Todo se pasa por `sort -u` al final.
- **`paquetes_del_emulador()`** (`$1`=binario, por defecto `$MAME`) — corre
  `ldd "$bin" | awk '/not found/{print $1}'`; para cada nombre de biblioteca
  que falte, busca en `LIBRERIAS_EMULADOR` por prefijo y traduce con
  `elige()`; lo que no está en la tabla se imprime igualmente por `stderr`
  como comentario (`# libX.so`), para no callárselo aunque no se sepa
  traducir. El comentario del código recuerda el síntoma real que motivó esto
  en Mint: `mame: error while loading shared libraries: libSDL2_ttf-2.0.so.0`,
  que hace que `-listxml` no devuelva nada y la lista de juegos salga vacía de
  datos, sin decir por qué.
- **`instalar_paquetes()`** — según `$GESTOR`:
  - **`pacman`**: primero **criba** los nombres con `pacman -Si` (o `-Sg` para
    grupos como `base-devel`), porque **pacman aborta la instalación ENTERA
    si un solo nombre no existe**. Si tras cribar no queda ninguno bueno,
    asume que la base de datos local está desincronizada y prueba
    `pacman -Sy --needed --noconfirm` directamente. Si la instalación de los
    "buenos" falla igualmente (404 en todos los espejos), no lo trata como
    fallo de red sino como base de datos vieja, y **pregunta** si hacer un
    `pacman -Syu` completo (nunca `-Sy` a secas, que dejaría el sistema a
    medias) — es una cabina que ya funciona, así que esa decisión la toma el
    usuario, no el script.
  - **`apt`**: `apt-get update && apt-get install -y`.
  - **`dnf`/`zypper`**: vía `instalar_rpm()`, que hace lo mismo que en
    pacman — criba antes con `lo_conoce()` (`dnf repoquery
    --whatprovides` / `zypper search --provides --match-exact`) y solo
    instala lo que el gestor reconoce, avisando de lo que no.

### `tarea_dependencias()`

Instala `pkg-config` primero si falta (hace falta para poder comprobar todo
lo demás). Calcula `paquetes_que_faltan()`; si no falta nada, termina. Si
falta algo y no hay gestor reconocido, avisa de instalar a mano y devuelve
fallo. Si hay gestor, pregunta confirmación (`d_si`) y, si se acepta, instala.
**Vuelve a comprobar después de instalar**: si algo sigue sin aparecer, avisa
de que puede llamarse distinto en esta distro (en vez de fallar la
compilación más tarde sin explicación). Por último, la "prueba de fuego": si
`$MAME` es ejecutable, comprueba que `"$MAME" -version` funcione de verdad; si
no, avisa con las primeras líneas de su salida de error.

### Las tareas (`tarea_*`)

Cada tarea es una función independiente, invocada solo si `hace <nombre>`
(que mira si `" $TAREAS "` contiene `" <nombre> "`) es cierto. El orden de
ejecución en el guion principal es **fijo**, no el de la selección del
usuario, y respeta las dependencias entre tareas:

```
deps → compilar → binario → descargar → mame → config → crt → audio →
salida → escritorio → teclado → romlist → arte → videos
```

| Tarea | Qué hace, en una frase |
|---|---|
| `deps` | Instala las dependencias que falten (ver arriba) |
| `compilar` | Compila Attract-Mode Plus desde este repo |
| `binario` | Instala el `attractplus` compilado como el binario del sistema |
| `descargar` | Baja un GroovyMAME ya parcheado y compilado (release de GitHub) |
| `mame` | Aplica los parches de `parches/` y compila GroovyMAME desde `../groovymame_src` |
| `config` | Instala plugins, layout, módulos, `.cfg` del emulador, `plugins.cfg`, `displays.cfg` |
| `crt` | Ajusta el shader, `mame.ini`, el driver de X, la resolución del CRT para un monitor de tubo |
| `audio` | Fuerza la salida de sonido a la placa base, no a un mando USB |
| `salida` | Edita `~/.xinitrc` para apagar el panel interno y usar el CRT como única pantalla |
| `escritorio` | Arregla el escritorio LXDE de GroovyArcade (bug de permisos en `/dev/tty12`) |
| `teclado` | Pone la distribución de teclado que corresponde al idioma del sistema |
| `romlist` | Construye la lista de juegos de Attract-Mode |
| `arte` | Descarga marquesinas/capturas y corrige su proporción |
| `videos` | Graba los vídeos de muestra (`videos.sh`, ~10 minutos) |

Detalle de cada una:

**`tarea_compilar()`** — Antes de compilar, repara una trampa conocida: la
SFML que AM+ compila aparte (`obj/sfml/install`) deja su ruta **absoluta**
grabada dentro de sus `.pc` de pkg-config; si el repo se movió de carpeta
después de una compilación anterior, ese `prefix=` apunta a un sitio que ya no
existe y el compilador cae silenciosamente a la SFML 2.x del sistema, dando un
error de compilación que no menciona SFML en absoluto
(`'getMaximumAntiAliasingLevel' is not a member of 'sf::RenderTexture'`, con
otra mayúscula en la versión 2.x). Se corrige con un `sed` que reescribe
`prefix=` en todos los `.pc` de esa carpeta si no coincide con la ruta actual.
Luego compila con `make -jN` (N = `nproc`), envolviendo la orden en
`env PATH=/usr/lib/ccache:$PATH` y `mold -run` si están instalados (baja la
compilación de unos 8 minutos a 2).

**`tarea_descargar()`** — Baja un GroovyMAME **ya compilado** (no las
fuentes) desde un release fijo de GitHub
(`https://github.com/Kotaix0807/attractplus-creditos/releases/download/groovymame-0.289-cabina`).
Antes de bajar nada, comprueba la versión de glibc del sistema
(`ldd --version`) contra el mínimo que exige el binario (2.38), comparando con
`sort -VC` (orden de versión); si es menor, avisa en rojo que hay que
compilar (tarea `mame`) y no baja los 81 MB para nada. Si la máquina es
GroovyArcade, avisa de que la distro ya trae su propio GroovyMAME hecho a
medida y que este es "genérico" de Ubuntu. Descarga el binario y los shaders
`bgfx` a un directorio temporal, los extrae a
`$HOME/.local/share/groovymame-cabina/` (bgfx **al lado** del binario, porque
MAME lo busca relativo a su directorio de trabajo). Comprueba las bibliotecas
de ejecución que le faltan a **ese binario concreto** (no al del sistema) con
`paquetes_del_emulador "$casa/mame"`, y si faltan, ofrece instalarlas.
Finalmente verifica que arranque con `-version`; si no, avisa y falla. Si
todo va bien, deja `MAME="$casa/mame"` para que el resto del instalador use
ese binario.

**`tarea_mame()`** — Aplica los parches de `parches/*.patch` sobre
`../groovymame_src` con `patch -N` (no falla si ya estaban aplicados, solo
avisa "ya estaba puesto") y compila con `make -jN NOWERROR=1 USE_QTDEBUG=0`
(con ccache si existe). Si no encuentra las fuentes, se salta la tarea sin
fallar, y si además detecta GroovyArcade, recuerda que ahí el camino es
`./parches/compilar-en-arch.sh`, que no toca el GroovyMAME de la distro.

**`tarea_binario()`** — Instala el `attractplus` recién compilado como el
binario del sistema, en la ruta que devuelva `command -v attractplus` (o
`/usr/local/bin/attractplus` si no hay ninguno). **Trampa importante y
documentada:** en GroovyArcade, `/usr/local/bin/attractplus` **no es un
binario, es un guion de ocho líneas** que elige entre `attractplus-kms` y
`attractplus-x11` según haya `$DISPLAY`. El script lo detecta mirando si los
dos primeros bytes del destino son `#!`, y si es así, **no lo sobrescribe**:
en su lugar instala en `<destino>-x11` (avisando de que si la cabina arranca
sin X haría falta compilar con `USE_DRM=1` para tener también un
`-kms`). Si el destino existente no es un guion, hace copia de seguridad una
sola vez (`<destino>.antes_instalar`, solo si aún no existe) antes de
sobrescribir con `install -m 755`.

**`tarea_config()`** — La tarea que más ficheros toca. En orden:

1. Crea la estructura de `$DESTINO` (`config/plugins/emulators/layouts/
   romlists/scraper/modules`).
2. Copia **todos** los `.nut` de `config/plugins/` (los propios y los de
   serie de AM+ como `KonamiCode`, no solo `Creditos.nut`).
3. Borra y reinstala entero `layouts/Arcade-UMAG` (`rm -rf` + copia).
4. Copia los módulos de `config/modules/` (`fade`, `animate`...), sin los
   cuales el layout falla con un error que no menciona que falta un módulo.
5. Genera `emulators/groovymame.cfg` a partir de la plantilla
   `config/cabina/groovymame.cfg`, sustituyendo `@MAMEDIR@`, `@CREDITOS@` y
   `@ROMS@` con `sed`. Hace copia de seguridad del `.cfg` anterior si existía.
6. Genera `config/plugins.cfg` igual, sustituyendo `@CREDITOS@`.
7. Copia `config/cabina/displays.cfg` a `$DESTINO/config/displays.cfg`
   **solo si no existe ya** (`copiar_si_falta`): si ya había uno (por ejemplo
   el de fábrica de GroovyArcade), se respeta.
8. **Comprobación de que algún display use un layout nuestro:** si el
   `displays.cfg` que había ya (paso 7) no usa ninguno de los layouts
   instalados en `$DESTINO/layouts/`, el frontend arrancaría con "otra cara"
   sin decir por qué (le pasó a GroovyArcade, cuyo `displays.cfg` apuntaba a
   `BasicPlus`, de serie). Se pregunta si parchear el display cuya lista de
   roms es `groovymame` para que use `Arcade-UMAG`, con un `awk` que reescribe
   solo la línea `layout` de ese bloque concreto (localizado por su
   `romlist`, no por el nombre del display, que puede ser cualquiera).
9. **Comprobación de displays que apuntan a un emulador inexistente:** cada
   `display` del `displays.cfg` referencia una lista (`romlist`); esa lista
   (`$DESTINO/romlists/<lista>.txt`) declara en su segunda línea, tercera
   columna separada por `;`, el nombre del emulador. Si ese
   `emulators/<emu>.cfg` no existe, AM+ mostrará el display pero **fallará al
   lanzar** con "Error getting emulator info for launch", sin decir cuál ni
   por qué. Se ofrece quitar esos displays rotos (de nuevo con `awk`,
   localizándolos por su `romlist`).
10. **Enlace `~/.attract`**: si `$DESTINO` no es ya `~/.attract` (caso
    GroovyArcade), hace falta que `~/.attract` sea un symlink a `$DESTINO`,
    porque AM+ busca su configuración ahí y solo ahí. Si `~/.attract` ya es un
    symlink, lo reapunta (`ln -sfn`); si no existe, lo crea; si existe pero
    **no** es un symlink (un directorio de verdad), se respeta y solo se
    avisa.

**`tarea_romlist()`** — `./attractplus --build-romlist groovymame -o groovymame`.
El `-o` es imprescindible: **sin él, AM+ no sobrescribe** la lista existente,
sino que crea `groovymame1.txt`, `groovymame2.txt`... y el frontend sigue
usando la vieja.

**`tarea_crt()`** — La tarea más larga y con más ramificaciones, pensada para
un CRT (tubo de rayos catódicos), no un panel plano:

- Si `ga.conf` dice `video.backend=KMS`, primero se pregunta si conviene pasar
  a X: bajo KMS no hay shader posible (bgfx no soporta KMSDRM), así que las
  scanlines dependen de que switchres genere el modo nativo del juego, cosa
  que solo funciona en un **monitor de recreativa** de verdad (15/25/31 kHz de
  los de switchres), no en un CRT de PC o multisync VGA. Si se acepta el
  cambio, se edita `ga.conf` con `sed` (`video.backend=X`) y se hace copia de
  seguridad.
  - Si se queda en KMS, se escriben en el `mame.ini` que corresponda (vía
    `mame_ini()`) las claves: `video opengl`, `bgfx_screen_chains` vacío,
    `switchres 1`, `switchres_ini 0` (si no, `/etc/switchres.ini` manda sobre
    `mame.ini`), `autosync 0`, `dotclock_min 25`. Se sale de la tarea aquí.
- Si el backend es X: localiza `bgfx_path` (vía `mame_opcion`) y el `mame.ini`
  que manda de verdad (vía `mame_ini()`, ver más abajo). Copia
  `crt-real.json` y `crt-lite.json` a `<bgfx>/chains/` (con `sudo` si esa
  carpeta no es escribible, como en GroovyArcade donde pertenece a `root`).
- Pregunta qué shader usar por defecto: `crt-real` (modela el haz del tubo,
  mejor pero más caro) o `crt-lite` (solo dibuja las líneas, mucho más
  barato). El diálogo tiene como **defecto "no"** a la pregunta "¿usar el
  ligero?", así que si no hay diálogo (`--sin-preguntar`) o se cancela, se
  queda `crt-real`.
- Escribe en `mame.ini`: `video bgfx`, `bgfx_screen_chains <cadena
  elegida>`, `resolution auto`, `verbose 0` (evita cientos de líneas por
  arranque que en KMS acabarían en `attract.log`), `aspect 4:3` (el tubo es
  4:3 físico aunque el modo de vídeo sea 5:4), `waitvsync 0` — **y este último
  es deliberado, no un descuido**: el comentario explica que encenderlo mata
  el arranque acelerado, porque el vsync bloquea cada fotograma hasta el
  barrido del monitor y la emulación no puede superar los 60 Hz del monitor
  aunque `creditos.lua` quite el freno, con una tabla de mediciones que
  muestra cómo los juegos por debajo de 60 Hz ganaban algo con vsync y los de
  60,6 Hz no ganaban nada (de ahí el síntoma "a veces funciona y a veces no").
  Si `bgfx_path` se encontró, se escribe también.
- Pregunta si el monitor es de recreativa (para dejar switchres encendido,
  que genera modelines nativos) o un CRT de PC/multisync VGA (para
  **apagarlo**, `switchres 0`, porque en un tubo de PC genera modos que no
  encajan y hace que los juegos vayan al doble de velocidad — con una tabla de
  ejemplo: Mappy a 661x496 y 222% de velocidad).
- Busca la resolución óptima del CRT: localiza la salida conectada que no sea
  interna (excluye `LVDS*/eDP*/DSI*`), lee sus modos soportados de
  `/sys/class/drm/.../modes`, y si `~/.xinitrc` ya tiene una línea `xrandr
  --output <salida>` (fijada por la tarea `salida`), ofrece añadir `--mode
  <el de más líneas>` a esa línea (más líneas = más píxeles por línea de
  juego = mejor dibuja el shader las scanlines). Avisa de que los modos altos
  suelen ir a 60 Hz y que un CRT de PC a 60 Hz parpadea más que a 85.
- **El driver de X**: si detecta una GPU NVIDIA por PCI y existe
  `modesetting_drv.so`, ofrece escribir
  `/etc/X11/xorg.conf.d/20-modesetting.conf` forzando el driver `modesetting`
  con `AccelMethod glamor` y `DRI 3`. El motivo, documentado con una tabla de
  medición: con una NVIDIA, Xorg elige por defecto el DDX viejo `nouveau`, que
  solo da DRI2 (cada fotograma se copia a través del servidor X), y eso deja
  varios juegos muy por debajo del 100% de velocidad; con `modesetting`+glamor
  todos llegan al 100%. La prueba de que no era un problema de relleno de
  píxeles: con `-video none` todos iban al 100%, así que el cuello de botella
  estaba en la subida del bitmap/intercambio de buffers, no en la emulación.
- **Limpieza de `.cfg` por juego**: si `cfg_directory` existe y tiene
  ficheros `.cfg`, corre un script Python **embebido** (aquí dentro del
  propio `instalar.sh`, vía heredoc) que, con expresiones regulares, quita de
  cada `.cfg`: el bloque `<bgfx>...</bgfx>` completo, los atributos
  `scalemode="N"` y `keepaspect="N"` de cualquier `<target>`, y los bloques
  `<video><target index="0"/></video>` vacíos. El motivo: switchres
  reescribe esos atributos en cada arranque con sus propias decisiones
  (`autostretch`), y de otro modo quedarían grabados como si fueran
  preferencias del usuario, cuando en realidad eran ruido de switchres.

**`tarea_audio()`** — Fuerza que el sonido salga por la tarjeta de sonido
integrada de la placa base, no por un mando USB que Linux también enumera
como tarjeta de sonido (síntoma real documentado: el mando de PS4 se registra
como `USB-Audio` y se queda con el índice de tarjeta que el `~/.asoundrc`
tenía fijado a mano). Localiza la primera tarjeta de `/proc/asound/cards` que
**no** sea `USB-Audio` con un `awk` sobre el formato `N [ID  ]: descripción`.
Genera `~/.asoundrc` a partir de la plantilla `config/cabina/asoundrc`
sustituyendo `@CARD@` por ese identificador (con `dmix` para que frontend y
emulador puedan sonar a la vez). Si no encuentra ninguna tarjeta no-USB, avisa
y no toca nada. Si el fichero resultante es idéntico al que ya había, no hace
nada (evita "tocar" sin necesidad); si no, hace copia de seguridad del
anterior.

**`tarea_salida()`** — Edita `~/.xinitrc` para que, si hay dos pantallas
conectadas (una interna tipo `LVDS`/`eDP`/`DSI` y una externa), la externa (el
CRT) quede como pantalla primaria y la interna se apague **al arrancar X**,
antes de lanzar el frontend. Sin esto, X enciende las dos y pone la interna de
primaria, así que el frontend se abre ahí y en el CRT solo se ve el fondo del
escritorio. Si solo hay una pantalla (o ninguna combinación interna+externa),
"no hay nada que decidir" y no toca nada. El bloque de shell que inserta (vía
un script Python embebido) es:

```bash
if xrandr --query | grep -q "^{crt} connected" ; then
    xrandr --output {crt} --primary --pos 0x0 --output {panel} --off
fi
```

y se inserta **justo antes** de la línea que lanza el frontend, buscando
alguno de tres marcadores en `~/.xinitrc`: `/opt/galauncher/startfe-X.sh`,
`exec `, o `attractplus` (el primero que aparezca); si no encuentra ninguno,
lo añade al final del fichero.

**`tarea_escritorio()`** — Arregla un fallo específico de GroovyArcade: su
`/opt/galauncher/startfe-X.sh` redirige el registro de LXDE con
`startlxde &> /dev/tty12`. En Arch, la regla de udev deja **todas** las
terminales virtuales en modo `0600 root:tty`, y `systemd` solo cede la
terminal de la sesión activa al usuario — `tty12` no es de nadie, así que el
usuario no puede escribir ahí. Y `bash` **no ejecuta la orden** cuando la
redirección de salida falla, así que `startlxde` nunca llega a arrancar, el
guion sale con error y X se cierra entero. El síntoma que se ve es "el
escritorio revienta y vuelve a `gasetup`", que no apunta para nada a un
problema de permisos de terminal. La tarea comprueba si el fichero de la
distro sigue con ese patrón (si no, ya está arreglado y no hace nada), y si
está, con `sudo sed -i` lo cambia a redirigir a `"$LOG_DIR"/lxde.log` (como
hacen los otros ocho frontends del mismo fichero), haciendo copia de
seguridad. **Aviso explícito en el código**: es un fichero de la distro, así
que una actualización del paquete lo deshace sin avisar, y hay que repasarlo.

**`tarea_teclado()`** — Si `localectl status` dice que el `X11 Layout` está
`(unset)`, deduce el teclado que corresponde al idioma del sistema
(`System Locale`) con una tabla de casos (`es_ES→es/es`, `es_*→latam/la-latin1`,
`pt_BR*→br/br-abnt2`, `pt_*→pt/pt`, `fr_*→fr/fr`, `de_*→de/de`, `it_*→it/it`,
`en_GB*→gb/uk`, `en_*→us/us`; cualquier otro idioma no reconocido se deja tal
cual, avisando). Si ya hay algo puesto, no toca nada. Aplica con
`localectl set-x11-keymap` y `set-keymap`, avisando de que solo surte efecto
al arrancar la sesión gráfica, no en caliente.

**`tarea_arte()`** — Si el frontend está compilado, lanza
`./attractplus --scrape-art groovymame` (el scraper propio de AM+, que para
GroovyMAME usa `adb.arcadeitalia.net` en vez de `thegamesdb.net`, ver
CLAUDE.md) y, si existe, llama a `creditos/aspecto.sh` para corregir la
proporción de lo que se acaba de descargar.

**`tarea_videos()`** — Simplemente `( cd "$CREDITOS" && ./videos.sh )`, sin
argumentos (graba todos los juegos de la lista).

### El flujo principal: preguntas, checklist y ejecución

1. Muestra un resumen inicial (`d_aviso`) con distro, gestor, rutas
   detectadas.
2. Pregunta (o toma el valor por defecto) `CREDITOS`, `MAME`, `ROMS`,
   `DESTINO` con `d_texto`.
3. **`insistir()`**: en vez de abortar si una ruta no es válida, vuelve a
   preguntar hasta 10 veces (mostrando el valor incorrecto anterior), y solo
   si no hay diálogo posible (o se agotan los intentos) devuelve fallo. Se
   usa para `CREDITOS` (validado con `hay_creditos`: existe `creditos.lua`
   dentro) y `MAME` (validado con `hay_emulador`: es ejecutable); si cualquiera
   de los dos sigue sin ser válido tras insistir, el script **aborta** —sin
   `creditos.lua` no hay qué lanzar, sin emulador no hay nada que configurar.
4. **`ROMS`** se trata distinto: si no es válida, se puede **dejar vacía a
   propósito** (`SIN_ROMS=1`) y seguir sin ella (se saltan las tareas
   `romlist`, `arte` y `videos`). La validación (`hay_roms`) no se conforma
   con que la carpeta exista: exige que tenga de verdad un `.zip`, un `.7z`, o
   una carpeta con un `.chd` dentro (hasta `-maxdepth 2`, para roms tipo CPS3
   que van en carpeta). **Motivo documentado**: el token `<DIR>` en `romext`
   hace que AM+ trate cualquier subcarpeta como si fuera un juego, así que
   apuntar a un `$HOME` cualquiera generó 36 "juegos" con nombres como
   `.config`, `Descargas`, `.ssh`.
5. Se calculan los valores por defecto del checklist: `compilar` se marca ON
   si `attractplus` **no** está ya compilado; `binario` solo ON en
   GroovyArcade; `escritorio` ON solo si el bug de `tty12` sigue presente;
   `teclado` ON solo si el teclado X11 sigue sin configurar; `audio` solo ON
   en GroovyArcade.
6. Si `TAREAS` no viene fijado por entorno, se arma un valor por defecto
   (`"deps config romlist arte"` más `compilar`/`binario`/`audio` según los
   defectos anteriores) y, si hay diálogo, se sustituye por lo que el usuario
   marque en un `whiptail --checklist` con las 14 tareas (con sus
   descripciones y su marca ON/OFF de partida).
7. Si `SIN_ROMS=1`, se filtran de `TAREAS` las entradas `romlist`, `arte` y
   `videos` con un `grep -v` sobre la lista partida por espacios.
8. Se ejecutan las tareas **en el orden fijo** documentado arriba (no en el
   orden en que aparecen en `TAREAS`), acumulando un contador `fallos`. Si
   `deps` falla, se pregunta explícitamente (defecto "no") si seguir de todas
   formas, porque compilar sin dependencias fallaría con un error que no
   dice que el problema son las dependencias.

### La sección "Revisión"

Al final, antes del resumen, hace una serie de comprobaciones de solo lectura
para detectar problemas que **no dan la cara hasta mucho después**:

- ¿Arranca `$MAME -version`? Si no, avisa de que sin esto `-listxml` no
  devuelve nada y la lista de juegos sale vacía de datos.
- Si hay `romlists/groovymame.txt`, cuenta las líneas (menos la cabecera) y
  comprueba con `awk -F';' 'NR>1 && $1==$2'` cuántas filas tienen el nombre
  del juego igual a su título — eso pasa cuando MAME no llegó a ejecutar
  `-listxml` de verdad, así que la "lista" tiene nombres pero cero datos.
- En GroovyArcade: si `ga.conf` dice que `frontend=` no es `attractplus`,
  avisa; si la tarea `crt` se marcó y `monitor=lcd`, avisa de que switchres no
  generará modelines de recreativa con ese ajuste.
- Repite (solo para avisar, sin arreglar) la comprobación de displays que
  apuntan a un emulador no definido.
- Comprueba si el `attractplus` del PATH es realmente el mismo fichero que el
  compilado en este repo (`-ef`).
- Comprueba que `~/.attract` sea un symlink cuando `$DESTINO` es distinto.
- Comprueba que haya sesión gráfica (`$DISPLAY`/`$WAYLAND_DISPLAY`); si no,
  avisa de que AM+ abortará con "Failed to open X11 display" sin más
  explicación.

### El resumen final

Construye una cadena `pendiente` con lo que quedó por hacer (compilar si no
está compilado, construir la romlist si no se hizo, grabar los vídeos si no
se hizo) y **siempre** añade dos pasos que el script no puede automatizar
porque exigen estar delante de la cabina: mapear el botón físico de moneda
(en el **general**, `Input Assignments (General) > Coin 1`, nunca por juego,
porque un mapeo propio del juego deja sin efecto el cerrojo del monedero —
ver CLAUDE.md, "El cerrojo falla en los juegos con mapeo propio de la
moneda"), y dónde está el menú de ajustes de arranque (`Configure > Plug-ins
> Arranque`).

Por último, si no encuentra `hi2txt-xml` en ninguna de las rutas conocidas
(`$HI2TXT_DB`, `~/hi2txt-xml/src/main/db`, `~/.mame/hi2txt/db`,
`/usr/share/hi2txt/db`), añade una explicación de qué es (una base de datos
de terceros, GPL-2, para el sistema de puntuaciones), por qué **el instalador
no la descarga él mismo** (es código ajeno, cambia sin control nuestro, y su
licencia no es la de este proyecto) y cómo clonarla a mano si se quiere.

Termina imprimiendo en rojo `Termino con N paso(s) fallidos` o en verde
`Instalado.`, y muestra el texto `pendiente` en un `d_aviso` final.

---

## `cabina.sh`

**Propósito en una frase:** el lanzador "de verdad" de la cabina — pone el CRT
como pantalla única antes de arrancar el frontend, y devuelve el escritorio a
como estaba al salir, pase lo que pase.

### Uso

```bash
./cabina.sh          # arranca la cabina
```

No admite argumentos propios, pero **reenvía todos los que reciba** a
`attractplus` (`./attractplus "$@"`), así que se le puede pasar cualquier
opción que entienda el frontend (por ejemplo `--config`).

### Variables de entorno

Ninguna propia. Solo lee `$DISPLAY` y `$WAYLAND_DISPLAY` para comprobar que
hay sesión gráfica.

### Recorrido paso a paso

1. `cd "$( dirname "$( readlink -f "$0" )" )"` — se sitúa en su propio
   directorio real (resolviendo symlinks), así que da igual desde dónde se
   invoque.
2. Si ni `$DISPLAY` ni `$WAYLAND_DISPLAY` están puestos, imprime un mensaje de
   error con las tres causas típicas y sale con código 1, **en vez de dejar
   que `attractplus` aborte solo**. El motivo, documentado en el comentario:
   AM+ no avisa de esto — aborta con un volcado de memoria (`core dump`) y una
   sola línea ("Failed to open X11 display"), que no dice nada útil. Las tres
   causas que sugiere: estar en una consola de texto (recomienda volver a la
   gráfica con Ctrl+Alt+F1/F2), haber entrado por SSH sin `-X` (`DISPLAY` no
   viaja solo), o estar en una sesión Wayland sin Xwayland (ahí hace falta una
   sesión Xorg).
3. Define `restaurar() { ./pantalla.py escritorio; }` y la engancha con
   `trap restaurar EXIT INT TERM` — se ejecuta **siempre** al terminar el
   script, sea porque `attractplus` salió normal, porque lo mataron, o porque
   alguien pulsó Ctrl+C.
4. Llama a `./pantalla.py cabina`; si falla, sale (`exit 1`) sin llegar a
   lanzar el frontend.
5. `sleep 1` — un margen para que el cambio de pantalla surta efecto antes de
   que la ventana de AM+ se cree.
6. `./attractplus "$@"` — lanza el frontend en primer plano (no `exec`: el
   `trap` de salida necesita que el script siga vivo para ejecutarse después).

### Qué otros ficheros/scripts invoca

- **`./pantalla.py`** (Python, fuera del alcance de este documento): con el
  subcomando `cabina` deja el CRT como única pantalla activa antes de
  arrancar, y con `escritorio` devuelve la disposición de pantallas que había
  antes. No es un script de shell y no se documenta aquí en detalle, pero es
  la pieza que de verdad hace el trabajo de este script.
- **`./attractplus`**: el frontend compilado, en el mismo directorio.

### Por qué existe (la trampa que resuelve)

El comentario de cabecera lo explica: bajo GNOME Wayland, el gestor de
ventanas (`mutter`) decide dónde cae cada ventana y **ignora** las órdenes de
posicionamiento del cliente X (`setPosition()`), así que no hay forma directa
de garantizar que Attract-Mode caiga en el CRT si hay más de una pantalla
disponible. La única forma fiable es que **no haya otro sitio donde caer**:
por eso `pantalla.py cabina` deja el CRT como pantalla única mientras dura la
sesión, y `pantalla.py escritorio` restaura la disposición normal (con las dos
pantallas, u otra) al salir. En una sesión Xorg pura esto no haría falta
(`xrandr` sí manda ahí), pero tampoco estorba dejarlo puesto.

---

## `pantalla-auto.sh`

**Propósito en una frase:** un servicio (opcionalmente `systemd`) que vigila
si hay un CRT enchufado al conector VGA y manda la imagen ahí automáticamente,
o al panel interno del portátil-chasis si no lo hay — pensado para no tener
que tocar nada a mano al conectar/desconectar el tubo.

### Uso (subcomandos)

```
./pantalla-auto.sh estado          # qué ve ahora mismo, sin tocar nada
./pantalla-auto.sh una-vez         # decide y aplica una sola vez
./pantalla-auto.sh vigilar         # se queda en bucle vigilando (lo que corre el servicio)
sudo ./pantalla-auto.sh crt        # fuerza el vídeo al CRT, a mano
sudo ./pantalla-auto.sh panel      # fuerza el vídeo al panel interno, a mano
sudo ./pantalla-auto.sh instalar   # instala el binario + el .service de systemd
sudo ./pantalla-auto.sh desinstalar
sudo ./pantalla-auto.sh pausar     # el servicio sigue vivo pero no toca nada
sudo ./pantalla-auto.sh reanudar
```

Sin subcomando, el valor por defecto es `estado` (`case "${1:-estado}" in`).
Un subcomando desconocido imprime la cabecera de comentarios (líneas 2-30) y
sale con código 1.

`crt`, `panel`, `instalar`, `desinstalar`, `pausar` y `reanudar` exigen ser
root (`necesita_root()`, que comprueba `id -u = 0` y si no, sale con "esto
necesita root: usa sudo"). `estado`, `una-vez` y `vigilar` no exigen root
(aunque `una-vez`/`vigilar` sí necesitan permisos para escribir en
`/sys/class/drm/.../status`, que en la práctica implica correr como root o
con los permisos que dé el `systemd` service, que corre como root).

### Variables de entorno / configuración

Se pueden fijar por entorno **o** en `/etc/pantalla-auto.conf` (se hace
`source` de ese fichero si existe, así que sus valores pisan a los del
entorno si se definieron ahí):

| Variable | Por defecto | Efecto |
|---|---|---|
| `EXTERNA` | `VGA-1` | El conector del CRT |
| `INTERNA` | `LVDS-1` | El conector del panel interno (el portátil que hace de chasis) |
| `INTERVALO` | `4` | Segundos entre comprobaciones del bucle `vigilar` |
| `CONFIRMAR` | `2` | Lecturas iguales seguidas que hacen falta antes de aplicar un cambio (antirrebote de cable) |
| `MODO_EXTERNA` | (vacío) | Modo de vídeo a forzar en el CRT al encenderlo. Vacío = no tocar la resolución si ya está encendida, o usar `--auto` si hay que encenderla |
| `MODO_INTERNA` | (vacío) | Lo mismo para el panel |
| `FRENO` | `/etc/pantalla-auto.off` | Fichero cuya sola existencia pausa el servicio |

`CONF=/etc/pantalla-auto.conf` y `UNIDAD=/etc/systemd/system/pantalla-auto.service`
son rutas fijas, no configurables.

### Por qué hace falta forzar el conector, no basta con `xrandr`

Explicado en la cabecera del propio script, y es la razón de ser de todo el
resto: la cabina arranca con `video=VGA-1:e video=LVDS-1:d` en la línea de
arranque del kernel. Ese `:d` **deshabilita el panel interno a nivel de
kernel** — aparece como `disconnected` en `/sys/class/drm` y **X no lo ve en
absoluto**. No es que esté apagado y se pueda encender con `xrandr`: no
existe para X. Por eso el primer paso siempre es tocar el conector (escribir
en su `status`), y `xrandr` viene después, solo si X está corriendo.

Lo bueno: esto se puede deshacer **en caliente**, sin tocar GRUB ni reiniciar
— escribir `on` en el `status` del conector lo devuelve a la vida (comprobado:
pasa a `connected` y ofrece su modo nativo).

Y al revés: apagar el conector que no se usa (en vez de solo `xrandr --off`)
evita un fallo real de AM+ documentado en CLAUDE.md — una salida `connected`
pero sin CRTC asignado hace que AM+ pida `XRRGetCrtcInfo(0)` y reviente con
`BadRRCrtc`. Dejando esa salida `disconnected` a nivel de kernel, X ni la
considera, así que ese fallo no puede darse.

### Recorrido de las funciones internas

- **`dir_de(n)`** — busca `/sys/class/drm/card*-<n>` con comodín, porque el
  número de tarjeta (`card0`, `card1`...) **no es estable**: cambió entre la
  cabina vieja (NVIDIA = `card0`) y la nueva (Intel = `card1`).
- **`estado_de(n)`** — lee el fichero `status` de ese conector (`connected`,
  `disconnected`, o `ausente` si no se encuentra el directorio).
- **`forzar(n, on|off|detect)`** — escribe ese valor en `status`. `detect` le
  pide al kernel que vuelva a comprobar de verdad la línea física.
- **`hay_crt()`** — hace `forzar EXTERNA detect`, espera 1 s, y comprueba si
  quedó `connected`. **Comentario importante**: el VGA no tiene una señal de
  "me han enchufado" fiable (no hay hot-plug detect utilizable), así que no
  vale esperar un evento — hay que forzar la comprobación cada vez. Verificado
  en la cabina que esto es una detección real y no el forzado del kernel:
  quitando el `:e` de la línea de arranque, el conector sigue dando
  `connected` con un EDID válido de 128 bytes.
- **`display_vivo()`** — busca el proceso `Xorg` en marcha con
  `pgrep -a -x Xorg` y extrae su número de display (`:0`, `:1`...) de la línea
  de órdenes con un `grep -oE ' :[0-9]+'`. Si no hay ningún Xorg corriendo,
  devuelve fallo.
- **`xr(display, args...)`** — envuelve `xrandr` fijando `DISPLAY` al valor
  dado y `XAUTHORITY` a `/home/arcade/.Xauthority` si no viene ya en el
  entorno (root puede hablar con la sesión gráfica del usuario `arcade`
  porque `~/.xinitrc` hace `xhost +`; el `XAUTHORITY` es un cinturón extra por
  si algún día deja de estarlo).
- **`arg_modo(conector, modo, display)`** — decide qué argumento de modo
  pasarle a `xrandr`, siguiendo la regla de "menor sorpresa": si esa salida
  **ya está encendida con un modo** (se comprueba con `xrandr --query | grep`),
  no se toca nada (devuelve cadena vacía); si hay que encenderla y no se pidió
  un modo concreto, usa `--auto` (el preferido del EDID); si se pidió un modo
  concreto, comprueba que esté en la lista de modos soportados por ese
  conector (`/sys/.../modes`) antes de usarlo, y si no está, cae a `--auto`
  avisando por `stderr`.
- **`aplicar(destino, apagar, modo)`** — el núcleo del cambio. Primero
  enciende el destino (`forzar destino on`), espera 1 s, y comprueba que
  quedó `connected`; **si no**, no hace nada más y devuelve fallo (para no
  dejar la cabina sin ninguna imagen si el destino resultó no estar
  disponible). Solo entonces apaga el otro (`forzar apagar off`). Si hay un
  Xorg vivo, espera 1 s más (para que se entere del cambio de conector) y
  aplica **una sola orden de `xrandr`** que hace las dos cosas a la vez
  (`--output destino --primary ... --output apagar --off`) — deliberadamente
  atómica, para que nunca haya un instante intermedio con las dos salidas
  apagadas. Si no hay Xorg corriendo, se limita a dejar el conector listo
  para cuando arranque.
- **`al_crt()` / `al_panel()`** — envoltorios de `aplicar()` con los conectores
  en cada sentido.

### Los subcomandos

- **`cmd_estado`** — imprime el estado de los dos conectores, si hay Xorg
  corriendo (y en qué display), si el fichero de freno está puesto, y el
  estado del servicio `systemd` (`is-enabled`/`is-active`) si está instalado.
- **`cmd_una_vez`** — si el freno está puesto, no hace nada; si no, decide con
  `hay_crt` y aplica una vez.
- **`cmd_vigilar`** — el bucle infinito que ejecuta el servicio. En cada
  vuelta: si el freno está puesto, avisa una vez (no en cada vuelta) y espera
  sin más. Si no, calcula el estado actual (`crt` o `panel`); para protegerse
  de un cable flojo que parpadee, exige leer el **mismo** valor
  `CONFIRMAR` veces seguidas antes de considerarlo un cambio real. También
  vigila si `display_vivo()` cambió (X se reinició o apareció) **aunque el
  cable no se haya movido**: si el servicio arranca antes que Xorg —que es lo
  normal al arrancar la cabina—, la parte de `xrandr` de `aplicar()` no llegó
  a ejecutarse la primera vez, y sin esta comprobación nunca lo reintentaría.
  Cuando hay motivo para actuar, llama a `al_crt`/`al_panel` y recuerda el
  último estado aplicado y el último `display_vivo` visto.
- **`cmd_instalar`** — copia el propio script a
  `/usr/local/bin/pantalla-auto.sh`, crea `/etc/pantalla-auto.conf` con los
  valores actuales (solo si no existe ya), escribe la unidad `systemd`
  (`Type=simple`, `ExecStart=... vigilar`, `Restart=on-failure`,
  `RestartSec=5`, `WantedBy=multi-user.target`), y hace
  `systemctl daemon-reload && systemctl enable --now pantalla-auto`.
- **`cmd_desinstalar`** — para y deshabilita el servicio, borra la unidad, el
  `.conf`, el fichero de freno y el propio binario instalado, y **devuelve los
  conectores al estado de arranque** (`EXTERNA on`, `INTERNA off`), para no
  dejar la máquina distinta de como arranca por defecto.
- **`cmd_pausar` / `cmd_reanudar`** — crean o borran el fichero de freno
  (`: > "$FRENO"` / `rm -f "$FRENO"`).

### Los tres niveles de "apagarlo"

Documentados explícitamente en la cabecera, de más suave a más definitivo:

1. `pausar` — el servicio sigue corriendo pero no toca nada.
2. `systemctl disable --now pantalla-auto` — lo para y no arranca más.
3. `desinstalar` — lo quita todo y devuelve los conectores a como arrancan.

---

## `parches/compilar-en-arch.sh`

**Propósito en una frase:** compila GroovyMAME con los parches de la cabina
**en Arch/GroovyArcade**, sin tocar el GroovyMAME que ya trae la distro
instalado ni depender del release binario de Ubuntu (que exige una glibc que
Arch no tiene por qué llevar y que, aunque arrancara, sería un GroovyMAME
"genérico" en vez del que GroovyArcade ya trae ajustado con switchres
funcionando de verdad).

### Uso

```bash
./parches/compilar-en-arch.sh
```

Sin argumentos ni subcomandos.

### Variables de entorno

| Variable | Por defecto | Efecto |
|---|---|---|
| `DESTINO` | `$HOME/.local/share/groovymame-cabina` | Dónde queda el binario final — el mismo sitio donde `instalar.sh` (tarea `descargar`) lo busca, así que los dos caminos convergen |
| `FUENTES` | `$HOME/groovymame-fuentes` | Dónde clonar el código fuente de GroovyMAME |
| `TRABAJOS` | `nproc` | Paralelismo de `make -j` |

### Salvaguardas iniciales

- Exige que exista `pacman` (`command -v pacman`); si no, sugiere usar la
  tarea `mame` de `instalar.sh` en su lugar, y sale.
- Se niega a correr como root (`[ "$(id -u)" -eq 0 ]`): "pide lo que necesita
  él solo" (usará `sudo` internamente solo para instalar paquetes).

### Recorrido paso a paso

1. **Comprobación de espacio**: calcula los GB libres en `$HOME` con
   `df -Pk` y `awk`, y exige al menos 12 GB (compilar GroovyMAME entero pesa
   bastante); si no hay suficiente, sale.
2. **Dependencias de compilación**: un array fijo `PAQUETES` con lo que pide
   GroovyMAME en Arch (`base-devel` —que es un grupo, no un paquete—, `git
   python sdl2 sdl2_ttf fontconfig libxinerama alsa-lib libpulse flac
   portaudio portmidi expat zlib libjpeg-turbo rapidjson glm libutf8proc asio
   lua`). Comprueba cada uno con `pacman -Qq` (paquete normal) o `pacman -Qg`
   (grupo); para lo que falte, **filtra antes de instalar** con `pacman -Si`/
   `-Sg` (mismo motivo que en `instalar.sh`: pacman aborta la instalación
   entera si un solo nombre no existe en los repos de esa versión) y solo
   entonces instala los que sí existen. Si la instalación falla igualmente
   (404 en todos los espejos), lo diagnostica como base de datos de pacman
   desfasada y sugiere `sudo pacman -Syu` completo (nunca un `-Sy` a secas),
   y sale con error.
3. **Fuentes**: si `$FUENTES/.git` ya existe, no vuelve a clonar. Si no,
   averigua la versión de GroovyMAME **ya instalada** en el sistema
   (`groovymame -version`, extrayendo `N.NNN` con `grep -oE`) y la traduce a
   nombre de rama de GitHub (`0.264` → `mame0264`), para clonar exactamente
   esa versión y no una cualquiera. Clona con `git clone --depth 1
   --branch <rama>` desde `antonioginer/GroovyMAME`; si esa rama no existe (o
   no se pudo determinar la versión instalada), reintenta un clon sin fijar
   rama.
4. **Parches**: aplica todos los `*.patch` que estén en el mismo directorio
   que este script (`parches/`) con `patch -N --dry-run` primero (para
   comprobar sin escribir nada si encajan o ya están puestos) y solo si el
   *dry-run* tiene éxito, los aplica de verdad. Si el *dry-run* falla, asume
   que ya estaban aplicados o que no encajan en estas fuentes, y avisa sin
   detener el script.
5. **Compilación**: `make -j$TRABAJOS NOWERROR=1 USE_QTDEBUG=0`, con
   `PATH=/usr/lib/ccache:$PATH` si `ccache` está instalado. Si falla, sugiere
   explícitamente relanzar con `TRABAJOS=1` — la causa más común en un
   mini-PC de cabina es quedarse sin memoria al compilar en paralelo.
6. **Instalación**: busca el binario recién compilado con
   `find "$FUENTES" -maxdepth 1 -type f -executable -name 'mame*'`, lo copia a
   `$DESTINO/mame`, y copia también la carpeta `bgfx` completa **al lado**
   (mismo motivo que en `instalar.sh`: MAME busca `bgfx` relativo a su
   directorio de trabajo). Añade además `crt-real.json` desde
   `config/cabina/` del repo principal a `$DESTINO/bgfx/chains/`.
7. Verifica que el binario final arranque (`-version`); si sí, imprime en
   verde la ruta y recuerda cómo decirle a `instalar.sh` que use este binario
   (`MAME=$DESTINO/mame ./instalar.sh`) y cómo deshacerlo todo
   (`rm -rf $DESTINO`, ya que nada del sistema se tocó). Si no arranca,
   muestra las primeras líneas de su error y sale con fallo.

### Ficheros que toca / no toca

- **No toca nada del sistema**: ni el `groovymame` de la distro, ni
  `pacman -U`, ni ficheros fuera de `$FUENTES` y `$DESTINO`.
- Lee `config/cabina/crt-real.json` del repo principal (`$REPO`, calculado
  como `dirname "$AQUI"`).
- Escribe únicamente dentro de `$FUENTES` (clon de git) y `$DESTINO` (binario
  final).

---

## `creditos/comun.sh`

**Propósito en una frase:** biblioteca de funciones de shell compartida por
varios scripts de `creditos/` — hoy, solo lo referente a encontrar dónde están
las roms. No se ejecuta solo: se carga con `. "$AQUI/comun.sh"` (o
`. "$AQUI/../comun.sh"` desde `pruebas/`).

### No tiene "uso" propio ni variables de entrada nuevas

No es un programa: es una colección de funciones. Quien lo carga necesita
tener `$HOME` disponible (nada más). La variable de entorno `ROMPATH`, si
está fijada, tiene prioridad sobre lo que declare MAME (ver `rompath_de`).

### Funciones que define

- **`mame_opcion(clave, binario)`** — ejecuta `"$binario" -showconfig` y
  extrae con `sed` el valor de una clave concreta (`s/^clave[[:space:]]\+//p`,
  quedándose con la primera coincidencia). Si el binario no es ejecutable,
  devuelve vacío sin error. Es la misma técnica que usa `instalar.sh` con su
  propia `mame_opcion()` (son dos copias independientes con la misma idea, no
  la misma función).
- **`rompath_de(binario)`** — devuelve el `rompath` **completo**, tal cual se
  le pasaría a `-rompath`. Precedencia: la variable de entorno `ROMPATH` (si
  existe) > lo que declare el propio MAME vía `mame_opcion rompath` > el
  defecto de Debian (`/usr/share/games/mame/roms`). **Trampa documentada y
  explícita**: el rompath son **varias rutas separadas por `;`**, no una sola
  — en una máquina real, MAME declaraba
  `$HOME/mame/roms;/usr/local/share/games/mame/roms;/usr/share/games/mame/roms`
  con las roms de verdad en la **tercera**. Quedarse con la primera que
  exista habría encontrado 11 juegos en vez de 104, sin ningún error visible.
  Por eso esta función **no elige ninguna**: devuelve el rompath entero, y son
  los scripts que la llaman (o el propio MAME) quienes buscan en todas.
  También expande a mano `$HOME`, `${HOME}` y un `~` inicial, porque
  `-showconfig` devuelve el valor **crudo** del `.ini` (en GroovyArcade, por
  ejemplo, `$HOME` sin expandir).
- **`dirs_de_rompath(rompath)`** — parte la cadena por `;` (con
  `${1//;/$'\n'}`) y filtra solo los directorios que **existen de verdad**. Es
  lo que necesitan los `find` que enumeran roms: da igual cuántas rutas
  declare MAME, aquí solo interesan las que hay en disco.
- **`listar_roms(rompath)`** — combina las dos anteriores: para cada
  directorio existente del rompath, busca ficheros `.zip`/`.7z` a
  `-maxdepth 1`, imprime solo el nombre de fichero (`-printf '%f\n'`), les
  quita la extensión con `sed 's/\.[^.]*$//'`, y pasa todo por `sort -u`. El
  resultado son los nombres de set de las roms instaladas, sin repetir.

### Quién lo usa

Se hace `source` de `comun.sh` desde: `poner_1c1c.sh`, `buscar_creditos.sh`,
`creditos/pruebas/aviso_mame.sh`, `creditos/pruebas/integracion.sh`, y
también desde `video_comun.sh` (que a su vez lo usan `videos.sh` y
`grabar.sh`). Es, en la práctica, la base de rutas de casi todo `creditos/`.

---

## `creditos/video_comun.sh`

**Propósito en una frase:** biblioteca compartida por `videos.sh` (grabación
automática en serie) y `grabar.sh` (grabar una partida jugada a mano) —
localizar el emulador y convertir un AVI crudo de MAME al `.mp4` final con la
proporción correcta. Tampoco se ejecuta solo: se carga con
`. "$AQUI/video_comun.sh"` **después** de haber definido `AQUI` en el script
que lo carga.

El comentario de cabecera explica por qué vive aparte en vez de estar
duplicado en los dos scripts: tanto la corrección de proporción 4:3 del
mueble como el ampliado en dos fases y el borrado de todas las extensiones de
vídeo tienen trampas que costaron una pasada cada una, y tener dos copias
significaría arreglar el fallo en un sitio y dejarlo vivo en el otro.

### Lo que quien lo carga tiene que tener puesto de antemano

| Variable | Para qué la usa `video_comun.sh` |
|---|---|
| `AQUI` | Directorio del script que hace `source` (para relocalizar `comun.sh`, etc.) |
| `DESTINO` | Carpeta de "snaps" del frontend, usada por `convertir_a_mp4` |
| `CALIDAD` | El `crf` de x264 a usar en la conversión |
| `AMPLIAR` | `1` o `0` — si se amplía la imagen antes de comprimir |
| `AUDIO_FFMPEG` | Argumentos de audio para `ffmpeg` (`-an`, o algo como `-c:a aac -b:a 160k`) |

### Recorrido: qué hace nada más cargarse

Al hacer `source`, este fichero **ejecuta código de inmediato** (no son solo
definiciones de función): busca el emulador y aborta el script que lo cargó
si no lo encuentra.

1. Redefine `AQUI` a su propio directorio (por si el que lo carga lo definió
   de otra forma; en la práctica coincide).
2. **`vecino(marca, candidatos...)`** — función auxiliar: recorre una lista de
   directorios candidatos y devuelve el primero que contenga el fichero/
   directorio `marca`. Sirve para soportar las dos disposiciones de repos
   posibles: `creditos/` dentro de `attractplus` (la normal, una sola
   clonación) o los dos repos hermanos, como estaban antes de fundirse.
3. **`buscar_mame()`** — encuentra el ejecutable de MAME probando, en orden:
   `$MAME` (si el usuario lo fijó por entorno), 
   `~/.local/share/groovymame-cabina/mame` (donde deja el binario tanto la
   tarea `descargar` de `instalar.sh` como `compilar-en-arch.sh`), el
   `groovymame_src/mame` que encuentre `vecino()` en dos niveles de
   profundidad relativa distintos (`../../groovymame_src` porque
   `video_comun.sh` vive en `creditos/`, o `../groovymame_src`, o
   `~/groovymame_src`), y finalmente `groovymame` o `mame` en el `$PATH`. Si
   ninguno resulta ejecutable, imprime por `stderr` la lista completa de
   sitios donde buscó y sale con código 1 — **esto mata el script que hizo
   `source`**, porque se ejecuta a nivel superior del fichero, no dentro de
   una función.
4. Fija `MAME_BIN` al resultado y `MAME_DIR` a su directorio (entrando en él
   con `cd` para lanzarlo, porque la compilación propia lleva al lado su
   `bgfx` y sus plugins, igual que hace el frontend con su `workdir`).
5. Hace `source` de `comun.sh` y fija `ROMPATH="$( rompath_de "$MAME_BIN" )"`.
6. Comprueba que `ffmpeg` esté en el PATH; si no, sale con error.

### Funciones que define

- **`proporcion(juego, ancho_crudo, alto_crudo)`** — calcula a qué resolución
  hay que llevar un vídeo/captura para que se vea con la proporción real de
  un monitor de recreativa. Consulta la rotación del juego con
  `"$MAME_BIN" -listxml <juego>` (busca `rotate="N"` en el `<display>`) y
  llama a un script Python **embebido** (inline, con `python3 -c`) que decide:
  la proporción deseada es 0.75 (3:4) si el juego está rotado 90/270 grados
  (vertical), o 4/3 si no. Si el bitmap crudo es más ancho que esa proporción,
  se agranda el **alto**; si es más estrecho, se agranda el **ancho** — nunca
  se encoge nada, para no perder detalle del original. Con un tope: si el
  factor de ampliación necesario pasa de 1.5×, se cambia de estrategia y se
  agranda el otro lado en su lugar (el caso real que motiva el tope es
  Frogger, que graba 224×768 porque la placa da tres líneas físicas por línea
  útil, y agrandar el ancho a lo bruto pediría un 2.6× inventado). El
  resultado se redondea a par (`yuv420p` lo exige) y se imprime como
  `"ANCHOxALTO"`.
- **`EXT_VIDEO`** — lista de extensiones que Attract-Mode Plus puede tratar
  como vídeo (`mp4 avi mkv mpg mpeg mov webm m4v wmv flv ogv`).
- **`video_existente(juego)`** — devuelve la ruta del primer fichero no vacío
  que encuentre para ese juego con cualquiera de esas extensiones, o falla si
  no hay ninguno.
- **`borrar_videos(juego)`** — borra **todas** las extensiones de vídeo de ese
  juego (nunca el `.png`, que es el respaldo cuando no hay vídeo). El motivo
  documentado: AM+ prefiere el vídeo a la imagen fija y acepta varias
  extensiones, así que si quedara, por ejemplo, un `.avi` de una grabación
  vieja, seguiría mandando sobre un `.mp4` recién generado y parecería que
  regrabar no sirve de nada.
- **`convertir_a_mp4(avi, juego, salto, dura)`** — la función central,
  compartida por los dos modos de grabación (la automática de `videos.sh` y
  la manual de `grabar.sh`). Paso a paso:
  1. Con `ffprobe -select_streams v:0 -show_entries stream=width,height
     -of csv=p=0:s=x` obtiene la resolución cruda del AVI de entrada; si
     `ffprobe` no devuelve nada, falla.
  2. Llama a `proporcion()` para saber a qué tamaño final hay que llegar.
  3. **Por qué se amplía antes de codificar, en dos pasos que no son
     intercambiables** (explicado en el propio comentario): el bitmap crudo
     de MAME es diminuto (Pac-Man: 224×288) y AM+ lo estira hasta el hueco del
     layout (~700 px en esta cabina); si se codificara directamente a ese
     tamaño pequeño, el h264 con un `crf` razonable gastaría muy pocos kbps y
     saldrían bloques por todas partes. Por eso primero se hace un
     **múltiplo entero** de ampliación con el filtro `neighbor` de `ffmpeg`
     (duplica píxeles exactos, sin difuminar el arte original), y solo
     **después**, sobre esa imagen ya grande, se aplica la corrección de
     proporción (que normalmente no es un múltiplo entero) con el filtro
     `lanczos`. Hacerlo al revés reparte mal las filas y se ve irregular. El
     factor entero (`amp`) se calcula como `700 / alto_crudo + 1`, con tope
     entre 1 y 4, y se puede desactivar del todo con `AMPLIAR=0`.
  4. Construye la orden de `ffmpeg`:
     `ffmpeg -y -loglevel error -i "$avi" -ss "$salto" ${corte} -vf
     "scale=ENTERO:flags=neighbor,scale=FINAL:flags=lanczos" -c:v libx264
     -preset slow -crf "$CALIDAD" -pix_fmt yuv420p ${audio} -movflags
     +faststart "$avi.mp4"`. `${corte}` es `-t "$dura"` solo si `dura` no está
     vacía ni es `0` (vacío/0 significa "hasta el final": la duración la puso
     el jugador, no una ventana fija). `${audio}` sale de partir
     `AUDIO_FFMPEG` en palabras con `read -ra` (por defecto `-an`, mudo).
  5. Si la conversión tiene éxito y el `.mp4` resultante no está vacío, borra
     cualquier vídeo anterior de ese juego (`borrar_videos`) y **mueve** el
     temporal al destino final (`mv -f`). Se convierte primero a un temporal y
     se sustituye al final para que el frontend nunca se encuentre un `.mp4` a
     medio escribir, y para que si la conversión falla, el vídeo viejo
     (bueno) siga en su sitio.

### Quién lo carga

`creditos/videos.sh` y `creditos/grabar.sh`, ambos con
`. "$AQUI/video_comun.sh"` justo después de calcular su propio `AQUI`.

---

## `creditos/videos.sh`

**Propósito en una frase:** graba en serie un vídeo de muestra de cada juego
(o de los que se le pidan), bajo Xvfb, arrancando cada uno con `creditos.lua`
igual que en la cabina real, para que Attract-Mode Plus tenga vídeo de
atracción en vez de una captura fija.

### Uso

```bash
./videos.sh pacman dkong          # esos juegos concretos
./videos.sh                       # todos los de la romlist
./videos.sh --tira simpsons       # hoja de contactos de UN juego, para ver dónde cortar
./videos.sh --hojas               # hoja de contactos de TODOS + fichero de tiempos
./videos.sh --desde hojas/tiempos.txt   # graba cada juego en el segundo apuntado

FORZAR=1 ./videos.sh simpsons     # rehacer uno (borra el vídeo anterior)
```

`-h`/`--help`/`--ayuda` imprime las líneas 2-16 del propio fichero (la
cabecera de comentarios) y sale.

Es un flujo pensado en **dos fases** para elegir el punto de cada vídeo sin
adivinar por análisis de imagen (que falla: el título de Mario parpadea más
que su propia demo):

1. `--hojas` graba una ventana larga de cada juego y deja una hoja de
   contactos (12 fotogramas) por juego en `hojas/<juego>.png`, más un fichero
   `hojas/tiempos.txt` para rellenar a mano.
2. Uno mira las hojas y escribe en `tiempos.txt` el segundo en que empieza el
   gameplay de cada juego.
3. `--desde hojas/tiempos.txt` lee esos valores, los graba como `video=` en
   `arranque.dat`, y graba el `.mp4` final de cada uno cortando justo ahí.

### Variables de entorno

| Variable | Por defecto | Efecto |
|---|---|---|
| `EMU` | `groovymame` | Nombre del emulador (para construir rutas de destino) |
| `DESTINO` | `$HOME/.attract/scraper/$EMU/snap` | Dónde quedan los `.mp4` finales |
| `ROMLIST` | `$HOME/.attract/romlists/$EMU.txt` | De dónde saca la lista de juegos si no se pasan por argumento |
| `SALTO` | `8` | Segundos que se descartan al principio (la carga), si no hay nada más específico. Si se fija por entorno, **manda sobre todo lo demás** (`SALTO_DE_ORDENES`) |
| `DURA` | `12` | Segundos que dura el vídeo grabado |
| `CALIDAD` | `20` | `crf` de x264 (pasa a `video_comun.sh`) |
| `AMPLIAR` | `1` | `0` para no ampliar antes de comprimir (pasa a `video_comun.sh`) |
| `AJUSTES` | `$AQUI/arranque.dat` | Fichero de ajustes por juego de donde lee `video=`, `videomas=`, `videodura=`, `segundos=` |
| `VENTANA` | `62` | Segundos que dura la grabación de `--tira`/`--hojas`, y sobre los que se reparten los 12 instantes de la hoja de contactos |
| `HOJAS` | `$PWD/hojas` | Carpeta donde `--hojas` deja las imágenes y `tiempos.txt` |
| `CREDITOS_LUA` | `$AQUI/creditos.lua` | Script de autoboot con el que se lanza cada juego |
| `GA_VERBOSO` | (vacío) | Si se fija (a cualquier valor), se pasa como `GA_VERBOSO=1` a `creditos.lua` para diagnóstico |
| `FORZAR` | (vacío) | `1` para rehacer un vídeo/hoja aunque ya exista |
| `SALTO=` / `DURA=` en la línea de órdenes | — | Igual que las variables de arriba, pero explícitamente documentadas como la prioridad más alta |

### El ajuste por juego vive en `arranque.dat`, no en este script

Este es el punto de diseño más importante del script: no hay ninguna tabla de
tiempos dentro de `videos.sh`. Las claves relevantes de `arranque.dat` (el
mismo fichero que usa `creditos.lua` para el arranque tapado) son:

- **`video=N`** — segundo **absoluto** en el que empieza el gameplay a grabar.
- **`videomas=N`** — segundos **relativos**, contados desde donde termina el
  arranque tapado (`segundos=`) de ese juego; admite decimales y signo
  negativo. Si el día de mañana se retoca `segundos=` de un juego, el vídeo
  se mueve solo con él en vez de quedar apuntando a un instante que ya no
  existe.
- **`videodura=N`** — cuánto dura el vídeo de ese juego en concreto.

`creditos.lua` **ignora** estas tres claves (su analizador guarda cualquier
clave y solo consulta las que le interesan a él); `videos.sh` es quien las
lee, con `clave_de_arranque()`.

### Funciones auxiliares

- **`clave_de_arranque(juego, clave)`** — busca la línea de `arranque.dat` que
  empieza exactamente por ese nombre de juego (`grep -iE "^$1[[:space:]]"`,
  la primera si hay varias) y extrae el valor de una clave con una expresión
  regular que admite signo y decimales
  (`(^|[[:space:]])$2=-?[0-9]+(\.[0-9]+)?`). **Bug corregido y documentado en
  el propio comentario**: antes esta expresión pedía solo `[0-9]+`, así que un
  valor como `segundos=11.8` se leía como `11`, **en silencio** — el vídeo
  empezaba casi un segundo antes de lo que decía `arranque.dat`, sin ningún
  aviso. Ahora también soporta el signo, para que `videomas=-2` se pueda
  escribir.
- **`calc(expr)`** / **`es_menor(a, b)`** — con decimales en juego, la
  aritmética de `bash` (`$(( ))`) directamente no sirve (`$(( 11.8 + 3 ))` es
  un error de sintaxis). Las dos hacen la cuenta con `awk`: `calc` evalúa una
  expresión y la imprime sin ceros sobrantes (`14.8` se queda `14.8`, `15.0`
  sale como `15`); `es_menor` compara dos números y devuelve el código de
  salida correspondiente.
- **`montador()`** — resuelve el binario de ImageMagick disponible: `magick
  montage` en la versión 7, o `montage` a secas en la 6.
- **`instantes_tira()`** — calcula los 12 instantes (en segundos) de la hoja
  de contactos, repartidos proporcionalmente a `VENTANA` (`paso = VENTANA /
  13`, y se listan `paso*1 .. paso*12`). **Corregido y documentado**: antes
  estaban clavados a una ventana de 60 s fija, así que con `VENTANA=120` (para
  juegos de lucha con presentación larga) la hoja salía igual que con
  `VENTANA=62` y no mostraba nunca la segunda mitad.
- **`hacer_tira(avi, salida, juego)`** — construye la hoja de contactos:
  extrae con `ffmpeg -ss <t> -vframes 1 -vf scale=150:-1` un fotograma por
  cada instante de `instantes_tira()`, y los junta con `montage`/`magick
  montage` en una rejilla de 4×3. Si encuentra una fuente sans (con
  `fc-match`), rotula cada fotograma con su segundo (`-label '%t s'`); si no,
  la hoja sale sin números (el orden ya se conoce por `instantes_tira()`).
- **`grabar_avi(juego, segundos, avi, log)`** — el método de grabación
  "completo" (usado por `--tira` y `--hojas`): lanza MAME bajo `xvfb-run` con
  `creditos.lua` de autoboot a `-autoboot_delay 0`, `-nothrottle`, y un
  monedero **aislado** en un fichero temporal (`GA_ARCHIVO=$(mktemp)`) para no
  tocar el monedero real de la cabina mientras se graba. Usa `-aviwrite` para
  volcar todo lo emulado durante `$segundos` segundos a un AVI crudo.
- **`grabar_clip(juego, inicio, dura, avi, log)`** — el método **rápido**
  usado por el flujo normal (sin `--tira`/`--hojas`/`--desde`): en vez de
  grabar desde el frame 0 y dejar que `ffmpeg` tire los primeros ~90 s de
  carga, delega en el propio `creditos.lua` (modo `GA_GRABAR`, ver
  CLAUDE.md, sección "Grabar solo la ventana"): pasa `GA_GRABAR=$inicio
  GA_GRABAR_DURA=$dura GA_GRABAR_MARGEN=2 GA_GRABAR_ARCHIVO=$avi`, y es el
  script Lua quien acelera la carga con `frameskip` máximo y solo empieza a
  grabar el AVI (`begin_recording`/`end_recording` de MAME) justo en el
  segundo pedido. El AVI resultante **ya es el clip completo**: empieza en 0
  y dura `dura` segundos. Como red de seguridad, calcula con `awk` un tope de
  `-seconds_to_run` (`inicio + dura + margen + 4`, redondeado hacia arriba)
  por si el propio Lua no terminara por su cuenta.

### Los cuatro modos de invocación

**`--tira <juego>`** — graba `VENTANA` segundos con `grabar_avi`, construye la
hoja de contactos (por defecto en `./tira-<juego>.png`, o donde diga `SALIDA`),
imprime los 12 instantes en filas de 4, y sugiere anotar el segundo elegido
como `video=` en `arranque.dat` (o probarlo sin tocar nada con
`SALTO=<n> FORZAR=1 ./videos.sh <juego>`).

**`--hojas [juegos...]`** — versión en lote de `--tira`, sobre todos los
juegos de la romlist si no se pasan argumentos. Crea `hojas/tiempos.txt` **solo
si no existe** (para no perder progreso si se interrumpe a medio hacer), con
una cabecera de instrucciones. Para cada juego: si ya tiene hoja y no se pasó
`FORZAR=1`, lo salta; si no, graba y construye la hoja, y añade una línea
`juego=` a `tiempos.txt` (vacía, o con el valor de `video=` que ya hubiera en
`arranque.dat`, como sugerencia de partida) solo si esa línea no existía ya.

**`--desde <tiempos.txt>`** — lee el fichero línea a línea **por el descriptor
de fichero 3**, no por la entrada estándar. El comentario explica por qué:
si se leyera por `stdin`, el propio MAME (o `ffmpeg`) lanzado dentro del bucle
se comería el resto de las líneas del fichero, y solo se procesaría el primer
juego — "costó una pasada averiguarlo". Por cada línea `juego=segundos`
(saltando comentarios `#` y líneas en blanco o sin valor): valida que sea un
número, escribe ese valor como `video=` en `arranque.dat` con el script
externo `escribir_ajuste.py` (Python, fuera de alcance de este documento), y
se **reinvoca a sí mismo** (`FORZAR=1 SALTO="$t" "$0" "$j"`) para grabar el
`.mp4` final de ese juego con el flujo normal.

**Sin flags (el modo normal)** — para cada juego de la lista (argumentos, o
toda la romlist si no hay ninguno): si ya existe vídeo y no se pasó
`FORZAR=1`, se salta. Si no, calcula el punto de corte (`salto`) con esta
precedencia, de más fuerte a más débil:

1. `SALTO=` de la línea de órdenes (`SALTO_DE_ORDENES`).
2. `video=` de `arranque.dat` para ese juego.
3. `segundos=` + `videomas=` de `arranque.dat`: `salto = segundos + videomas`
   (calculado con `calc()`, y con suelo en 0 vía `es_menor`). **No** se le
   aplica el suelo general de `SALTO` (8 s) en este caso: el punto lo eligió
   una persona a mano, y subirlo automáticamente sería ignorar esa decisión.
4. `segundos=` de `arranque.dat` **como suelo, no como valor final**: si ese
   valor es mayor o igual que `SALTO` (el defecto, normalmente 8), se usa tal
   cual; si es **menor**, se sustituye por `SALTO`, porque `arranque.dat` solo
   sabe cuándo la placa terminó de arrancar, y la demo de atracción suele
   empezar después. Un `segundos=0` (que en `creditos.lua` significa "a este
   juego no se le tapa el arranque") se trata como si no existiera, cayendo
   al defecto general.
5. El defecto (`SALTO`, 8 s).

La duración (`dura`) sigue una precedencia parecida pero más corta: `DURA=` de
la línea de órdenes > `videodura=` de `arranque.dat` > `DURA` por defecto.

Graba con `grabar_clip()` (el método rápido) a un AVI temporal; si sale vacío,
informa del fallo buscando en el log de MAME pistas típicas (`not found`,
`missing`, `fatal`, `required`, `unknown system`) en vez de solo decir "no se
pudo grabar". Si sale bien, convierte con `convertir_a_mp4 avi juego 0 dura`
(el `0` porque `grabar_clip` ya entregó el AVI recortado desde el principio,
así que no hace falta volver a saltar nada al convertir).

### Ficheros que lee / escribe, y scripts que invoca

- **Lee**: `arranque.dat` (o lo que diga `AJUSTES`), la romlist del emulador,
  y (en `--desde`) el fichero de tiempos que se le pase.
- **Escribe**: los `.mp4` en `$DESTINO`, las hojas de contactos en `$HOJAS`,
  `hojas/tiempos.txt`, y (indirectamente, vía `escribir_ajuste.py`) el propio
  `arranque.dat`.
- **Invoca**: `. video_comun.sh` (que a su vez busca el MAME y hace `source`
  de `comun.sh`), `creditos.lua` como `-autoboot_script` de MAME,
  `escribir_ajuste.py` (solo en `--desde`), y se reinvoca a sí mismo
  (`$0`) en `--desde`.

---

## `creditos/grabar.sh`

**Propósito en una frase:** graba **la partida de una persona jugando de
verdad**, con sonido, alternando "empezar/parar" con una tecla, y la deja
lista como el vídeo de ese juego en el frontend — el complemento manual de
`videos.sh` para los momentos que la grabación automática no puede elegir
bien.

### Uso

```bash
./grabar.sh mwalk
```

Solo admite **un** juego por invocación (`[ $# -eq 1 ]`, si no, error de uso).
`-h`/`--help`/`--ayuda`, o sin argumentos, imprime la cabecera (líneas 2-22) y
sale.

El flujo, tal como lo describe el propio comentario:

1. Se abre el juego y se juega normal.
2. En el momento que vale la pena, se pulsa la **tecla** y arriba a la
   derecha aparece `* REC 3s` — ha empezado a grabar.
3. La misma tecla corta la toma. Se pueden hacer tantas tomas como se quiera
   dentro de la misma sesión.
4. Al salir del emulador, el script elige una toma (o pregunta cuál) y la
   convierte.

### Variables de entorno

| Variable | Por defecto | Efecto |
|---|---|---|
| `EMU` | `groovymame` | Para construir la ruta de destino |
| `DESTINO` | `$HOME/.attract/scraper/$EMU/snap` | Dónde queda el `.mp4` final |
| `CALIDAD` | `20` | `crf` de x264 |
| `AMPLIAR` | `1` | Ampliar antes de comprimir |
| `TECLA` | `KEYCODE_PAUSE` | Token de MAME que arranca/para la grabación (leído con `input:code_pressed`, el estado crudo del teclado, sin pasar por el `ioport` del juego ni por la UI de MAME) |
| `CREDITOS_LUA` | `$AQUI/creditos.lua` | Script de autoboot |
| `AUDIO_FFMPEG` | `-c:a aac -b:a 160k` | A diferencia de `videos.sh`, aquí **se graba CON sonido** por defecto |
| `GA_VERBOSO` | (vacío) | Diagnóstico de `creditos.lua` |

Se cambia la tecla así: `TECLA=KEYCODE_MENU ./grabar.sh pacman`. El comentario
explica por qué la tecla por defecto es Pausa/Inter y no otra más "obvia":
comprobando `inpttype.ipp` de MAME, Insert resultó estar ya cogida por "Fast
Forward", y las teclas de Inicio/Fin/AvPág/RePág son del menú de MAME, e
Imprimir Pantalla se la queda el escritorio.

### Por qué es un script aparte de `videos.sh`

Explícito en el comentario: `videos.sh` graba en serie, sin nadie delante,
bajo Xvfb y **sin sonido**. Esto es justo lo contrario — una persona jugando
en la cabina de verdad, con audio — y mezclar los dos casos en un solo script
habría dejado peor a los dos. Lo que sí comparten (vía `video_comun.sh`) es el
tratamiento final del vídeo: corrección de proporción 4:3 y ampliado antes de
comprimir, para que la partida grabada a mano no desentone del resto de
vídeos generados automáticamente.

### Recorrido paso a paso

1. Exige que exista `$DISPLAY` o `$WAYLAND_DISPLAY` — este script se lanza
   **delante de la cabina**, no por SSH sin más (con `ssh -X` sí funcionaría,
   porque entonces sí hay `DISPLAY`).
2. Imprime el emulador, el juego y el destino, y recuerda al usuario la tecla
   de grabación.
3. Lanza MAME (**no** bajo `xvfb-run`: se juega en pantalla real) con
   `creditos.lua` de autoboot (`-autoboot_delay 0`), pasando
   `GA_GRABAR_TECLA=$TECLA` y `GA_GRABAR_ARCHIVO="$TMP/toma-"` — es
   `creditos.lua` quien, en su modo de grabación por tecla, escribe un AVI
   distinto por cada par empezar/parar (`toma-1.avi`, `toma-2.avi`...).
   **Deliberadamente no fuerza** ninguna opción de vídeo/sonido (`-video`,
   `-sound`): se deja lo que ya diga `mame.ini`, porque aquí el jugador está
   delante de verdad, a diferencia de `videos.sh`, que graba a ciegas bajo
   Xvfb y por eso sí necesita forzarlas.
4. Al salir MAME, lista `toma-*.avi` con `sort -V` (orden numérico natural).
   Si no hay ninguna, avisa de que no se llegó a pulsar la tecla (o MAME no la
   vio) y sugiere probar con otra (`TECLA=KEYCODE_MENU`).
5. Si hay una sola toma, se usa esa directamente. Si hay varias: si hay
   terminal interactivo, muestra una lista numerada con duración
   (`ffprobe -show_entries format=duration`) y tamaño, y pregunta cuál
   quedarse, validando que la respuesta sea un número de la lista; si no hay
   terminal (por ejemplo, invocado desde otro script), se queda
   automáticamente con **la más larga**.
6. Antes de convertir: si ya había un vídeo para ese juego
   (`video_existente`), se guarda una copia en `$DESTINO/respaldo/
   <nombre>.anterior` — con **nombre fijo**, sobrescribiendo la copia anterior
   si la había, no acumulando una por regrabación (decisión explícita de Eloy
   para no gastar espacio sin límite).
7. Convierte con `convertir_a_mp4 elegida juego 0 ""` — `salto=0` y
   `dura=""` (vacía = "hasta el final": la toma dura lo que el jugador quiso,
   no una ventana fija).
8. Tras convertir, comprueba que el clip lleve sonido de verdad con
   **`pico_audio()`**: mide el pico de volumen en dB con
   `ffmpeg -af volumedetect -f null /dev/null` y extrae `max_volume` del log.
   Si no hay pista de audio en absoluto, avisa. Si el pico es ≤ -80 dB (-91 dB
   es silencio digital absoluto), avisa de que el clip **puede** haber salido
   mudo, aclarando explícitamente que eso no significa necesariamente un
   fallo: el propio tramo del juego pudo estar callado en ese momento, o el
   `mame.ini` tener `sound none`/volumen bajo. Si el pico es razonable,
   confirma "sonido OK".

### Ficheros que lee / escribe, y scripts que invoca

- **Lee**: nada de configuración propia; consulta `mame.ini` indirectamente
  (no lo toca) al no forzar sus opciones.
- **Escribe**: el `.mp4` final en `$DESTINO`, y una copia de respaldo del
  vídeo reemplazado en `$DESTINO/respaldo/`.
- **Invoca**: `. video_comun.sh` (que localiza MAME y hace `source` de
  `comun.sh`), y lanza `creditos.lua` como `-autoboot_script` de MAME.

### Detalle técnico: por qué el audio "simplemente funciona"

El comentario lo aclara: el AVI que graba MAME (`begin_recording`/
`end_recording`, activados por `creditos.lua` en su modo de grabación por
tecla) lleva el sonido **dentro**, porque el gestor de sonido de MAME
alimenta la grabación por su cuenta mientras dura. No hace falta capturar
audio aparte ni sincronizar nada después — a diferencia de un enfoque que
grabara vídeo y audio por separado.

---

## `creditos/aspecto.sh`

**Propósito en una frase:** corrige la proporción (aspect ratio) de las
capturas y vídeos que **ya están descargados o grabados previamente** —
`videos.sh` ya graba con la proporción correcta desde el principio, así que
esto es para "lo de antes" y para lo que baje `arte.sh`, que llega crudo.

### Uso

```bash
./aspecto.sh            # corrige lo que haga falta
./aspecto.sh --ver       # solo dice qué corregiría, sin tocar nada

CAPTURAS=/otra/ruta ./aspecto.sh    # si las capturas están en otro sitio
```

### Variables de entorno

| Variable | Por defecto | Efecto |
|---|---|---|
| `MAME_DIR` | Se busca con `vecino()` en `../../groovymame_src`, `../groovymame_src` o `~/groovymame_src` | Dónde está el ejecutable `mame` |
| `EMU` | `groovymame` | Para construir la ruta de capturas |
| `CAPTURAS` | `$HOME/.attract/scraper/$EMU/snap` | Carpeta con los `.png`/`.mp4` a corregir |

**Trampa documentada explícitamente en el código**: el nombre de variable es
`CAPTURAS`, no `SNAP`, a propósito. `SNAP` **ya existe en el entorno** cuando
algo se lanza desde una aplicación empaquetada como Snap (por ejemplo, VS Code
la fija a `/snap/code/NNN`), así que `"${SNAP:-...}"` se tragaría ese valor
ajeno sin avisar. El síntoma sería mudo: el script no encontraría ningún
fichero en esa ruta y diría que no hay nada que corregir, sin ningún error.

### Recorrido paso a paso

1. Comprueba que `ffmpeg` y `ffprobe` estén en el PATH.
2. Resuelve el binario de ImageMagick disponible: si existe `magick` (v7), usa
   `CONVERTIR=(magick)` e `IDENTIFICAR=(magick identify)`; si no, y existe
   `convert` (v6), usa `CONVERTIR=(convert)` e `IDENTIFICAR=(identify)`; si no
   hay ninguno, sale con error.
3. Comprueba que `$CAPTURAS` exista.
4. Construye una tabla asociativa `ROT[juego]=rotación` de **un solo tirón**:
   ejecuta `./mame -listxml` (todas las roms de golpe, en vez de un
   `-listxml` por juego, que costaría ~1 s cada uno) y lo procesa con un
   script Python **embebido** que va emparejando `<machine name="...">` con el
   siguiente `<display ... rotate="N">` que aparezca.
5. Define `destino(juego, ancho, alto)`: la misma lógica de `proporcion()` de
   `video_comun.sh`, pero **implementada aparte, en su propio Python
   embebido** (no reutiliza la función de `video_comun.sh`): calcula la
   proporción deseada (0.75 si está rotado 90/270, si no 4/3), agranda el
   lado que falta, y aplica el mismo tope de 1.5× explicado arriba para
   Frogger.
6. Para cada `.png` y `.mp4` de `$CAPTURAS`:
   - Si el juego no está en la tabla `ROT` (MAME no lo conoce, por ejemplo un
     nombre de set mal escrito), se avisa y se deja tal cual.
   - Se mide el tamaño actual (`identify -format '%wx%h'` para PNG,
     `ffprobe ... -of csv=p=0:s=x` para MP4).
   - Se calcula el tamaño deseado con `destino()`.
   - Si ya coincide, se cuenta como "ya estaba bien" y se pasa al siguiente.
   - Si no, se informa del cambio (`crudo -> nuevo`); en modo `--ver` se
     cuenta como "por corregir" y no se toca nada; si no, se corrige de
     verdad: para PNG, `convert/magick ... -filter Lanczos -resize
     "ANCHOxALTO!"` (el `!` fuerza las dimensiones exactas, ignorando la
     proporción original de la imagen, porque el tamaño ya viene calculado a
     propósito) a un fichero temporal y luego `mv` sobre el original; para
     MP4, `ffmpeg -vf "scale=...:flags=lanczos" -c:v libx264 -preset slow
     -crf 26 -pix_fmt yuv420p -an` a un temporal, comprobando que no quede
     vacío, y solo entonces `mv`. En los dos casos, ir a un temporal primero
     evita dejar el fichero real a medio escribir si el proceso se cae a
     mitad.
7. Al final, imprime un resumen: cuántos se corrigieron (o corregirían, en
   `--ver`), cuántos ya estaban bien, y cuántos quedaron sin tocar por no
   tener rotación conocida.

### Ficheros que lee / escribe, y scripts que invoca

- **Lee**: la salida de `./mame -listxml` (no un fichero, sino el propio
  ejecutable de MAME), y los `.png`/`.mp4` de `$CAPTURAS`.
- **Escribe**: los mismos `.png`/`.mp4`, sobrescribiéndolos in situ (vía
  temporal).
- **No hace `source` de `comun.sh` ni de `video_comun.sh`**: tiene su propia
  copia de `vecino()` y su propia implementación de la lógica de proporción,
  duplicada respecto a `video_comun.sh` (algo a tener en cuenta si algún día
  se corrige un caso límite en una de las dos: hay que revisar también la
  otra).
- **Invoca**: `mame -listxml`, `ffmpeg`/`ffprobe`, `convert`/`magick`/
  `identify`.

---

## `creditos/arte.sh`

**Propósito en una frase:** descarga las marquesinas, capturas, flyers y
ruedas ("wheel") de uno o varios juegos desde `adb.arcadeitalia.net`, y las
deja donde Attract-Mode Plus las busca automáticamente.

### Uso

```bash
./arte.sh pacman dkong          # esos juegos
./arte.sh bublbobl              # el PADRE, si tu rom es un clon
```

Exige al menos un argumento; sin ninguno, imprime uso y sale con error.

Si la rom instalada es un clon o un hack (por ejemplo `bbredux`), hay que
pedir el arte con el nombre del juego **padre**, porque AM+ busca en este
orden: `Name`, luego `AltRomname`, luego `CloneOf` — o sea, si no encuentra
arte con el nombre exacto de la rom, prueba con el del clon original.

### Variables de entorno

| Variable | Por defecto | Efecto |
|---|---|---|
| `EMU` | `groovymame` | Para construir la ruta de destino |
| `DESTINO` | `$HOME/.attract/scraper/$EMU` | Carpeta base donde se guarda cada tipo de arte |

`FUENTE` no es configurable por entorno: está fijada a
`http://adb.arcadeitalia.net/media/mame.current`.

### Recorrido paso a paso

Un array fijo `TIPOS` mapea el nombre remoto al nombre de carpeta local:
`marquees:marquee`, `ingames:snap`, `flyers:flyer`, `decals:wheel`.

Para cada juego pasado como argumento, y para cada uno de esos cuatro tipos:

1. Crea la carpeta local si no existe (`$DESTINO/<tipo-local>`).
2. Si el fichero de destino ya existe y no está vacío, lo salta ("ya
   estaba").
3. Descarga con `curl -sL -m 40 -o fichero -w "%{http_code}"` desde
   `$FUENTE/<tipo-remoto>/<juego>.png`. El `-L` es imprescindible: el sitio
   **redirige `http` a `https`**, y sin seguir la redirección `curl` recibiría
   un 301 vacío.
4. Si el código HTTP es 200 y el fichero no quedó vacío, informa del tamaño
   en bytes; si no, borra el fichero (puede haber quedado una página de error
   HTML con extensión `.png`) e informa del código HTTP recibido.

Al final imprime un recordatorio de recargar el layout con F5, o reiniciar
AM+, para ver el arte nuevo.

### Ficheros que lee / escribe, y scripts que invoca

- **No lee ninguna configuración local** ni hace `source` de nada — es
  completamente autónomo, solo necesita `curl`.
- **Escribe**: los `.png` en
  `$DESTINO/{marquee,snap,flyer,wheel}/<juego>.png`, que es exactamente donde
  `internal_get_best_artwork_file` de AM+ los busca sin necesidad de
  configurar ninguna ruta de artwork adicional.

---

## `creditos/poner_1c1c.sh`

**Propósito en una frase:** pasada de calibración que deja cada juego en
1 moneda = 1 crédito, para que desde el primer arranque los créditos que
gestiona el frontend sean exactos (sin esta pasada, MAME arranca con el DIP
de tarifa de fábrica de cada placa, que en varios juegos no es 1C/1C).

### Uso

```bash
./poner_1c1c.sh                 # todas las roms del rompath
./poner_1c1c.sh pacman dkong     # solo esos
```

### Variables de entorno

| Variable | Por defecto | Efecto |
|---|---|---|
| `MAME_DIR` | Buscado con `vecino()` en `../../groovymame_src`, `../groovymame_src` o `~/groovymame_src` | Directorio con el ejecutable `mame` |
| `ROMPATH` | Lo que declare `$MAME_DIR/mame` (vía `rompath_de` de `comun.sh`) | Dónde están las roms |
| `CFG_DIR` | El `cfg_directory` que MAME use por defecto | A qué carpeta de `.cfg` se escribe el cambio de DIP — **importante fijarlo a una carpeta aparte al probar**, para no tocar la configuración real de la cabina |
| `MAME_EXTRA` | (vacío) | Opciones extra que se añaden a la línea de MAME, sin procesar (se expanden con `$MAME_EXTRA` sin comillas, así que aquí se pueden pasar varias opciones separadas por espacio) |

### Recorrido paso a paso

1. Hace `source` de `comun.sh` y calcula `ROMPATH` con `rompath_de`.
2. Comprueba que `$MAME_DIR/mame` sea ejecutable; si no, sale.
3. Si no se pasaron juegos como argumento, los saca con `listar_roms
   "$ROMPATH"` (de `comun.sh`) — es decir, los nombres de fichero `.zip`/`.7z`
   sin extensión de todo el rompath. Si tampoco hay ninguna rom, sale con
   error.
4. Si no hay `$DISPLAY` y existe `xvfb-run`, se antepone `xvfb-run -a` al
   lanzamiento de MAME (en la cabina, con pantalla real, no hace falta).
5. Si `$CFG_DIR` está fijado, añade `-cfg_directory "$CFG_DIR"` a las
   opciones.
6. Para cada juego: lanza
   `mame <juego> -rompath ... [-cfg_directory ...] $MAME_EXTRA -video none
   -sound none -nothrottle -noswitchres -seconds_to_run 2
   -autoboot_script poner_1c1c.lua -autoboot_delay 1`, capturando toda su
   salida (`stdout`+`stderr`) en una variable. Solo 2 segundos de emulación,
   sin vídeo ni sonido: basta con que el DIP se cambie y se guarde en el
   `.cfg` al salir; no hace falta ver nada.
7. Busca en esa salida la línea que empieza por `1C1C ` (la que imprime el
   propio `poner_1c1c.lua`, fuera del alcance de este documento). Si no
   aparece, lo cuenta como error y muestra la primera línea que contenga
   "error" o "not found". Si aparece, la imprime tal cual y clasifica el
   resultado según contenga `estado=cambiado`, `estado=ya-estaba`, o ninguno
   de los dos (`otros`).
8. Al final, imprime el resumen: `cambiados=N ya-estaban=N sin-cambio=N
   fallos=N`.

### Ficheros que lee / escribe, y scripts que invoca

- **Lee**: `comun.sh` (vía `source`), las roms del rompath.
- **Escribe indirectamente**: el `.cfg` de cada juego (dentro de `$CFG_DIR`
  o el de MAME por defecto), a través de `poner_1c1c.lua`, que es el que de
  verdad cambia el DIP de tarifa.
- **Invoca**: `mame` con `-autoboot_script poner_1c1c.lua`, opcionalmente bajo
  `xvfb-run`.

### Por qué hay que hacerlo una sola vez por juego

MAME **guarda** el cambio de DIP en el `.cfg` del juego al salir, aunque no
afecte a la partida en curso (según CLAUDE.md, la placa lee la tarifa **al
arrancar**, así que cambiarla por Lua durante la partida no surte efecto
hasta el siguiente arranque). De ahí que esta pasada sea de calibración única:
una vez hecha, todos los arranques siguientes de ese juego ya salen en 1C/1C.

---

## `creditos/buscar_creditos.sh`

**Propósito en una frase:** pasada de calibración que recorre los juegos
lanzando cada uno bajo `buscar_creditos.lua` para **localizar en qué
dirección de RAM guarda su contador de créditos**, y escribe el resultado en
`creditos.dat` con el mismo espíritu que el `hiscore.dat` de MAME.

> La **metodología** con la que `buscar_creditos.lua` decide cuál es la
> dirección correcta (fotografiar la RAM, meter monedas, comparar subidas,
> pulsar START, resolver ambigüedades, distinguir copias espejo, etc.) está
> descrita en detalle en `docs/direcciones-ram.md`; aquí solo se documenta lo
> que hace **este script de shell** — el envoltorio que lanza MAME juego a
> juego y recoge el resultado.

### Uso

```bash
./buscar_creditos.sh                 # todas las roms del rompath
./buscar_creditos.sh pacman dkong    # solo esos
```

### Variables de entorno

| Variable | Por defecto | Efecto |
|---|---|---|
| `MAME_DIR` | Buscado con `vecino()`, igual que `poner_1c1c.sh` | Directorio con el ejecutable `mame` |
| `ROMPATH` | Lo que declare `$MAME_DIR/mame` | Dónde están las roms |
| `SALIDA` | `$AQUI/creditos.dat` | **Fichero que se REESCRIBE ENTERO** al final |
| `CFG_DIR` | El `cfg_directory` de MAME por defecto | Carpeta de `.cfg` a usar (aislar al probar) |
| `MAME_EXTRA` | (vacío) | Opciones extra sin procesar para MAME |

> **Peligro explícito, documentado en CLAUDE.md y que hay que remarcar aquí
> porque está en el propio código (la última línea del script hace
> `> "$SALIDA"`):** el script **reescribe `creditos.dat` entero** con
> únicamente lo que encuentre en esa pasada. Lanzarlo a pelo sobre un
> subconjunto de juegos **borra** las direcciones ya verificadas de los
> juegos que no se incluyan en esa pasada, y también las ~4958 direcciones
> importadas de la colección de cheats. Para probar sobre unos pocos juegos
> sin destrozar la tabla real, hay que fijar `SALIDA=` a un fichero temporal y
> fundir el resultado a mano después; y conviene también fijar `CFG_DIR=` a
> una copia, para que las monedas que la prueba mete no queden grabadas en
> los `.cfg` reales.

### Recorrido paso a paso

1. `source` de `comun.sh`, calcula `ROMPATH`.
2. Comprueba que `$MAME_DIR/mame` sea ejecutable.
3. Lista los juegos a probar (argumentos, o `listar_roms "$ROMPATH"` si no se
   pasó ninguno).
4. Igual que `poner_1c1c.sh`: usa `xvfb-run -a` si no hay `$DISPLAY`, y añade
   `-cfg_directory` si `$CFG_DIR` está fijado.
5. Para cada juego, lanza:
   ```
   mame <juego> -rompath ... [-cfg_directory ...] $MAME_EXTRA \
     -video none -sound none -nothrottle -noswitchres -seconds_to_run 60 \
     -autoboot_script buscar_creditos.lua -autoboot_delay 6
   ```
   Nótese el **`-autoboot_delay 6`** (a diferencia de `creditos.lua`, que
   siempre usa `-autoboot_delay 0` en producción): aquí se le da tiempo a la
   placa a terminar su propio test de RAM/ROM antes de que el script de
   búsqueda empiece a fotografiar la memoria, porque la búsqueda de
   direcciones necesita una RAM ya estable para no confundir el patrón del
   test con el contador de créditos.
6. De toda la salida capturada, busca la **última** línea que empiece por
   `CREDITOS ` (con `tail -1`): las líneas anteriores son mensajes de
   progreso ("probando..."), y la última es el veredicto final. Si no aparece
   ninguna, cuenta el juego como "no arrancó".
7. Si aparece, la imprime, y extrae con `sed` los campos `dir=` (la dirección
   encontrada, o vacío si quedó sin determinar) y `cpu=` (qué CPU, por
   defecto se usa `:maincpu` si el campo viene vacío). Si hay dirección,
   añade una línea `<juego> @<cpu>,program,<dir>` a un acumulador temporal; si
   no, cuenta el juego como fallido.
8. Al terminar todos los juegos, **reescribe `$SALIDA` desde cero**: un
   bloque de comentarios de cabecera (qué es el fichero, cómo se generó, qué
   hacer si un juego da problemas — borrar su línea y volverá a la
   estimación por pulsaciones de START) seguido de las líneas acumuladas,
   ordenadas alfabéticamente (`sort`).
9. Imprime el resumen: `encontrados=N fallidos=N -> $SALIDA`.

### Ficheros que lee / escribe, y scripts que invoca

- **Lee**: `comun.sh` (vía `source`), las roms del rompath.
- **Escribe**: `$SALIDA` (por defecto `creditos.dat`), **sobrescribiéndolo
  entero**.
- **Invoca**: `mame` con `-autoboot_script buscar_creditos.lua`,
  opcionalmente bajo `xvfb-run`.

---

## `creditos/pruebas/correr.sh`

**Propósito en una frase:** el corredor principal de la batería de pruebas del
sistema de créditos — ejecuta, en orden, todas las pruebas que **no necesitan
tener Attract-Mode Plus compilado ni un emulador de verdad**, más una
comprobación final de compatibilidad con Lua 5.5.

Las dos pruebas que sí necesitan MAME/AM+ de verdad están **aparte**, y no las
lanza `correr.sh`: `integracion.sh` y `aviso_mame.sh` (documentadas más
abajo).

### Uso

```bash
./correr.sh
```

Sin argumentos ni subcomandos. `set -eu`: el script se detiene en el primer
mando que falle (`-e`) y trata cualquier variable sin definir como error
(`-u`).

### Variables de entorno

| Variable | Por defecto | Efecto |
|---|---|---|
| `SQ` | `../../extlibs/squirrel` si existe, si no `../../attractplus/extlibs/squirrel` | Dónde están las fuentes de Squirrel 3.0.7 con las que compilar `sqhost` |

### Recorrido paso a paso

1. Se sitúa en su propio directorio (`cd "$(dirname ...)"`).
2. Resuelve `SQ` con la lógica de arriba: como `creditos/pruebas/` está dos
   niveles por debajo de la raíz del repo cuando `creditos/` está fundido
   dentro de `attractplus` (que es la disposición normal desde el
   `git subtree`), el camino relativo es `../../extlibs/squirrel`; si no
   existe ahí (disposición vieja de dos repos hermanos), prueba
   `../../attractplus/extlibs/squirrel`.
3. **Compila `sqhost` si hace falta** (no existe, o `sqhost.cpp` es más nuevo
   que el binario ya compilado): `sqhost` es un intérprete mínimo de Squirrel
   (unas 50 líneas, según CLAUDE.md) compilado con **las mismas fuentes de
   Squirrel 3.0.7 que usa Attract-Mode Plus** (`extlibs/squirrel`), no una
   instalación de Squirrel del sistema. Se compila con
   `g++ -O0 -w -I .../include -I .../squirrel -I .../sqstdlib -o sqhost
   sqhost.cpp <fuentes de squirrel y sqstdlib>`.
4. **`./sqhost pruebas.nut`** — ejercita el plugin `Creditos.nut` contra
   `maqueta.nut`, una imitación de la API de Attract-Mode Plus construida a
   partir del código fuente real y de `Layouts.md`, que reproduce a propósito
   las asperezas reales de esa API (`min()`/`max()` devuelven float, los
   valores de configuración siempre llegan como cadena, los plugins corren
   antes que el layout).
5. Resuelve qué intérprete de Lua usar: prueba `lua5.4`, `lua5.3`, `lua`, en
   ese orden, y se queda con el primero que exista en el PATH. Si no hay
   ninguno, sale con error.
6. Ejecuta, en este orden, con el intérprete de Lua elegido:
   `prueba_tarifa.lua` (el analizador de textos de DIP de tarifa),
   `prueba_monedero.lua` (la contabilidad del monedero compartido: formatos
   de fichero, escritura atómica, el vigilante del botón de moneda),
   `prueba_aviso.lua` (el cuadro de aviso al salir: estimación de lo que
   queda dentro y máquina de estados del diálogo), `prueba_memoria.lua` (la
   lectura de créditos desde la tabla `creditos.dat` y el reparto de subidas
   y bajadas).
7. **`./sqhost prueba_arranque.nut`** — el editor de ajustes del plugin
   "Arranque" (el menú en pantalla para tocar `arranque.dat` desde dentro de
   Attract-Mode Plus).
8. Con Lua otra vez: `prueba_ajustes.lua` (los ajustes por juego de
   `arranque.dat`), `prueba_cerrojo.lua` (el cerrojo del botón de moneda: que
   el jugador no pueda meter más monedas que créditos tenía).
9. **`./prueba_importar.sh`** — invoca el script hermano de pruebas del
   importador de la colección de cheats (documentado más abajo) como un
   subproceso más de la batería.
10. **Comprobación de compatibilidad con Lua 5.5**: busca un `luac` que
    informe de ser la versión 5.5 (`luac5.5` o `luac`, comprobando con
    `$c -v 2>&1 | grep -q "Lua 5\.5"`). El motivo, explicado en un comentario
    extenso: **la cabina tiene dos binarios de MAME con Lua distinta** — el
    GroovyMAME que compila este repo lleva Lua 5.4, pero el `mame`/`lua` del
    sistema de GroovyArcade es 5.5.1. En Lua 5.5, la variable de control de
    un bucle `for` es **constante**, así que reasignarle un valor
    (`linea = linea:gsub(...)` dentro de `for linea in f:lines() do`) es un
    **error de compilación**, y el fichero entero deja de cargar. Este fallo
    es **mudo** al probar con Lua 5.4 (que sí lo permite) — le pasó de hecho a
    `ajustes.lua` en el pasado. Si se encuentra un `luac` de 5.5, corre
    `luac -p` (solo comprobar sintaxis, sin ejecutar) sobre **todos** los
    `.lua` de `creditos/` (`../*.lua`, es decir, un nivel por encima de
    `pruebas/`); si alguno falla, lo reporta y el script termina con código de
    error. Si no hay ningún `luac` de 5.5 disponible en la máquina actual, se
    salta esta comprobación avisando, en vez de romper toda la batería por no
    poder verificarlo ahí.

### Ficheros que lee / invoca

- **Lee**: `pruebas.nut`, `maqueta.nut`, `prueba_tarifa.lua`,
  `prueba_monedero.lua`, `prueba_aviso.lua`, `prueba_memoria.lua`,
  `prueba_arranque.nut`, `prueba_ajustes.lua`, `prueba_cerrojo.lua`, y todos
  los `.lua` de `creditos/` (para la comprobación de Lua 5.5).
- **Compila**: `sqhost` desde `sqhost.cpp` y las fuentes de Squirrel.
- **Invoca**: `./prueba_importar.sh` como subproceso.
- **No necesita**: ni Attract-Mode Plus compilado, ni GroovyMAME, ni ninguna
  rom. Es la batería "rápida y sin dependencias externas".

---

## `creditos/pruebas/aviso_mame.sh`

**Propósito en una frase:** prueba el cuadro de aviso al salir con créditos
dentro (`aviso.lua`) y buena parte de la lógica de arranque tapado / cerrojo /
NVRAM, **dentro de GroovyMAME real** (no de una maqueta), en una veintena de
escenarios encadenados.

### Uso

```bash
./aviso_mame.sh
```

Sin argumentos. Usa un juego fijo por defecto (`pacman`), configurable por
entorno.

### Variables de entorno

| Variable | Por defecto | Efecto |
|---|---|---|
| `MAME_DIR` | `vecino()` en `../../../groovymame_src`, `../../groovymame_src` o `~/groovymame_src` (un nivel más profundo que otros scripts, porque este vive en `pruebas/`) | Directorio con el ejecutable `mame` |
| `ROMPATH` | Lo que declare MAME | Dónde están las roms |
| `JUEGO` | `pacman` | Sobre qué juego se ejecutan todos los escenarios |

Además, cada escenario pasa sus propias variables `GA_*` a `creditos.lua`
(`GA_PRUEBA_MONEDA`, `GA_PRUEBA_SALIR`, `GA_PRUEBA_START`, `GA_ARCHIVO`,
`GA_AVISO`, `GA_AVISO_ESPERA`, `GA_ARRANQUE`, `GA_ASENTAR`, `GA_AJUSTES`,
etc.) — son variables propias de `creditos.lua`/`monedero.lua`/`aviso.lua`
(fuera de alcance de este documento como scripts de shell), pero es este
script quien las inyecta escenario a escenario.

### La limitación de la simulación (documentada en la cabecera)

La tecla de salir y el botón START **se fingen** sustituyendo las funciones
que `creditos.lua` usa para leerlos (en un script auxiliar,
`integracion/mame_con_captura.lua`), no son pulsaciones físicas reales. Eso
alimenta fielmente la máquina de estados de `aviso.lua`, pero tiene un límite
explícito: en el escenario "no avisar" solo se puede comprobar que **no
frenamos la salida**, no que MAME realmente saldría, porque salir es
comportamiento nativo de MAME que aquí no se toca ni se simula.

Cómo se sabe si la partida "siguió" o no: el envoltorio Lua saca una captura
en el frame `GA_SNAP_FRAMES`, y escribe una línea `[prueba] captura` en el
log. Si MAME salió antes de llegar a ese frame, esa línea sencillamente no
aparece.

### Preparación común

- Crea un directorio temporal `$T` con una subcarpeta `mamecfg`, en la que
  copia el `.cfg` **real** del juego desde `~/.mame/cfg/$JUEGO.cfg` si existe
  — así cualquier mapeo de entrada propio de la cabina para ese juego se
  respeta durante la prueba (relevante por el problema documentado en
  CLAUDE.md de los juegos con mapeo propio de la moneda, que rompía el
  cerrojo).
- `FRAME_CORTE=760`: con `-autoboot_delay 0` (el arranque instantáneo, sin
  esperar segundos de reloj) todo ocurre 360 frames antes que con el viejo
  esquema de `-autoboot_delay 6`, así que el frame de captura se adelanta en
  la misma medida para seguir representando "el mismo punto" de la partida.
- Prepara dos ficheros de monedero de partida (`monedero.txt` con saldo 10,
  `corto.txt` con saldo 2) que algunos escenarios concretos reutilizan.

### `correr()`, el lanzador común de cada escenario

`correr(nombre, variables...)`: escribe un monedero fresco de saldo 5 en
`$T/<nombre>.txt` (salvo que el escenario pase su propio `GA_ARCHIVO` para
sobrescribirlo), y lanza:

```bash
env GA_MONEDERO=1 GA_ARCHIVO=... "$@" GA_VERBOSO=1 GA_SNAP=... GA_SNAP_FRAMES=$FRAME_CORTE \
  xvfb-run -a ./mame "$JUEGO" -rompath ... -cfg_directory ... \
  -snapshot_directory ... -video soft -sound none -nothrottle -noswitchres \
  -window -resolution 640x480 -seconds_to_run 16 \
  -autoboot_script integracion/mame_con_captura.lua -autoboot_delay 0 \
  > "$T/<nombre>.log" 2>&1
```

`GA_MONEDERO=1` está fijado en casi todos los escenarios porque prueban el
**monedero compartido** (el diseño con contador físico Arduino), que desde el
2026-08-29 **no** es el modo por defecto de la cabina real (el modo por
defecto son monedas de verdad, sin monedero) — el escenario 9 en adelante
prueba explícitamente ese modo por defecto, sin `GA_MONEDERO`.

Tres funciones de aserción minúsculas: **`comprobar(nombre, condición,
detalle)`** imprime `ok`/`FALLO` y cuenta los fallos; **`tiene(nombre,
patrón)`** hace `grep -q` sobre el log de ese escenario; **`sigue(nombre)`**
comprueba si apareció la línea `[prueba] captura` (la partida no se cortó).

### Los escenarios

Cada uno lanza uno o varios `mame` bajo Xvfb y comprueba varias líneas del
log. En resumen (los nombres entre paréntesis son el nombre interno que usa
`correr()`, es decir, el prefijo de sus ficheros en `$T`):

1. **(`frena`)** el jugador mete monedas y luego intenta salir → se le
   avisa, se le cuenta lo que hay dentro (leído de la RAM real, porque
   `pacman` está en `creditos.dat`), y la partida **no** se corta.
2. **(`confirma`)** segunda pulsación de salir → confirma, y MAME **se
   cierra** de verdad.
3. **(`cancela`)** tras el aviso, pulsar START → cancela la salida y sigue
   jugando.
4. **(`espera`)** si nadie contesta en `GA_AVISO_ESPERA` frames, el cuadro se
   retira solo y **no** sale (ante la duda, la partida sigue).
5. **(`mirar`)** entrar a mirar un juego y salir sin meter monedas → no
   aparece ningún aviso.
6. **(`loco`)** el jugador mete 4 monedas de un monedero de 10 → las 4 se
   cobran (contador físico visible), jugar **no** vuelve a cobrar, y el
   monedero queda en 6.
7. **6b (`cerrojo`)** con solo 2 créditos disponibles, se intentan meter 4
   monedas → el cerrojo se monta con el número justo, entran 2, se bloquea el
   botón, las otras 2 se rechazan, y el monedero queda en 0 (nunca negativo).
8. **6c (`pillo`)** el "jugador pillo": pulsar la moneda nada más arrancar
   (frames 5, 25, 45, 65), reproduciendo el agujero real que encontró Eloy →
   con `-autoboot_delay 0` el cerrojo ya está puesto desde el frame 0, así que
   las 4 pulsaciones se rechazan, no entra ningún crédito, y el barrido de
   limpieza cubre el arranque entero.
9. **6e (`arranque`)** con el monedero **lleno**, pulsar la moneda durante el
   arranque tapado tampoco cuesta nada (la placa ignora físicamente las
   monedas mientras hace su autotest, así que cobrarlas sería cobrar por
   nada) — el monedero sale intacto.
10. **6d (`pronto`)** una moneda metida **mientras la RAM aún se asienta**
    (sin arranque tapado, con asentamiento largo a propósito) no se le quita
    al jugador al barrer: el barrido respeta lo que ya está pagado.
11. **6f (`barrido`)** sin arranque tapado, el barrido debe quitar los
    créditos que la máquina traiga puestos y no estén pagados (el patrón del
    test de RAM de Pac-Man, o restos de NVRAM), sin cobrarle nada al jugador.
12. **6g (`devuelve`)** si la placa no recoge la moneda a tiempo (dentro de
    `GA_COMPROBAR` frames), el crédito cobrado se **devuelve**, y el monedero
    acaba como empezó.
13. **7 (`apagado`)** `GA_AVISO=0` desactiva el aviso del todo: no se monta y
    no frena nada.
14. **8 (`memoria`)** confirma que, al estar en `creditos.dat`, los créditos
    del cuadro de aviso se leen de la RAM real y el consumo también sale de
    ahí (no de una estimación por pulsaciones de START).
15. **9 (`reales`)** el modo **por defecto** de monedas de verdad (sin
    `GA_MONEDERO`): no busca ningún fichero de monedero, monta el cerrojo sin
    límite ("puede meter las que quiera"), sigue tapando el arranque igual, y
    sigue avisando al salir con créditos dentro; la partida no se corta.
16. **9b (`carga`)** sin monedero, la moneda durante la carga tampoco cuenta
    (reproduce el caso de Q*bert con 52 créditos regalados): el botón está
    cerrado mientras carga, las 4 pulsaciones se rechazan, y ninguna entra.
17. **10 (`reinicio`)** un juego que **reinicia la placa a media carga**
    (`elevator`) hace que MAME ejecute el script de autoboot **dos veces**; se
    comprueba que el script lo detecta ("la placa se reinició") y que el
    estado final del emulador es el correcto — velocidad normal
    (`throttled=true`), sonido no silenciado (`mute=false`), y el botón de
    moneda sigue vivo (no "0 códigos", que sería un botón muerto para
    siempre).
18. **11 (`nvram`)** confirma que `nvram=0` en un `arranque.dat` a medida
    evita que Tapper escriba su fichero de NVRAM (comprobando que el fichero
    físico no aparece), y que sin ese ajuste sí se escribe.

Al final, imprime `# fallos=$fallos` y sale con código de error si hubo
alguno (`exit $(( fallos > 0 ))`).

### Ficheros que lee / escribe, y scripts que invoca

- **Lee**: `comun.sh` (vía `source`), el `.cfg` real del juego en
  `~/.mame/cfg/`, y varios `.lua` auxiliares en `integracion/` (fuera de
  alcance como scripts de shell).
- **Escribe**: todo dentro de un directorio temporal que se borra al salir
  (`trap ... EXIT`) — ficheros de monedero, `.cfg` aislados, logs, capturas,
  y en el escenario 11, ficheros de NVRAM y un `arranque.dat` de prueba.
- **Invoca**: `mame` bajo `xvfb-run`, con `-autoboot_script
  integracion/mame_con_captura.lua` en casi todos los escenarios, y con
  `-autoboot_script ../creditos.lua` directamente en el escenario 11 (NVRAM).

---

## `creditos/pruebas/integracion.sh`

**Propósito en una frase:** la prueba de integración de verdad, de extremo a
extremo — Attract-Mode Plus **compilado**, con el plugin de créditos activado
de verdad, lanzando GroovyMAME real y volviendo, todo bajo Xvfb en un
directorio de configuración desechable que no toca `~/.attract` ni `~/.mame`.

### Uso

```bash
./integracion.sh
```

Sin argumentos.

### Variables de entorno

| Variable | Por defecto | Efecto |
|---|---|---|
| `REPO` | `vecino()` busca `extlibs/squirrel` en `../..`, `../../attractplus` o `~/attractplus` | Raíz del repo de Attract-Mode Plus, para copiar su `config/` de plantilla |
| `AM` | `$REPO/attractplus` | El binario compilado de Attract-Mode Plus |
| `MAME_DIR` | `vecino()` en `../../../groovymame_src`, `../../groovymame_src` o `~/groovymame_src` | Directorio con el ejecutable `mame` |
| `ROMPATH` | Lo que declare MAME | Dónde están las roms |
| `JUEGO` | `pacman` | Juego usado para la prueba |
| `GUARDAR` | (vacío) | Si se fija a una ruta, copia ahí las capturas y el log tras terminar (el directorio temporal se borra siempre al salir) |

### Recorrido paso a paso

1. Comprueba que tanto `$AM` como `$MAME_DIR/mame` sean ejecutables; si no,
   sale.
2. Crea un directorio de configuración **completo y desechable**
   (`$T/config`), copiando dentro **todo** el `config/` real del repo
   (`cp -r "$REPO"/config/* "$D"/`) y luego:
   - **Borra `intro/`** — el intro de Attract-Mode se "comería" las primeras
     señales que dispara el layout de prueba antes de que este tenga el
     control, así que se quita de en medio para la prueba.
   - Copia el plugin `Creditos.nut` (por si la copia de `config/` no lo
     trajera ya, o para asegurarse de que es el actual).
   - Instala un layout de prueba propio (`integracion/layout.nut`) en
     `layouts/PruebaCreditos/`, que es el que **dispara las señales** que en
     una cabina real dispararía el mando: bajo Xvfb no hay nadie que pulse
     botones.
3. Escribe un `emulators/groovymame.cfg` de prueba que apunta al
   `MAME_DIR/mame` real, con argumentos fijos que incluyen
   `-autoboot_script integracion/mame_con_captura.lua -autoboot_delay 0` y
   `-seconds_to_run 16` — MAME se cierra solo tras ese tiempo y saca su propia
   captura.
4. Escribe un `plugins.cfg` minimalista que activa el plugin `Creditos` con
   la señal `custom1` y un `buzon` (el fichero de intercambio del monedero)
   apuntando a un temporal, y un `attract.cfg` con un único display `Arcade`
   que usa el layout `PruebaCreditos` y la romlist `groovymame`.
5. Construye la romlist con `"$AM" --config "$D" --build-romlist groovymame`;
   si falla, muestra las últimas 5 líneas del log y sale.
6. Lanza el frontend bajo `xvfb-run`, con un `timeout 300` de seguridad:
   `env GA_MONEDERO=1 GA_VERBOSO=1 GA_ARCHIVO=... GA_SNAP=...
   GA_SNAP_FRAMES=650 GA_PRUEBA_MONEDA=480 GA_PRUEBA_START=560
   timeout 300 xvfb-run -a "$AM" --config "$D"` — `GA_PRUEBA_MONEDA` y
   `GA_PRUEBA_START` son los frames en los que el layout de prueba dispara,
   respectivamente, la señal de meter moneda y la de pulsar START dentro de
   MAME.

### Las cuatro comprobaciones

1. **El marcador se dibuja encima del layout**: usando ImageMagick (`magick`
   o `convert`, el que exista), mide el brillo medio de una región de la
   captura final donde debería estar el marcador y de otra región donde solo
   está el fondo del layout (un rectángulo opaco a pantalla completa, puesto
   ahí a propósito para esta prueba), y comprueba que la primera sea
   sensiblemente más brillante — si no, el marcador estaría tapado por el
   fondo (lo que pasaría sin el `zorder` máximo y sin crearlo en
   `Transition.StartLayout`).
2. **Solo un crédito va al juego, no el monedero entero**: comprueba en el
   log de AM+ la línea `saldo 3, a insertar 0` — el diseño de "hucha" no
   inserta nada al lanzar, a diferencia de un sistema que insertara el
   monedero completo. También comprueba que **no** aparezca "creditos
   sincronizados" (el monedero no se vuelca en la RAM del juego, lo que
   metería los 3 créditos de golpe y dejaría el botón de moneda sin efecto
   visible), y que el cerrojo se monte con el número correcto ("cerrojo
   puesto: el jugador puede meter 3").
3. **Meter una moneda dentro de la partida no cuesta nada por sí sola**:
   comprueba "quedan 2 en el monedero" (se descuenta al **meter**, visible en
   el contador físico) y que jugarla (pulsar START) **no** la cobre otra vez
   ("el juego se lleva 1 credito, quedan 2"). Y que el frontend, al volver,
   adopte ese saldo correcto (busca una línea `ESTADO` propia del layout de
   prueba con `partidas=1 creditos=2`).
4. **Con lo que queda se juega otra partida**: cuenta cuántas veces aparece
   "a insertar" en el log (debe ser 2, una por cada lanzamiento de MAME), y
   comprueba que tras la segunda partida la línea `ESTADO` diga
   `partidas=2 creditos=1`.

Al final imprime `# fallos=$fallos` y sale con el código correspondiente.

### Ficheros que lee / escribe, y scripts que invoca

- **Lee**: todo el `config/` del repo principal (como plantilla), y
  `integracion/layout.nut` / `integracion/mame_con_captura.lua` (auxiliares,
  fuera de alcance como scripts de shell).
- **Escribe**: un `$D` (config de AM+) y un `$T` (temporal general)
  completos, que se borran al salir salvo que `GUARDAR` diga lo contrario.
- **Invoca**: `"$AM" --build-romlist` y `"$AM" --config "$D"` bajo
  `xvfb-run`, que a su vez lanza `mame` según el `groovymame.cfg` de prueba.

---

## `creditos/pruebas/prueba_importar.sh`

**Propósito en una frase:** prueba unitaria de `importar_cheats.py` (Python,
fuera de alcance de este documento) — el importador que rastrea la colección
de cheats de MAME buscando direcciones de créditos y las añade a
`creditos.dat` marcadas como `(cheat)`.

### Uso

```bash
./prueba_importar.sh
```

Sin argumentos ni variables de entorno propias.

### Recorrido paso a paso

1. Crea un directorio temporal con una subcarpeta `xml/` y tres ficheros de
   prueba:
   - **`galaga.xml`** — un cheat bien formado con dos entradas: "Infinite
     Lives" (que debe ser **ignorado**, no es de créditos) e "Infinite
     Credits" (que debe ser **capturado**).
   - **`mrdo.xml`** — dos entradas: "Coin Counter Freeze" (debe ignorarse: es
     un contador de monedas físicas, no de créditos) y una llamada
     literalmente **"Credits"**, sin la palabra "Infinite" delante (debe
     reconocerse igualmente como cheat de créditos).
   - **`roto.xml`** — XML deliberadamente **inválido**, para comprobar que un
     fichero roto no tumba la importación entera.
2. Escribe un `creditos.dat` de partida con una única línea ya verificada
   (`pacman @:maincpu,program,4e6e`), que debe **sobrevivir intacta**.
3. Ejecuta `importar_cheats.py <carpeta xml> --salida creditos.dat`,
   capturando su salida.
4. Comprueba, con `grep` sobre el `creditos.dat` resultante:
   - Que se extrajo la dirección correcta de Galaga
     (`galaga @:maincpu,program,9a12`).
   - Que **no** se coló el cheat de vidas (`8320`).
   - Que **no** se coló el contador de monedas (`e000`).
   - Que sí se capturó el cheat llamado solo "Credits" de Mr. Do!
     (`mrdo @:maincpu,program,e015`).
   - Que la línea de `pacman` ya verificada **no se pisó**.
   - Que la entrada de Galaga quedó marcada `# (cheat)`.
   - Que la salida por pantalla menciona "ficheros mirados" (o sea, que el
     XML roto no interrumpió el recuento final).

Al final, `# fallos=$fallos` y el código de salida correspondiente.

### Ficheros que lee / escribe, y scripts que invoca

- **Lee/escribe**: solo dentro de su propio directorio temporal (que se borra
  al salir).
- **Invoca**: `../importar_cheats.py` (Python).
- Es invocado, a su vez, por `correr.sh` como parte de la batería principal.

---

## `creditos/pruebas/rescate.sh`

**Propósito en una frase:** comprobación manual (no forma parte de
`correr.sh`) de que un cambio en la tabla de puntuaciones de un juego, hecho
en la RAM, es recogido correctamente por el propio plugin `hiscore` de MAME
**y** que el fichero `.hi` resultante coincide exactamente con lo que se
escribió — el eslabón de "rescate de puntuaciones" que conecta con el sistema
de `puntajes.py` (Python, fuera de alcance de este documento).

### Uso

```bash
./rescate.sh <carpeta-temporal> <juego> [juego...]
```

El primer argumento (`$S`, vía `shift` tras leer `S="$1"`) es una carpeta de
trabajo que el propio script **borra y recrea** al principio
(`rm -rf "$S/e2e"; mkdir -p "$S/e2e/hi" "$S/e2e/cfg" "$S/e2e/nv"`). El resto
de argumentos son los juegos a comprobar.

No lee variables de entorno; las rutas de MAME (`~/Dev/arcade/groovymame_src/mame`)
y del repo de créditos (`/home/eloy/Dev/arcade/attractplus/creditos`) están
**fijadas a mano dentro del script** (`MAME=`, `CRED=`), a diferencia del
resto de scripts del proyecto, que las detectan con `vecino()`. Esto significa
que este script en concreto **no es portable a otra máquina o disposición de
carpetas sin editarlo**.

### Recorrido paso a paso

Para cada juego pasado como argumento:

1. Consulta, con un pequeño script Python embebido que importa
   `puntajes.py` (añadiendo `creditos/` al `sys.path`), el bloque de memoria
   que `hiscore.dat` declara para ese juego
   (`leer_hiscore_dat(ruta_hiscore_dat())`), y lo formatea como
   `cpu,espacio,dirección-hex,longitud-hex` separado por `;`. Si el juego no
   tiene bloque declarado en `hiscore.dat`, lo salta con un aviso.
2. Lanza MAME con un script Lua propio, **`rescate.lua`** (no documentado
   aquí: pertenece al lado Python/puntuaciones del proyecto, fuera del
   alcance de este documento sobre scripts de shell), pasándole
   `GA_D_BLOQUES` (el bloque que se acaba de calcular) y `GA_D_FRAME=1800`;
   habilita el plugin real `hiscore` de MAME (`-plugin hiscore -pluginspath
   ...`) y apunta `-homepath`, `-cfg_directory` y `-nvram_directory` a
   subcarpetas del directorio temporal, para no tocar la configuración real.
3. De la salida de MAME extrae con `grep -o` el valor `despues=` (el volcado
   hexadecimal que `rescate.lua` dice haber escrito en la RAM).
4. Comprueba si existe el fichero `<carpeta>/e2e/hiscore/<juego>.hi` que el
   plugin `hiscore` debería haber escrito. Si existe, lo vuelca a hexadecimal
   con `xxd -p | tr -d '\n'` y lo compara **byte a byte** contra lo que
   `rescate.lua` dijo haber escrito: si coinciden, `OK`; si no, `DIFIERE`. Si
   el fichero no existe en absoluto, `SIN .hi`.
5. Imprime una línea por juego: `juego|estado|primeros 24 caracteres del
   volcado|nombre del fichero .hi`.

### Ficheros que lee / escribe, y scripts que invoca

- **Lee**: `hiscore.dat` de MAME (vía `puntajes.py`), las roms del sistema.
- **Escribe**: todo dentro de `<carpeta>/e2e/` (que él mismo recrea al
  principio) — cfg, nvram, y el `hiscore/<juego>.hi` que escribe el propio
  plugin `hiscore` de MAME.
- **Invoca**: `mame` con `-plugin hiscore` y `-autoboot_script rescate.lua`;
  y un intérprete `python3` embebido para consultar `puntajes.py`.

### Nota sobre su portabilidad

A diferencia de todos los demás scripts documentados aquí, `rescate.sh` no
usa `vecino()` ni `comun.sh`: las rutas de MAME y del repo están escritas a
fuego dentro del fichero. Si se necesita en otra máquina, hay que editar las
líneas `MAME=` y `CRED=` a mano antes de usarlo.
