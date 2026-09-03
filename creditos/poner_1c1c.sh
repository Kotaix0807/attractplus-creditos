#!/bin/bash
# Pasada de configuracion: deja los juegos en 1 moneda = 1 credito.
#
#   ./poner_1c1c.sh                 # todas las roms de ROMPATH
#   ./poner_1c1c.sh pacman dkong    # solo esos
#
# Arranca cada juego dos segundos, cambia el DIP de tarifa y sale; MAME guarda
# el cambio en su .cfg. Hay que hacerlo una sola vez por juego: desde entonces
# los creditos del frontend son exactos ya en el primer arranque.
#
# Variables:
#   MAME_DIR   donde esta el ejecutable   (por defecto, el groovymame_src de al lado)
#   ROMPATH    donde estan las roms       (/usr/share/games/mame/roms)
#   CFG_DIR    cfg de MAME a modificar    (el que MAME use por defecto)
#   MAME_EXTRA opciones extra para MAME

set -u

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Donde esta cada cosa. Los repos pueden estar de DOS formas: creditos dentro
# de attractplus (una sola clonacion, que es lo normal) o los dos al lado, como
# estaban antes. Se buscan en los dos sitios en vez de suponer uno.
vecino() {   # $1=marca que tiene dentro  $2..=candidatos
	local marca="$1"; shift
	local c
	for c in "$@"; do
		[ -e "$c/$marca" ] && { ( cd "$c" && pwd ); return 0; }
	done
	return 1
}

MAME_DIR="${MAME_DIR:-$( vecino mame \
	"$AQUI/../../groovymame_src" "$AQUI/../groovymame_src" "$HOME/groovymame_src" )}"
ROMPATH="${ROMPATH:-/usr/share/games/mame/roms}"
MAME_EXTRA="${MAME_EXTRA:-}"

if [ ! -x "$MAME_DIR/mame" ]; then
	echo "no encuentro $MAME_DIR/mame" >&2
	exit 1
fi

juegos=( "$@" )
if [ ${#juegos[@]} -eq 0 ]; then
	# Los nombres de set son los nombres de fichero sin extension
	mapfile -t juegos < <(find "$ROMPATH" -maxdepth 1 -type f \
		\( -name '*.zip' -o -name '*.7z' \) -printf '%f\n' | sed 's/\.[^.]*$//' | sort)
fi

if [ ${#juegos[@]} -eq 0 ]; then
	echo "no hay roms en $ROMPATH" >&2
	exit 1
fi

# Sin DISPLAY hace falta un X de mentira; en la cabina ya hay pantalla
LANZA=()
if [ -z "${DISPLAY:-}" ] && command -v xvfb-run >/dev/null; then
	LANZA=( xvfb-run -a )
fi

OPC_CFG=()
[ -n "${CFG_DIR:-}" ] && OPC_CFG=( -cfg_directory "$CFG_DIR" )

echo "# ${#juegos[@]} juegos, cfg en ${CFG_DIR:-el de MAME por defecto}"
cambiados=0; ya=0; otros=0; fallos=0

for j in "${juegos[@]}"; do
	salida=$( cd "$MAME_DIR" && "${LANZA[@]}" ./mame "$j" \
		-rompath "$ROMPATH" "${OPC_CFG[@]}" $MAME_EXTRA \
		-video none -sound none -nothrottle -noswitchres -seconds_to_run 2 \
		-autoboot_script "$AQUI/poner_1c1c.lua" -autoboot_delay 1 2>&1 )

	linea=$( echo "$salida" | grep '^1C1C ' | head -1 )
	if [ -z "$linea" ]; then
		echo "ERROR juego=$j    $(echo "$salida" | grep -iE 'error|not found' | head -1)"
		fallos=$((fallos+1))
		continue
	fi

	echo "$linea"
	case "$linea" in
		*estado=cambiado*)  cambiados=$((cambiados+1)) ;;
		*estado=ya-estaba*) ya=$((ya+1)) ;;
		*)                  otros=$((otros+1)) ;;
	esac
done

echo "# cambiados=$cambiados ya-estaban=$ya sin-cambio=$otros fallos=$fallos"
