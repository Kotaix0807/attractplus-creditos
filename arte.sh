#!/bin/bash
# Baja los artes de uno o varios juegos y los deja donde AM+ los busca.
#
#   ./arte.sh pacman dkong          # esos juegos
#   ./arte.sh bublbobl              # el PADRE, si tu rom es un clon
#
# Los ficheros van a  <config>/scraper/<emulador>/<tipo>/<nombre>.png , que es
# donde AM+ mira solo, sin configurar ninguna ruta de artwork.
#
# Si tu rom es un clon o un hack (bbredux), guarda el arte con el nombre del
# juego PADRE: AM+ prueba Name, luego AltRomname y luego CloneOf.
set -u

EMU="${EMU:-groovymame}"
DESTINO="${DESTINO:-$HOME/.attract/scraper/$EMU}"
FUENTE="http://adb.arcadeitalia.net/media/mame.current"

[ $# -gt 0 ] || { echo "uso: $0 <juego> [juego...]" >&2; exit 1; }

# tipo remoto : carpeta local
TIPOS=( "marquees:marquee" "ingames:snap" "flyers:flyer" "decals:wheel" )

for juego in "$@"; do
	echo "$juego:"
	for par in "${TIPOS[@]}"; do
		remoto=${par%%:*}
		local_=${par##*:}
		mkdir -p "$DESTINO/$local_"
		fichero="$DESTINO/$local_/$juego.png"

		if [ -s "$fichero" ]; then
			echo "  $local_: ya estaba"
			continue
		fi

		# -L porque el sitio redirige http -> https
		code=$(curl -sL -m 40 -o "$fichero" -w "%{http_code}" "$FUENTE/$remoto/$juego.png")

		if [ "$code" = "200" ] && [ -s "$fichero" ]; then
			echo "  $local_: $(stat -c%s "$fichero") bytes"
		else
			rm -f "$fichero"
			echo "  $local_: no hay (HTTP $code)"
		fi
	done
done

echo
echo "# Recarga el layout con F5 para verlo, o reinicia AM+."
