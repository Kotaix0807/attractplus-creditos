#!/bin/bash
# Deja la cabina lista en una maquina nueva.
#
#   git clone <este repo> ~/attractplus
#   git clone <el otro>   ~/groovyarcade-creditos
#   cd ~/attractplus && ./instalar.sh
#
# Lo que hace: crea ~/.attract, copia los plugins, el layout y la configuracion,
# y sustituye las rutas por las de ESTA maquina (en el original estaban puestas
# a mano y no existen en ningun otro sitio).
#
# Lo que NO hace, a proposito:
#   - No compila nada. Te dice que falta y como.
#   - No baja artes ni videos: son 40 MB y se regeneran en 10 minutos con
#     arte.sh y videos.sh, que necesitan solo las roms.
#   - No toca ~/.attract/config/attract.cfg si ya existe: ahi estan tus teclas.
set -u

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESTINO="${DESTINO:-$HOME/.attract}"

# Se pueden fijar por entorno si la deteccion falla:
#   MAME=/usr/bin/groovymame ROMS=/ruta/roms CREDITOS=/ruta ./instalar.sh
CREDITOS="${CREDITOS:-$(cd "$AQUI/../groovyarcade-creditos" 2>/dev/null && pwd || true)}"

rojo()  { printf '\033[31m%s\033[0m\n' "$*"; }
verde() { printf '\033[32m%s\033[0m\n' "$*"; }
aviso() { printf '\033[33m%s\033[0m\n' "$*"; }

echo "== Instalador de la cabina =="
echo

# ---------------------------------------------------------------- comprobaciones
faltan=()
for p in git make g++; do command -v "$p" >/dev/null || faltan+=( "$p" ); done
command -v ffmpeg >/dev/null || aviso "ffmpeg no esta: videos.sh no podra grabar"
command -v curl   >/dev/null || aviso "curl no esta: arte.sh no podra descargar"

if [ ${#faltan[@]} -gt 0 ]; then
	rojo "Faltan herramientas: ${faltan[*]}"
	if command -v pacman >/dev/null; then
		echo "  sudo pacman -S --needed base-devel git"
	elif command -v apt-get >/dev/null; then
		echo "  sudo apt install build-essential git"
	fi
	exit 1
fi

if [ -z "$CREDITOS" ] || [ ! -f "$CREDITOS/creditos.lua" ]; then
	rojo "No encuentro el repo groovyarcade-creditos."
	echo "  Clonalo al lado de este, o pasalo asi:"
	echo "     CREDITOS=/ruta/a/groovyarcade-creditos $0"
	exit 1
fi

# El emulador: primero el compilado aqui, luego el del sistema
if [ -z "${MAME:-}" ]; then
	for c in "$HOME/groovymame_src/mame" /usr/bin/groovymame /usr/bin/mame /usr/games/mame; do
		[ -x "$c" ] && { MAME="$c"; break; }
	done
fi

if [ -z "${MAME:-}" ]; then
	rojo "No encuentro el emulador."
	echo "  Pasalo asi:  MAME=/ruta/al/mame $0"
	exit 1
fi
MAMEDIR="$(dirname "$MAME")"

# Las roms
if [ -z "${ROMS:-}" ]; then
	for c in /usr/share/games/mame/roms "$HOME/roms" /usr/local/share/games/mame/roms; do
		[ -d "$c" ] && { ROMS="$c"; break; }
	done
fi
[ -n "${ROMS:-}" ] || { rojo "No encuentro las roms. Pasalas con ROMS=/ruta $0"; exit 1; }

echo "  frontend:  $AQUI"
echo "  creditos:  $CREDITOS"
echo "  emulador:  $MAME"
echo "  roms:      $ROMS"
echo "  destino:   $DESTINO"
echo

# ---------------------------------------------------------------- instalacion
mkdir -p "$DESTINO"/{config,plugins,emulators,layouts,romlists,scraper}

copiar_si_falta() {   # origen destino
	if [ -e "$2" ]; then
		echo "  = $(basename "$2") ya existe, no lo toco"
	else
		cp "$1" "$2" && echo "  + $(basename "$2")"
	fi
}

respaldar() {
	[ -e "$1" ] && cp "$1" "$1.antes_instalar"
}

echo "Plugins:"
for p in "$AQUI"/config/plugins/{Creditos,Arranque}.nut; do
	cp "$p" "$DESTINO/plugins/" && echo "  + $(basename "$p")"
done

echo "Layout:"
rm -rf "$DESTINO/layouts/Arcade-UMAG"
cp -r "$AQUI/config/layouts/Arcade-UMAG" "$DESTINO/layouts/" && echo "  + Arcade-UMAG"

# Los modulos que usan los layouts (fade, animate...). Sin esto el layout
# revienta con "the index 'FadeArt' does not exist", que no dice nada de que
# el problema sea un modulo que falta.
echo "Modulos:"
mkdir -p "$DESTINO/modules"
cp -r "$AQUI"/config/modules/. "$DESTINO/modules/" && echo "  + $(ls "$DESTINO/modules" | wc -l) modulos"

echo "Configuracion:"
respaldar "$DESTINO/emulators/groovymame.cfg"
sed -e "s|@MAMEDIR@|$MAMEDIR|g" -e "s|@CREDITOS@|$CREDITOS|g" -e "s|@ROMS@|$ROMS|g" \
	"$AQUI/config/cabina/groovymame.cfg" > "$DESTINO/emulators/groovymame.cfg"
echo "  + emulators/groovymame.cfg (rutas de esta maquina)"

respaldar "$DESTINO/config/plugins.cfg"
sed -e "s|@CREDITOS@|$CREDITOS|g" "$AQUI/config/cabina/plugins.cfg" > "$DESTINO/config/plugins.cfg"
echo "  + config/plugins.cfg"

copiar_si_falta "$AQUI/config/cabina/displays.cfg" "$DESTINO/config/displays.cfg"
copiar_si_falta "$AQUI/config/cabina/attract.cfg" "$DESTINO/config/attract.cfg"

echo
verde "Instalado."
echo
echo "Lo que falta, por orden:"
echo
echo "  1. Compilar el frontend:"
echo "       cd $AQUI && make -j\$(nproc)"
echo
if [ ! -x "$AQUI/attractplus" ]; then
	echo "     (todavia no esta compilado)"
	echo
fi
echo "  2. Parche del emulador, opcional (quita los avisos y los mensajes de carga):"
echo "       cd <fuentes de groovymame> && patch -p1 < $AQUI/parches/groovymame-sin-avisos.patch"
echo "       make -j\$(nproc) NOWERROR=1 USE_QTDEBUG=0"
echo
echo "  3. La lista de juegos:"
echo "       cd $AQUI && ./attractplus --build-romlist groovymame"
echo
echo "  4. Artes y videos (no vienen en el repo, se generan aqui):"
echo "       cd $AQUI && ./attractplus --scrape-art groovymame     # marquesinas, capturas, flyers"
echo "       cd $CREDITOS && ./videos.sh                           # videos, unos 10 minutos"
echo
echo "  5. Mapear el boton de moneda en MAME y, si quieres el menu de ajustes"
echo "     de arranque, la tecla en Configure > Plug-ins > Arranque."
