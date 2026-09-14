# Documentación de la cabina arcade (créditos + puntajes + vídeo)

Este directorio reúne **toda la documentación del proyecto** de Eloy (el sistema
de créditos, puntajes, arranque y vídeo montado sobre GroovyMAME + Attract-Mode
Plus). Los ficheros de la raíz del repo y de `extlibs/`, `util/`, `src/`,
`config/modules/` y `config/layouts/` son de **Attract-Mode Plus (upstream)** y no
forman parte de este proyecto.

`CLAUDE.md` sigue en la raíz del repo a propósito: es lo que Claude Code carga como
instrucciones del proyecto, y guarda el **por qué** de cada decisión con todo su
historial. Esta carpeta es el **qué** y el **cómo**.

## Índice

| Documento | Qué contiene |
|---|---|
| [`ESTRUCTURA.md`](ESTRUCTURA.md) | El mapa del repo: qué hay en cada carpeta, quién lee qué fichero de configuración y las trampas de sincronización (repo ↔ cabina). |
| [`lua.md`](lua.md) | Funcionamiento **a fondo de cada script Lua** (`creditos.lua` y sus módulos): qué hace, cómo se carga, sus variables `GA_*`, su recorrido frame a frame y la API de MAME que usa. |
| [`sh.md`](sh.md) | Funcionamiento **a fondo de cada script de shell** (`instalar.sh`, `videos.sh`, `grabar.sh`, `cabina.sh`, `pantalla-auto.sh`, los `comun.sh`, las pruebas…). |
| [`py.md`](py.md) | Funcionamiento **a fondo de cada script Python** (`puntajes.py`, `hi2txt.py`, `buscar_tabla.py`, `auditar_puntajes.py`, `importar_cheats.py`, el demonio del Arduino, `pantalla.py`, `patron.py`…) y los **formatos de datos** que manejan. |
| [`direcciones-ram.md`](direcciones-ram.md) | **Cómo se localizan las direcciones de RAM** de créditos y de puntajes, con el máximo detalle: el método del buscador de trucos, la prueba funcional, hi2txt-xml, la búsqueda por rejilla de iniciales y las trampas. Empieza por aquí si quieres entender lo más difícil del proyecto. |
| [`puntajes.md`](puntajes.md) | Informe técnico del rescate y descifrado de puntuaciones (histórico, con la cobertura juego a juego). |
| [`INFORME-CREDITOS-NVRAM.md`](INFORME-CREDITOS-NVRAM.md) | Informe de qué juegos arrancan con créditos guardados en la NVRAM y cómo se limpian. |

## Por dónde empezar según lo que quieras

- **Entender cómo funciona el sistema de créditos** → `lua.md` (empieza por
  `creditos.lua`), y `direcciones-ram.md` para la parte de localizar el contador.
- **Entender los puntajes** → `direcciones-ram.md` (parte B) y `py.md`
  (`puntajes.py`, `hi2txt.py`).
- **Instalar o reinstalar en una cabina** → `sh.md` (`instalar.sh`) y
  `ESTRUCTURA.md`.
- **Grabar vídeos de muestra o tu propia partida** → `sh.md` (`videos.sh`,
  `grabar.sh`).
- **El porqué de cada decisión y el historial completo** → `../CLAUDE.md`.

## Nota sobre los nombres

Los scripts y sus variables de entorno (`GA_*`) son la **interfaz que usa la
cabina desplegada**: la `.cfg` del emulador lanza `creditos.lua` por ruta
absoluta, los scripts se cargan entre sí por nombre (`dofile`, `source`) y las
pruebas los invocan por su ruta. Por eso los nombres se cambian con cuidado y de
forma coordinada (repo + configuración desplegada + pruebas + esta documentación),
nunca a la ligera.
