#!/bin/bash
# Corrige la proporcion de las capturas y videos que ya estan descargados.
#
# EL PROBLEMA. Tanto el -aviwrite de MAME como las capturas de arcadeitalia
# guardan el bitmap CRUDO del juego (Pac-Man: 224x288, Q*bert: 240x256), y esos
# no son los pixeles que veia el jugador. El monitor de una recreativa es 4:3
# FISICO: un juego vertical se ve a 3:4 = 0.750 y uno horizontal a 4:3 = 1.333,
# gire lo que gire el bitmap. Guardarlo crudo deja a Q*bert un 25% mas ancho y
# a Kung-Fu Master un 25% mas estrecho, y asi se ven en el frontend.
#
# Dentro del juego MAME ya lo hace bien (keepaspect): esto es solo el arte.
#
# La correccion SIEMPRE agranda un lado, nunca encoge el otro, para no tirar
# detalle del original.
#
# Uso:
#   ./aspecto.sh            corrige lo que haga falta
#   ./aspecto.sh --ver      solo dice que corregiria
#
#   CAPTURAS=/otra/ruta ./aspecto.sh    si las capturas estan en otro sitio
#
# videos.sh ya graba con la proporcion buena; esto es para lo de antes y para
# lo que baje arte.sh, que viene igual de crudo.
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
EMU="${EMU:-groovymame}"
# OJO con el nombre: SNAP a secas ya existe en el entorno cuando algo se lanza
# desde un snap (VS Code la pone a /snap/code/NNN), y "${SNAP:-...}" se la come
# tan tranquilo. El sintoma es mudo: el script no encuentra ningun fichero y
# dice que no hay nada que corregir.
CAPTURAS="${CAPTURAS:-$HOME/.attract/scraper/$EMU/snap}"
VER=""
[ "${1:-}" = "--ver" ] && VER=1

for p in ffmpeg ffprobe; do
	command -v "$p" >/dev/null || { echo "hace falta $p" >&2; exit 1; }
done

# ImageMagick 7 dejo de instalar `convert` e `identify`: trae un solo `magick`
# que hace de los dos. En Arch, Fedora 41+ y Debian 13 ya es asi, y en Ubuntu
# 24.04 todavia es la 6. Se usa el que haya, en vez de suponer uno.
if command -v magick >/dev/null; then
	CONVERTIR=( magick );  IDENTIFICAR=( magick identify )
elif command -v convert >/dev/null; then
	CONVERTIR=( convert ); IDENTIFICAR=( identify )
else
	echo "hace falta ImageMagick (el binario 'magick', o 'convert' en la 6)" >&2
	exit 1
fi
[ -d "$CAPTURAS" ] || { echo "no encuentro $CAPTURAS" >&2; exit 1; }

# La rotacion de cada juego, de un tiron: -listxml por juego cuesta ~1 s y son
# veinte. Sale "juego rotacion" por linea.
declare -A ROT
while read -r j r; do ROT[$j]=$r; done < <(
	cd "$MAME_DIR" && ./mame -listxml 2>/dev/null | python3 -c '
import sys, re
juego = None
for linea in sys.stdin:
    m = re.search(r"<machine name=\"([^\"]+)\"", linea)
    if m: juego = m.group(1); continue
    m = re.search(r"<display[^>]*rotate=\"(\d+)\"", linea)
    if m and juego: print(juego, m.group(1)); juego = None
')

destino() {   # $1=juego $2=ancho $3=alto -> "ANCHOxALTO"
	python3 -c '
import sys
w, h, rot = int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3])
deseada = 0.75 if rot in (90, 270) else 4/3
# Por defecto se agranda el lado que falta, que no tira nada del original.
if w / h > deseada:  w2, h2 = w, round(w / deseada)
else:                w2, h2 = round(h * deseada), h
# Pero con tope: Frogger graba 224x768 (la placa da 3 lineas por linea util) y
# agrandar ahi pedia 576 de ancho, o sea inventar un 2,6x. Pasado 1.5x sale mas
# a cuenta encoger el otro lado.
if max(w2 / w, h2 / h) > 1.5:
    if w / h > deseada:  w2, h2 = round(h * deseada), h
    else:                w2, h2 = w, round(w / deseada)
print(f"{w2 - w2 % 2}x{h2 - h2 % 2}")
' "$2" "$3" "${ROT[$1]:-0}"
}

hechos=0; bien=0; sin_rot=0
for f in "$CAPTURAS"/*.png "$CAPTURAS"/*.mp4; do
	[ -e "$f" ] || continue
	j="$(basename "${f%.*}")"
	if [ -z "${ROT[$j]:-}" ]; then
		echo "  ? $j: MAME no lo conoce, lo dejo como esta"
		sin_rot=$((sin_rot+1)); continue
	fi

	if [ "${f##*.}" = "png" ]; then
		crudo="$("${IDENTIFICAR[@]}" -format '%wx%h' "$f")"
	else
		crudo="$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height \
			-of csv=p=0:s=x "$f")"
	fi
	nuevo="$(destino "$j" "${crudo%x*}" "${crudo#*x}")"

	if [ "$crudo" = "$nuevo" ]; then bien=$((bien+1)); continue; fi

	echo "  $(basename "$f"): $crudo -> $nuevo"
	[ -n "$VER" ] && { hechos=$((hechos+1)); continue; }

	if [ "${f##*.}" = "png" ]; then
		"${CONVERTIR[@]}" "$f" -filter Lanczos -resize "${nuevo}!" "$f.tmp.png" &&
			mv "$f.tmp.png" "$f" && hechos=$((hechos+1))
	else
		# A un temporal y luego mv: si ffmpeg se cae a medias, el video
		# bueno sigue estando.
		ffmpeg -y -loglevel error -i "$f" -vf "scale=${nuevo/x/:}:flags=lanczos" \
			-c:v libx264 -preset slow -crf 26 -pix_fmt yuv420p -an \
			-movflags +faststart "$f.tmp.mp4" 2>/dev/null &&
			[ -s "$f.tmp.mp4" ] && mv "$f.tmp.mp4" "$f" && hechos=$((hechos+1)) ||
			rm -f "$f.tmp.mp4"
	fi
done

echo
if [ -n "$VER" ]; then
	echo "# $hechos por corregir, $bien ya estaban bien, $sin_rot desconocidos"
else
	echo "# $hechos corregidos, $bien ya estaban bien, $sin_rot desconocidos"
fi
