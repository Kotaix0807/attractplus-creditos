# Cómo está organizado esto

Mapa del proyecto: qué hay en cada sitio, quién lee qué, y las trampas que ya
nos han mordido. Para el **por qué** de cada decisión, `CLAUDE.md`.

Regla de oro: **hay cuatro sitios distintos con código, y sólo dos están bajo
git.** Si algo «no se aplica», casi siempre es que tocaste una copia que no es
la que corre.

---

## Los cuatro sitios

| Sitio | Qué hay | ¿Git? |
|---|---|---|
| `~/attractplus/` | El frontend (código de AM+) + lo nuestro en Squirrel y Python | **sí** |
| `~/groovyarcade-creditos/` | Todo lo de MAME, en Lua, y las pruebas | **sí** |
| `~/groovymame_src/` | El emulador, con un parche de 22 líneas | el parche, en `parches/` |
| `~/snap/arduino/85/Arduino/Arcade/` | El firmware del contador físico | copia en `arduino/` |

Y un quinto que **no es código pero manda más que el código**:

| `~/.attract/` | La instalación de verdad de la cabina | no |

---

## El flujo, en una imagen

```
   chauchera                                   monedas de verdad
       │                                              │
       v                                              v
  ┌──────────┐   ~/.attract/creditos.txt   ┌────────────────────┐
  │   AM+    │ ─────────────────────────>  │  GroovyMAME        │
  │ frontend │                             │  + creditos.lua    │
  └──────────┘                             └────────────────────┘
       │                                              │
       │ (monedero, hoy APAGADO)                      │ arranque tapado
       v                                              │ cerrojo de la moneda
  daemon.py ──> puerto serie ──> Arduino               │ aviso al salir
```

**Hoy la cabina va a monedas de verdad**: el plugin de créditos está
desactivado y el monedero apagado. Sólo quedan en pie el arranque tapado y el
aviso de salida. El sistema del monedero entero sigue montado y probado en la
rama `monedero-frontend` de los dos repos.

---

## `~/attractplus/` — el frontend

Es el código fuente de Attract-Mode Plus. Lo nuestro es esto:

| Fichero | Qué hace |
|---|---|
| `CLAUDE.md` | La memoria del proyecto: decisiones, mediciones y trampas |
| `ESTRUCTURA.md` | Este fichero |
| `config/plugins/Creditos.nut` | El monedero del frontend. **Desactivado** |
| `config/plugins/Arranque.nut` | Menú en la cabina para ajustar la carga de cada juego |
| `daemon.py` | Vigila el monedero y lo manda al Arduino por el puerto serie |
| `src/scraper_general.cpp` | Parcheado: usa el scraper de MAME y no thegamesdb |

Compilar (unos 2 minutos):

```bash
cd ~/attractplus && PATH=/usr/lib/ccache:$PATH mold -run make -j10
```

### ⚠️ Los plugins hay que COPIARLOS

El que corre **no** es el del repo, es el de `~/.attract/plugins/`. Editar el
repo y no copiar es la forma más rápida de volverse loco:

```bash
cp ~/attractplus/config/plugins/*.nut ~/.attract/plugins/
```

Para comprobar si están desincronizados:

```bash
for f in Creditos.nut Arranque.nut; do
  diff -q ~/attractplus/config/plugins/$f ~/.attract/plugins/$f || echo "  ^ $f desincronizado"
done
```

---

## `~/groovyarcade-creditos/` — todo lo de MAME

`creditos.lua` es el que arranca (lo lanza el emulador con `-autoboot_script`) y
carga a los demás con `dofile`.

| Fichero | Qué hace |
|---|---|
| `creditos.lua` | El principal: arranque tapado, cerrojo, aviso, monedero |
| `ajustes.lua` | Lee `arranque.dat` (los ajustes por juego) |
| `cerrojo.lua` | Cierra el botón de moneda mientras la placa arranca |
| `aviso.lua` | El cuadro de «dejas créditos dentro» al salir |
| `memoria.lua` | Lee y escribe los créditos en la RAM del juego |
| `monedero.lua` | La contabilidad del monedero. No habla con MAME, a propósito |
| `tarifa.lua` | Entiende el DIP de tarifa (1 moneda = N créditos) |

### Los dos ficheros de datos

| | Qué es | Quién lo edita |
|---|---|---|
| `arranque.dat` | Velocidad y segundos de carga **por juego** | tú, a mano o desde la cabina |
| `creditos.dat` | Dónde guarda cada juego sus créditos en la RAM | `buscar_creditos.sh`, una vez |

**Son cosas distintas y no dependen una de otra.** `creditos.dat` sólo hace
falta para el barrido de créditos y para `auto=1`.

### Herramientas de una sola pasada

| Herramienta | Qué hace |
|---|---|
| `arte.sh` | Baja marquesina, captura, flyer y rueda de un juego |
| `videos.sh` | Graba con el emulador un vídeo de muestra de cada juego |
| `buscar_creditos.sh` | Encuentra la dirección de los créditos ejecutando el juego |
| `poner_1c1c.sh` | Deja el DIP de tarifa en 1 moneda = 1 crédito |
| `importar_cheats.py` | Saca direcciones de la colección de cheats de MAME |

---

## `~/groovymame_src/` — el emulador

