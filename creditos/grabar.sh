#!/bin/bash
# Graba TU partida, con sonido, y la deja como video del juego en el frontend.
#
#   ./grabar.sh mwalk
#
#   1. se abre el juego y juegas normal;
#   2. cuando llegas a un momento que vale la pena, pulsas la TECLA y empieza a
#      grabar (arriba a la derecha aparece "* REC 3s");
#   3. la misma tecla corta la toma. Puedes hacer las tomas que quieras;
#   4. sales del emulador y aqui se elige una y se convierte.
#
# La tecla por defecto es Pausa/Inter (KEYCODE_PAUSE). Se cambia con TECLA=:
#
#   TECLA=KEYCODE_MENU ./grabar.sh pacman
#
# Es un guion APARTE de videos.sh a proposito, y solo corre cuando lo pides:
# videos.sh graba en serie, sin nadie delante, bajo Xvfb y sin sonido. Esto es
# lo contrario -- una persona jugando en la cabina, con audio -- y mezclarlos
# habria dejado a los dos peor.
#
# Lo que SI comparte es el tratamiento del video (video_comun.sh): correccion
# de proporcion 4:3 del mueble y ampliado antes de comprimir. Asi la partida
# grabada se ve igual que el resto en el frontend y no canta.
set -u

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$AQUI/video_comun.sh"

EMU="${EMU:-groovymame}"
DESTINO="${DESTINO:-$HOME/.attract/scraper/$EMU/snap}"
CALIDAD="${CALIDAD:-20}"
AMPLIAR="${AMPLIAR:-1}"
TECLA="${TECLA:-KEYCODE_PAUSE}"
CREDITOS_LUA="${CREDITOS_LUA:-$AQUI/creditos.lua}"

# CON sonido, que es medio encargo. El AVI de MAME lo lleva dentro: el gestor
# de sonido alimenta la grabacion por su cuenta mientras dura
# (video_manager::add_sound_to_recording), asi que no hay que capturar audio
# aparte ni sincronizar nada despues.
AUDIO_FFMPEG="${AUDIO_FFMPEG:--c:a aac -b:a 160k}"

case "${1:-}" in
	''|-h|--help|--ayuda) sed -n '2,22p' "$0" | sed 's/^# \?//'; exit 0 ;;
esac
[ $# -eq 1 ] || { echo "uso: $0 <juego>   (uno cada vez)" >&2; exit 1; }
JUEGO="$1"

# Sin sesion grafica no hay nada que jugar, y MAME aborta con un mensaje que no
# lo dice. Vale mas decirlo aqui.
[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] || {
	echo "no hay sesion grafica (DISPLAY vacio): esto se lanza DELANTE de la" >&2
	echo "cabina, no por ssh. Por ssh solo funciona con  ssh -X ." >&2
	exit 1; }

TMP=$(mktemp -d /tmp/grabar-mame.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

echo "# emulador: $MAME_BIN"
echo "# juego:    $JUEGO"
echo "# destino:  $DESTINO/$JUEGO.mp4"
echo
echo "  Pulsa  $TECLA  para EMPEZAR a grabar y otra vez para PARAR."
echo "  Mientras graba se ve '* REC' arriba a la derecha (no sale en el video)."
echo "  Cierra el emulador cuando termines."
echo

# Se lanza como en la cabina: creditos.lua de autoboot, con los ajustes de
# arranque.dat. Asi la moneda, el arranque tapado y el aviso de salida se
# comportan igual que jugando de verdad -- que es justo lo que se esta grabando.
#
# Y NO se tocan los ajustes de video ni de sonido: los pone mame.ini, que es lo
# que el jugador tiene delante. videos.sh si los forza, pero porque graba a
# ciegas bajo Xvfb.
( cd "$MAME_DIR" && env ${GA_VERBOSO:+GA_VERBOSO=1} \
	GA_GRABAR_TECLA="$TECLA" GA_GRABAR_ARCHIVO="$TMP/toma-" \
	"$MAME_BIN" "$JUEGO" -rompath "$ROMPATH" \
	-autoboot_script "$CREDITOS_LUA" -autoboot_delay 0 ) || true

mapfile -t TOMAS < <( ls -1 "$TMP"/toma-*.avi 2>/dev/null | sort -V )

if [ "${#TOMAS[@]}" -eq 0 ]; then
	echo "No hay ninguna toma: no llegaste a pulsar $TECLA, o el emulador no la vio."
	echo "Prueba otra tecla:  TECLA=KEYCODE_MENU $0 $JUEGO"
	exit 1
fi

duracion() { ffprobe -v error -show_entries format=duration -of csv=p=0 "$1" 2>/dev/null; }

if [ "${#TOMAS[@]}" -eq 1 ]; then
	ELEGIDA="${TOMAS[0]}"
else
	echo "Hay ${#TOMAS[@]} tomas:"
	i=1; for t in "${TOMAS[@]}"; do
		printf '  %d) %5.1f s  %s\n' "$i" "$( duracion "$t" )" "$( du -h "$t" | cut -f1 )"
		i=$((i+1))
	done
	if [ -t 0 ]; then
		read -rp "cual me quedo? [1-${#TOMAS[@]}] " n
		[[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le "${#TOMAS[@]}" ] || {
			echo "no es un numero de la lista; no toco nada" >&2; exit 1; }
		ELEGIDA="${TOMAS[$((n-1))]}"
	else
		# Sin nadie a quien preguntar, la mas larga es la apuesta menos mala.
		ELEGIDA="$( for t in "${TOMAS[@]}"; do echo "$( duracion "$t" ) $t"; done |
			sort -rn | head -1 | cut -d' ' -f2- )"
		echo "(sin terminal para preguntar: me quedo con la mas larga)"
	fi
fi

echo
printf 'convirtiendo %s (%.1f s)... ' "$( basename "$ELEGIDA" )" "$( duracion "$ELEGIDA" )"

# El video que se reemplaza se guarda. Los automaticos se pueden rehacer con
# videos.sh en un minuto, pero una partida grabada a mano NO: si esto pisara la
# toma buena de la semana pasada no habria forma de recuperarla.
mkdir -p "$DESTINO"
if ya="$( video_existente "$JUEGO" )"; then
	mkdir -p "$DESTINO/respaldo"
	cp -f "$ya" "$DESTINO/respaldo/$( basename "$ya" ).$( date +%Y%m%d-%H%M%S )"
fi

# salto 0 y dura vacia: la toma dura lo que quisiste, no una ventana fijada.
if convertir_a_mp4 "$ELEGIDA" "$JUEGO" 0 ""; then
	echo "$( du -h "$DESTINO/$JUEGO.mp4" | cut -f1 )"
	echo
	echo "$DESTINO/$JUEGO.mp4"
	[ -d "$DESTINO/respaldo" ] && echo "(el video anterior esta en $DESTINO/respaldo/)"
	echo "Recarga el layout con F5 para verlo."
else
	echo "fallo la conversion (se deja el video que hubiera)"
	exit 1
fi
