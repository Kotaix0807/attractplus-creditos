#!/bin/bash
# Graba un video de muestra de cada juego, del propio emulador.
#
#   ./videos.sh pacman dkong       # esos juegos
#   ./videos.sh                    # todos los de la romlist
#   ./videos.sh --tira simpsons    # tira de fotogramas para MEDIR el salto
#
#   FORZAR=1 ./videos.sh simpsons  # rehacer uno que ya tenia video
#   SALTO=20 FORZAR=1 ./videos.sh mappy
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

# Cuanto hay que descartar de cada juego, MEDIDO con --tira. El defecto de 8 s
# vale para las placas de los 80 que arrancan en un suspiro, pero no para las
# que hacen un test largo ni para las que tardan en llegar al juego de verdad.
declare -A SALTOS=(
	[simpsons]=16    # 4 s "RAM ROM CHECK", 10 s patron de test, atraccion a los 14
	[nrallyx]=28     # test hasta los 12, luego la lista de personajes; juego a los 28
	[mappy]=38       # titulo y personajes hasta los 35; la demo empieza a los 38
)

SALTO="${SALTO:-8}"        # segundos que se descartan del principio (la carga)
DURA="${DURA:-12}"         # segundos que dura el video
CALIDAD="${CALIDAD:-26}"   # crf de x264: mas bajo = mejor y mas grande

command -v ffmpeg >/dev/null || { echo "hace falta ffmpeg" >&2; exit 1; }
[ -x "$MAME_DIR/mame" ] || { echo "no encuentro $MAME_DIR/mame" >&2; exit 1; }

# --tira <juego>: graba un minuto y saca una tira de fotogramas, para VER en
# que segundo empieza lo que quieres grabar en vez de adivinarlo.
if [ "${1:-}" = "--tira" ]; then
	[ $# -eq 2 ] || { echo "uso: $0 --tira <juego>" >&2; exit 1; }
	j="$2"
	command -v montage >/dev/null || { echo "hace falta imagemagick" >&2; exit 1; }

	T=$(mktemp -d /tmp/tira-mame.XXXXXX)
	echo "grabando un minuto de $j..."
	( cd "$MAME_DIR" && xvfb-run -a ./mame "$j" -rompath "$ROMPATH" \
		-video soft -sound none -noswitchres -window -resolution 640x480 \
		-seconds_to_run 62 -aviwrite "$T/v.avi" > /dev/null 2>&1 )

	ARCHIVOS=()
	for t in 4 8 12 16 20 26 32 38 44 50 56 60; do
		ffmpeg -y -loglevel error -ss $t -i "$T/v.avi" -vframes 1 \
			-vf scale=150:-1 "$T/$t.png" 2>/dev/null && ARCHIVOS+=( "$T/$t.png" )
	done

	SALIDA="${SALIDA:-$PWD/tira-$j.png}"
	montage "${ARCHIVOS[@]}" -tile 4x3 -geometry +4+4 -background gray \
		-label '%t s' "$SALIDA"
	rm -rf "$T"

	echo "tira en $SALIDA"
	echo "Mira en que segundo empieza lo que quieres y ponlo en la tabla SALTOS,"
	echo "o lanzalo asi:  SALTO=<segundos> FORZAR=1 $0 $j"
	exit 0
fi

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

	if [ -s "$DESTINO/$j.mp4" ] && [ "${FORZAR:-0}" != "1" ]; then
		echo "  $j: ya tenia video (FORZAR=1 para rehacerlo)"
		saltados=$((saltados+1))
		continue
	fi

	# El salto del juego manda sobre el general. Asi cambiar SALTO en la linea
	# de comandos sigue funcionando para un juego suelto.
	salto=${SALTO_ESPECIFICO:-${SALTOS[$j]:-$SALTO}}
	[ -n "${SALTO_FORZADO:-}" ] && salto=$SALTO

	echo -n "  $j: grabando (salto ${salto}s)... "

	# El avi sale sin comprimir (unos 11 MB por segundo), por eso va a un
	# temporal y se borra en cuanto se convierte.
	( cd "$MAME_DIR" && xvfb-run -a ./mame "$j" -rompath "$ROMPATH" \
		-video soft -sound none -noswitchres -window -resolution 640x480 \
		-seconds_to_run $(( salto + DURA + 2 )) \
		-aviwrite "$TMP/$j.avi" > /dev/null 2>&1 )

	if [ ! -s "$TMP/$j.avi" ]; then
		echo "no se pudo grabar"
		fallos=$((fallos+1))
		continue
	fi

	echo -n "convirtiendo... "

	# -ss antes que -t: se descarta la carga y se toma el modo de atraccion.
	# -an: sin audio (grabar sonido sin tarjeta no es fiable).
	if ffmpeg -y -loglevel error -i "$TMP/$j.avi" -ss "$salto" -t "$DURA" \
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
