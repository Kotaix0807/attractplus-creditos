#!/bin/bash
# Graba un video de muestra de cada juego, del propio emulador.
#
#   ./videos.sh pacman dkong       # esos juegos
#   ./videos.sh                    # todos los de la romlist
#
# Por que grabarlos en vez de bajarlos: la fuente que AM+ trae incrustada
# (progettosnaps.net/videosnaps/mp4/) devuelve 404 desde hace tiempo, y
# arcadeitalia no sirve videos. Pero las roms y el emulador ya estan aqui.
#
# El video va a  <config>/scraper/<emulador>/snap/<juego>.mp4 , el mismo sitio
# que la captura fija. AM+ prefiere el video cuando existe.
set -u

MAME_DIR="${MAME_DIR:-/home/eloy/groovymame_src}"
ROMPATH="${ROMPATH:-/usr/share/games/mame/roms}"
EMU="${EMU:-groovymame}"
DESTINO="${DESTINO:-$HOME/.attract/scraper/$EMU/snap}"
ROMLIST="${ROMLIST:-$HOME/.attract/romlists/$EMU.txt}"

SALTO="${SALTO:-8}"        # segundos que se descartan del principio (la carga)
DURA="${DURA:-12}"         # segundos que dura el video
CALIDAD="${CALIDAD:-26}"   # crf de x264: mas bajo = mejor y mas grande

command -v ffmpeg >/dev/null || { echo "hace falta ffmpeg" >&2; exit 1; }
[ -x "$MAME_DIR/mame" ] || { echo "no encuentro $MAME_DIR/mame" >&2; exit 1; }

if [ $# -gt 0 ]; then
	JUEGOS=( "$@" )
else
	mapfile -t JUEGOS < <(cut -d';' -f1 "$ROMLIST" | grep -v '^#')
fi

mkdir -p "$DESTINO"
TMP=$(mktemp -d /tmp/videos-mame.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

hechos=0; saltados=0; fallos=0

for j in "${JUEGOS[@]}"; do
	[ -n "$j" ] || continue

	if [ -s "$DESTINO/$j.mp4" ]; then
		echo "  $j: ya tenia video"
		saltados=$((saltados+1))
		continue
	fi

	echo -n "  $j: grabando... "

	# El avi sale sin comprimir (unos 11 MB por segundo), por eso va a un
	# temporal y se borra en cuanto se convierte.
	( cd "$MAME_DIR" && xvfb-run -a ./mame "$j" -rompath "$ROMPATH" \
		-video soft -sound none -noswitchres -window -resolution 640x480 \
		-seconds_to_run $(( SALTO + DURA + 2 )) \
		-aviwrite "$TMP/$j.avi" > /dev/null 2>&1 )

	if [ ! -s "$TMP/$j.avi" ]; then
		echo "no se pudo grabar"
		fallos=$((fallos+1))
		continue
	fi

	echo -n "convirtiendo... "

	# -ss antes que -t: se descarta la carga y se toma el modo de atraccion.
	# -an: sin audio (grabar sonido sin tarjeta no es fiable).
	if ffmpeg -y -loglevel error -i "$TMP/$j.avi" -ss "$SALTO" -t "$DURA" \
		-c:v libx264 -preset slow -crf "$CALIDAD" -pix_fmt yuv420p -an \
		-movflags +faststart "$DESTINO/$j.mp4" 2>/dev/null \
		&& [ -s "$DESTINO/$j.mp4" ]
	then
		echo "$(du -h "$DESTINO/$j.mp4" | cut -f1)"
		hechos=$((hechos+1))
	else
		rm -f "$DESTINO/$j.mp4"
		echo "fallo la conversion"
		fallos=$((fallos+1))
	fi

	rm -f "$TMP/$j.avi"
done

echo
echo "# $hechos grabados, $saltados ya estaban, $fallos fallaron"
echo "# Recarga el layout con F5 para verlos."