Compilado desde fuente, con **un parche de 22 líneas en dos ficheros**, sin
commitear (`git diff` para verlo):

- `src/frontend/mame/ui/info.cpp` — sin avisos de emulación imperfecta
- `src/frontend/mame/ui/ui.cpp` — sin pantalla de avisos y sin los mensajes de
  carga (`Initializing...`, `Loading Machine (N%)`)

Recompilar:

```bash
cd ~/groovymame_src && PATH=/usr/lib/ccache:$PATH mold -run make -j10 NOWERROR=1 USE_QTDEBUG=0
```

---

## `~/.attract/` — la instalación de verdad

**Aquí es donde la cabina lee todo.** Y lo importante:

> ⚠️ **AM+ reescribe estos ficheros al salir.** Edítalos con AM+ **cerrado** o
> te los machaca.

| Fichero | Qué manda ahí | Trampa conocida |
|---|---|---|
| `config/attract.cfg` | Teclas del frontend (`input_map`) | Asignar una tecla a un plugin **se la quita** al menú. Así se perdió Tab |
| `config/plugins.cfg` | Ajustes de cada plugin, incluida su tecla | Un valor guardado aquí **manda sobre** el valor por defecto del `.nut` |
| `emulators/groovymame.cfg` | Cómo se lanza MAME | Aquí van `-autoboot_script` y `-autoboot_delay 0` |
| `plugins/*.nut` | Los plugins **que de verdad corren** | Copias, no enlaces: hay que sincronizar |
| `romlists/groovymame.txt` | La lista de juegos | La regenera AM+ |
| `scraper/groovymame/…` | Marquesinas, capturas, flyers y ruedas | AM+ mira aquí solo, sin configurar rutas. Para un clon, el arte va con el nombre del **padre** |
| `creditos.txt` | El monedero compartido | Hoy no se usa (monedas de verdad) |

Las copias `*.antes*` son respaldos de cuando algo se rompió. Se pueden borrar.

### Y fuera de ahí

| Fichero | Qué manda ahí |
|---|---|
| `~/.mame/cfg/<juego>.cfg` | Mapeos y DIP por juego. Un mapeo propio de la moneda **impide** que el cerrojo funcione |
| `~/.mame/nvram/<juego>/nvram` | La memoria del juego. Algunos guardan **créditos** ahí: `nvram=0` en `arranque.dat` |

---

## Instalar en otra máquina

```bash
git clone <este repo>              ~/attractplus
git clone <groovyarcade-creditos>  ~/groovyarcade-creditos
cd ~/attractplus && ./instalar.sh
```

`instalar.sh` crea `~/.attract`, copia plugins, layout, módulos y configuración,
y **sustituye las rutas absolutas** por las de esa máquina (el emulador, las
roms y el repo de créditos se detectan solos, o se pasan por entorno:
`MAME=… ROMS=… CREDITOS=… ./instalar.sh`).

Luego dice lo que falta: compilar el frontend, aplicar el parche del emulador
(`parches/groovymame-sin-avisos.patch`), construir la romlist y generar artes y
vídeos.

**Lo que NO lleva el repo, a propósito:**

| | por qué |
|---|---|
| Artes y vídeos (40 MB) | se regeneran en ~10 minutos con `--scrape-art` y `videos.sh`, y sólo necesitan las roms |
| El binario de AM+ | se compila |
| Las roms | no son nuestras |

**Lo que respeta si ya existe**: `config/attract.cfg` (ahí están tus teclas) y
`config/displays.cfg`. Lo demás lo reescribe, guardando `*.antes_instalar`.

**Probado en un `HOME` vacío**, no leído: instala, construye la romlist y AM+
arranca con el layout, los logos y la lista sin un solo error. Esa prueba
destapó que faltaba copiar `modules/` — sin él el layout revienta con un
`the index 'FadeArt' does not exist` que no dice nada del módulo que falta.

## Las pruebas

```bash
cd ~/groovyarcade-creditos/pruebas
./correr.sh          # 390 comprobaciones, sin emulador ni frontend (segundos)
./aviso_mame.sh      # 56 dentro de MAME de verdad (minutos)
./integracion.sh     # 9 con AM+ de verdad, bajo Xvfb (minutos)
```

`correr.sh` es la que se pasa siempre. Las otras dos, cuando se toca el
comportamiento dentro del emulador o del frontend.

Para trastear con Squirrel sin arrancar AM+: `./sqhost juega.nut`.

---

## Las ramas

| Rama | Qué es |
|---|---|
| `master` | Lo que corre hoy: monedas de verdad |
| `monedero-frontend` | El sistema completo del monedero, por si se retoma |

Están en los **dos** repos y hay que moverlas juntas.

---

## Cinco trampas que ya nos costaron caro

1. **Editas el repo y no la copia instalada.** Los plugins corren desde
   `~/.attract/plugins/`.
2. **AM+ reescribe su configuración al salir.** Tócala con AM+ cerrado.
3. **Un valor guardado en `plugins.cfg` manda sobre el defecto del `.nut`.**
   Cambiar el defecto en el código no cambia nada si ya hay un valor guardado.
4. **Asignar una tecla a un plugin se la quita a quien la tuviera.** Así se
   perdió el Tab del menú.
5. **`segundos=0` en `arranque.dat` desactiva también la velocidad**, porque la
   velocidad se aplica *durante* esa ventana.
