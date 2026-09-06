#!/bin/bash
# Graba un video de muestra de cada juego, del propio emulador.
#
#   ./videos.sh pacman dkong       # esos juegos
#   ./videos.sh                    # todos los de la romlist
#   ./videos.sh --tira simpsons    # tira de fotogramas para MEDIR el salto a ojo
#   ./videos.sh --medir            # mide el salto SOLO y lo escribe en arranque.dat
#
#   FORZAR=1 ./videos.sh simpsons  # rehacer uno (borra el video anterior)
#
# El ajuste de cada juego NO esta en este script: esta en arranque.dat, al lado,
# junto a los de la carga. Dos claves, las dos opcionales:
#
#   video=N       segundo en el que empieza lo que quieres grabar
#   videodura=N   cuanto dura el video de ese juego
#
#   contra segundos=7 velocidad=0 video=16
#
# Sin 'video=' se usa 'segundos=' (cuando la placa termina de arrancar) como
# suelo, y si tampoco lo hay, 8 s. creditos.lua ignora las dos claves nuevas.
#
# Por que grabarlos en vez de bajarlos: la fuente que AM+ trae incrustada
# (progettosnaps.net/videosnaps/mp4/) devuelve 404 desde hace tiempo, y
# arcadeitalia no sirve videos. Pero las roms y el emulador ya estan aqui.
#
# El video va a  <config>/scraper/<emulador>/snap/<juego>.mp4 , el mismo sitio
# que la captura fija. AM+ prefiere el video cuando existe.
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

# En una maquina de desarrollo el emulador esta en el arbol de fuentes
# (groovymame_src/mame). En una cabina GroovyArcade NO hay tal arbol: el binario
# esta instalado, y ademas puede haber dos (el de la distro y el nuestro). Se
# prueban todos los sitios en vez de suponer uno, y MAME= manda sobre todos.
#
#   MAME=/ruta/al/mame ./videos.sh
buscar_mame() {
	local c fuentes
	fuentes="$( vecino mame "$AQUI/../../groovymame_src" \
		"$AQUI/../groovymame_src" "$HOME/groovymame_src" 2>/dev/null )"
	for c in "${MAME:-}" \
		"$HOME/.local/share/groovymame-cabina/mame" \
		${fuentes:+"$fuentes/mame"} \
		"$( command -v groovymame 2>/dev/null )" \
		"$( command -v mame 2>/dev/null )"
	do
		[ -n "$c" ] && [ -x "$c" ] && { echo "$c"; return 0; }
	done
	return 1
}

MAME_BIN="$( buscar_mame )" || {
	echo "no encuentro el emulador. Lo busco, por este orden, en:" >&2
	echo "  \$MAME (la variable de entorno)" >&2
	echo "  ~/.local/share/groovymame-cabina/mame" >&2
	echo "  ../../groovymame_src/mame, ../groovymame_src/mame, ~/groovymame_src/mame" >&2
	echo "  groovymame o mame en el PATH" >&2
	echo >&2
	echo "Lanzalo asi:  MAME=/ruta/al/mame $0 ..." >&2
	exit 1
}
# Se entra en su directorio para lanzarlo: nuestra compilacion lleva al lado su
# bgfx y sus plugins, igual que hace el frontend con 'workdir'.
MAME_DIR="$( cd "$( dirname "$MAME_BIN" )" && pwd )"

# Las rutas NO se suponen: se le preguntan al propio emulador, que es quien sabe
# cual de sus mame.ini manda. En esta maquina el rompath es
# /usr/share/games/mame/roms y en la cabina ~/shared/roms/mame. La cuenta esta
# en comun.sh, que es de donde la cogen tambien los demas scripts.
. "$AQUI/comun.sh"
ROMPATH="$( rompath_de "$MAME_BIN" )"
EMU="${EMU:-groovymame}"
DESTINO="${DESTINO:-$HOME/.attract/scraper/$EMU/snap}"
ROMLIST="${ROMLIST:-$HOME/.attract/romlists/$EMU.txt}"

SALTO_DE_ORDENES="${SALTO:-}"   # si el usuario puso SALTO=, manda sobre todo
DURA_DE_ORDENES="${DURA:-}"
SALTO="${SALTO:-8}"        # segundos que se descartan del principio (la carga)
DURA="${DURA:-12}"         # segundos que dura el video
CALIDAD="${CALIDAD:-20}"   # crf de x264: mas bajo = mejor y mas grande
AMPLIAR="${AMPLIAR:-1}"    # 0 para guardar al tamano crudo del juego

# --- todo el ajuste por juego vive en arranque.dat -------------------------
#
# Antes habia aqui una tabla SALTOS dentro del script, y eso obligaba a tocar
# el codigo para afinar un juego. Ahora los dos numeros que necesita el video
# son claves de arranque.dat, al lado de las de la carga:
#
#   video=N       segundo en el que empieza lo que quieres grabar
#   videodura=N   cuanto dura el video de ese juego (opcional)
#
#   contra segundos=7 velocidad=0 video=16
#
# creditos.lua las ignora: su parser guarda cualquier clave y solo consulta las
# suyas (comprobado ejecutandolo). Asi un solo fichero describe cada juego.
#
# Si no hay 'video=', se usa 'segundos=' -- arranque.dat ya sabe cuanto tarda
# en arrancar cada placa, y es exactamente el numero que hay que descartar.
#
# OJO: se toma el DATO, no se ejecuta creditos.lua. Ese script tapa el arranque
# pintando la pantalla de NEGRO, y ese negro entraria tal cual en el video.
#
# Dos cuidados con 'segundos=', y los dos importan:
#
#   1. Solo se mira la linea PROPIA del juego, nunca la de 'defecto'. La de
#      defecto vale 5 s, que es MENOS que el salto general de 8: usarla haria
#      que los juegos sin linea propia empezaran el video antes que antes.
#   2. Es un SUELO, no el valor final. arranque.dat dice cuando la placa esta
#      lista; la demo llega despues. Contra arranca a los 7 y su demo empieza a
#      los 16. Por eso existe 'video=', que si es el valor final.
#
# Y 'segundos=0' no significa "empieza ya", significa "a este juego no se le
# tapa el arranque" (mwalk, que apenas se puede acelerar). Para el video no
# sirve, y se cae al valor por defecto.
AJUSTES="${AJUSTES:-$AQUI/arranque.dat}"

clave_de_arranque() {   # $1=juego  $2=clave -> valor, o nada
	[ -f "$AJUSTES" ] || return 1
	local linea v
	linea="$( grep -iE "^$1[[:space:]]" "$AJUSTES" 2>/dev/null | head -1 )"
	[ -n "$linea" ] || return 1
	v="$( printf '%s' "$linea" | grep -oE "(^|[[:space:]])$2=[0-9]+" |
	      head -1 | cut -d= -f2 )"
	[ -n "$v" ] || return 1
	printf '%s' "$v"
}

command -v ffmpeg >/dev/null || { echo "hace falta ffmpeg" >&2; exit 1; }

# --- la proporcion de verdad de cada juego ---------------------------------
#
# MAME graba con -aviwrite el bitmap CRUDO del juego (Pac-Man: 224x288), y esos
# no son los pixeles que veia el jugador. El monitor de una recreativa es 4:3
# fisico, asi que un juego vertical se ve a 3:4 = 0.750 y uno horizontal a
# 1.333, gire lo que gire el bitmap. Guardarlo crudo deja a Q*bert un 25% mas
# ancho de lo que debe y a Kung-Fu Master un 25% mas estrecho.
#
# La correccion SIEMPRE agranda un lado, nunca encoge el otro: asi no se tira
# detalle de la imagen original.
#
# Devuelve "ANCHOxALTO" ya redondeado a par (lo exige yuv420p).
proporcion() {   # $1=juego  $2=ancho crudo  $3=alto crudo
	local rot
	rot=$( cd "$MAME_DIR" && "$MAME_BIN" -listxml "$1" 2>/dev/null |
	       sed -n 's/.*<display[^>]*rotate="\([0-9]*\)".*/\1/p' | head -1 )
	python3 -c '
import sys
juego, w, h, rot = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4] or 0)
deseada = 0.75 if rot in (90, 270) else 4/3
if w / h > deseada:          # demasiado ancho: se estira a lo alto
    w2, h2 = w, round(w / deseada)
else:                        # demasiado estrecho: se estira a lo ancho
    w2, h2 = round(h * deseada), h
# Con tope: Frogger graba 224x768 y agrandar pedia un 2,6x de ancho inventado.
if max(w2 / w, h2 / h) > 1.5:
    if w / h > deseada:  w2, h2 = round(h * deseada), h
    else:                w2, h2 = w, round(w / deseada)
print(f"{w2 - w2 % 2}x{h2 - h2 % 2}")
' "$1" "$2" "$3" "${rot:-0}"
}
# AM+ prefiere el video a la imagen fija, y acepta varias extensiones. Si de
# una grabacion anterior quedara un .avi o un .mkv, seguiria mandando sobre el
# .mp4 nuevo y pareceria que regrabar no sirve de nada. Por eso al rehacer un
# juego se borra TODO lo que sea video suyo, no solo el .mp4.
#
# La imagen fija (.png) NO se toca: es el respaldo cuando no hay video.
EXT_VIDEO="mp4 avi mkv mpg mpeg mov webm m4v wmv flv ogv"

video_existente() {   # $1=juego -> ruta del primero que encuentre, o nada
	local e
	for e in $EXT_VIDEO; do
		[ -s "$DESTINO/$1.$e" ] && { printf '%s' "$DESTINO/$1.$e"; return 0; }
	done
	return 1
}

borrar_videos() {   # $1=juego
	local e n=0
	for e in $EXT_VIDEO; do
		[ -e "$DESTINO/$1.$e" ] && { rm -f "$DESTINO/$1.$e" && n=$((n+1)); }
	done
	[ "$n" -gt 0 ] && printf '(borrado el anterior) '
	return 0
}

# Convierte un AVI crudo de MAME a un mp4 listo para el frontend, cortando
# desde 'salto' durante 'dura' segundos. Lo usan los DOS modos -- la grabacion
# normal y --medir --, para que el pipeline de escalado y calidad sea el mismo
# en ambos y no se dupliquen las mismas 20 lineas con dos juegos de trampas.
#   $1=avi de entrada  $2=juego  $3=salto (s)  $4=dura (s)
# Deja el mp4 en $DESTINO/$2.mp4. Devuelve 0 si lo consiguio.
convertir_a_mp4() {
	local avi="$1" j="$2" salto="$3" dura="$4"
	local crudo destino_px amp entero final

	# -ss antes que -t: se descarta la carga y se toma el modo de atraccion.
	# -an: sin audio (grabar sonido sin tarjeta no es fiable).
	crudo=$( ffprobe -v error -select_streams v:0 \
		-show_entries stream=width,height -of csv=p=0:s=x "$avi" )
	[ -n "$crudo" ] || return 1
	destino_px=$( proporcion "$j" "${crudo%x*}" "${crudo#*x}" )

	# --- por que se amplia antes de codificar ---------------------------
	#
	# El bitmap crudo es diminuto (Pac-Man 224x288) y AM+ lo estira hasta el
	# hueco del layout, que en esta cabina son unos 700 px. Ampliar por
	# interpolacion un video de 224 px deja los pixeles blandos, y encima el
	# h264 a ese tamano gastaba 33 kbps: bloques por todas partes.
	#
	# Se amplia AQUI, y en dos pasos que no son intercambiables:
	#   1. un multiplo ENTERO con 'neighbor', que duplica pixeles exactos y
	#      mantiene el filo del arte original;
	#   2. la correccion de proporcion con 'lanczos', que es la parte no
	#      entera, ya sobre una imagen grande.
	# Hacerlo al reves (proporcion primero) reparte mal las filas y se ve
	# irregular.
	amp=1
	if [ "$AMPLIAR" != "0" ]; then
		amp=$(( 700 / ${crudo#*x} + 1 ))
		[ "$amp" -lt 1 ] && amp=1
		[ "$amp" -gt 4 ] && amp=4
	fi
	entero="$(( ${crudo%x*} * amp ))x$(( ${crudo#*x} * amp ))"
	final="$(( ${destino_px%x*} * amp ))x$(( ${destino_px#*x} * amp ))"
	final="$(( ${final%x*} - ${final%x*} % 2 ))x$(( ${final#*x} - ${final#*x} % 2 ))"
	printf '(%s -> %s) ' "$crudo" "$final" >&2

	# Se convierte a un temporal y solo entonces se sustituye el que hubiera.
	# Asi el frontend nunca se encuentra un mp4 a medio escribir, y si la
	# conversion falla el video viejo sigue en su sitio.
	if ffmpeg -y -loglevel error -i "$avi" -ss "$salto" -t "$dura" \
		-vf "scale=${entero/x/:}:flags=neighbor,scale=${final/x/:}:flags=lanczos" \
		-c:v libx264 -preset slow -crf "$CALIDAD" -pix_fmt yuv420p -an \
		-movflags +faststart "$avi.mp4" 2>/dev/null \
		&& [ -s "$avi.mp4" ]
	then
		borrar_videos "$j"
		mv -f "$avi.mp4" "$DESTINO/$j.mp4"
		return 0
	fi
	rm -f "$avi.mp4"
	return 1
}

echo "# emulador: $MAME_BIN"
echo "# roms:     $ROMPATH"
echo "# destino:  $DESTINO"

case "${1:-}" in
	-h|--help|--ayuda)
		sed -n '2,16p' "$0" | sed 's/^# \?//'
		exit 0 ;;
	--*)
		case "$1" in
			--tira|--medir) ;;
			*) echo "opcion desconocida: $1 (prueba --ayuda)" >&2; exit 1 ;;
		esac ;;
esac

# --tira <juego>: graba un minuto y saca una tira de fotogramas, para VER en
# que segundo empieza lo que quieres grabar en vez de adivinarlo.
if [ "${1:-}" = "--tira" ]; then
	[ $# -eq 2 ] || { echo "uso: $0 --tira <juego>" >&2; exit 1; }
	j="$2"
	# ImageMagick 7 no instala 'montage' ni 'convert' sueltos: trae un solo
	# 'magick' que hace de todos. En Ubuntu 24.04 aun es la 6.
	if command -v magick >/dev/null;   then MONTAR=( magick montage )
	elif command -v montage >/dev/null; then MONTAR=( montage )
	else echo "hace falta imagemagick" >&2; exit 1; fi

	T=$(mktemp -d /tmp/tira-mame.XXXXXX)
	echo "grabando un minuto de $j..."
	( cd "$MAME_DIR" && xvfb-run -a "$MAME_BIN" "$j" -rompath "$ROMPATH" \
		-video soft -sound none -noswitchres -window -resolution 640x480 \
		-seconds_to_run 62 -nothrottle -aviwrite "$T/v.avi" > "$T/mame.log" 2>&1 )
	[ -s "$T/v.avi" ] || {
		echo "no se pudo grabar $j:" >&2
		grep -iE "not found|missing|fatal|error" "$T/mame.log" | head -3 >&2
		exit 1
	}

	ARCHIVOS=(); SEGUNDOS=()
	for t in 4 8 12 16 20 26 32 38 44 50 56 60; do
		ffmpeg -y -loglevel error -ss $t -i "$T/v.avi" -vframes 1 \
			-vf scale=150:-1 "$T/$t.png" 2>/dev/null &&
			{ ARCHIVOS+=( "$T/$t.png" ); SEGUNDOS+=( "$t" ); }
	done

	SALIDA="${SALIDA:-$PWD/tira-$j.png}"
	# montage rotula con -label, pero necesita una fuente y en GroovyArcade no
	# hay ninguna configurada: suelta "unable to read font (null)" y la tira
	# sale SIN los segundos, que es justo para lo que sirve. Se le da el
	# fichero de una fuente si el sistema sabe cual, y pase lo que pase la
	# correspondencia se imprime tambien por pantalla.
	FUENTE="$( fc-match -f '%{file}' sans 2>/dev/null )"
	if [ -n "$FUENTE" ] && [ -f "$FUENTE" ]; then
		"${MONTAR[@]}" "${ARCHIVOS[@]}" -tile 4x3 -geometry +4+4 -background gray \
			-font "$FUENTE" -pointsize 14 -label '%t s' "$SALIDA" 2>/dev/null
	fi
	[ -s "$SALIDA" ] || "${MONTAR[@]}" "${ARCHIVOS[@]}" -tile 4x3 -geometry +4+4 \
		-background gray "$SALIDA"
	rm -rf "$T"

	echo "tira en $SALIDA"
	echo -n "orden de los fotogramas (4 por fila), en segundos:"
	for i in "${!SEGUNDOS[@]}"; do
		[ $(( i % 4 )) -eq 0 ] && printf '\n   '
		printf '%4s' "${SEGUNDOS[$i]}"
	done
	echo
	echo "Mira en que segundo empieza lo que quieres y apuntalo en $AJUSTES,"
	echo "en la linea de $j, como  video=<segundos>  (creditos.lua la ignora)."
	echo "Para probarlo sin tocar el fichero:  SALTO=<segundos> FORZAR=1 $0 $j"
	exit 0
fi

# --medir [juegos...]: mide SOLO el salto y lo escribe en arranque.dat.
#
# Por que hace falta: de los juegos instalados, la gran mayoria no tiene linea
# propia en arranque.dat, asi que caian en el salto ciego de 8 s y sus videos
# empezaban EN LA PANTALLA DE TEST de la placa. Ese era el fallo.
#
# Y no se arregla tirando de 'segundos=', aunque lo parezca: esa clave dice
# cuando la placa acepta monedas, no cuando empieza algo que merezca la pena
# grabar. Contra esta lista a los 7 y su demo empieza a los 16. La linea
# 'defecto' es peor todavia: son 5 s, menos que los 8 de ahora.
#
# Lo que se hace es medirlo de verdad, con medir_video.py, y DEJARLO ESCRITO en
# arranque.dat como 'video=N'. Asi la proxima grabacion ya no mide nada: sale
# de arranque.dat, que es donde tiene que estar el ajuste de cada juego.
if [ "${1:-}" = "--medir" ]; then
	shift
	VENTANA="${VENTANA:-60}"     # segundos emulados que se graban para medir
	HOJA="${HOJA:-$PWD/medidas.png}"
	# Por defecto, de la MISMA grabacion larga que sirve para medir se saca ya
	# el mp4: un solo arranque del emulador por juego en vez de dos, que en la
	# cabina (i3 lento) es la mitad de tiempo. SOLO_MEDIR=1 se queda en medir y
	# escribir arranque.dat, sin grabar el video.
	GRABAR=1; [ "${SOLO_MEDIR:-0}" = 1 ] && GRABAR=0

	if [ $# -gt 0 ]; then
		JUEGOS=( "$@" )
	else
		mapfile -t JUEGOS < <(cut -d';' -f1 "$ROMLIST" | grep -v '^#')
	fi

	T=$(mktemp -d /tmp/medir-mame.XXXXXX)
	trap 'rm -rf "$T"' EXIT
	medidos=0; saltados=0; fallos=0
	MUESTRAS=(); ETIQUETAS=()

	echo "# midiendo ${#JUEGOS[@]} juego(s), ventana de ${VENTANA}s emulados"
	for j in "${JUEGOS[@]}"; do
		[ -n "$j" ] || continue
		if [ -z "${FORZAR:-}" ] && ya=$( clave_de_arranque "$j" video ); then
			echo "  $j: ya tenia video=$ya (FORZAR=1 para volver a medirlo)"
			saltados=$((saltados+1)); continue
		fi

		echo -n "  $j: grabando... "
		( cd "$MAME_DIR" && xvfb-run -a "$MAME_BIN" "$j" -rompath "$ROMPATH" \
			-video soft -sound none -noswitchres -window -resolution 640x480 \
			-seconds_to_run "$VENTANA" -nothrottle \
			-aviwrite "$T/$j.avi" > "$T/$j.log" 2>&1 )
		if [ ! -s "$T/$j.avi" ]; then
			echo "no se pudo grabar"
			grep -iE "not found|missing|fatal|required|unknown system" "$T/$j.log" |
				head -2 | sed 's/^/      /'
			fallos=$((fallos+1)); rm -f "$T/$j.avi" "$T/$j.log"; continue
		fi

		echo -n "midiendo... "
		punto=$( "$AQUI/medir_video.py" "$T/$j.avi" "$DURA" 2>"$T/$j.med" )
		detalle=$( sed 's/^# //' "$T/$j.med" 2>/dev/null | head -1 )
		if [ -z "$punto" ]; then
			echo "no pude medirlo"; fallos=$((fallos+1))
			rm -f "$T/$j.avi" "$T/$j.log" "$T/$j.med"; continue
		fi

		# El fotograma elegido, para poder mirarlo despues: una eleccion no
		# esta confirmada hasta que se ha visto, igual que en creditos.dat.
		if ffmpeg -v error -y -ss "$punto" -i "$T/$j.avi" -vframes 1 \
			-vf scale=150:-1 "$T/m_$j.png" 2>/dev/null && [ -s "$T/m_$j.png" ]; then
			MUESTRAS+=( "$T/m_$j.png" ); ETIQUETAS+=( "$j:$punto" )
		fi
		rm -f "$T/$j.log" "$T/$j.med"

		"$AQUI/escribir_ajuste.py" "$AJUSTES" "$j" video "$punto" || {
			echo "no pude escribir en $AJUSTES"; fallos=$((fallos+1))
			rm -f "$T/$j.avi"; continue; }

		# Paso unico: el mp4 sale del avi que ya tenemos, sin volver a arrancar
		# el emulador. La duracion sale de arranque.dat si el juego la fija, o
		# el defecto; si el punto medido + la duracion no cabe en la ventana
		# grabada, se recorta a lo que haya.
		if [ "$GRABAR" = 1 ]; then
			dura=$( clave_de_arranque "$j" videodura ) || dura=$DURA
			libre=$(( VENTANA - punto ))
			[ "$dura" -gt "$libre" ] && dura=$libre
			if [ "$dura" -ge 3 ] && convertir_a_mp4 "$T/$j.avi" "$j" "$punto" "$dura"; then
				echo "video=$punto  $(du -h "$DESTINO/$j.mp4" | cut -f1)  ($detalle)"
			else
				echo "video=$punto  (medido; no se pudo grabar el video; $detalle)"
			fi
		else
			echo "video=$punto   ($detalle)"
		fi
		rm -f "$T/$j.avi"
		medidos=$((medidos+1))
	done

	# Hoja de contactos: 95 juegos en una imagen se revisan de un vistazo.
	if [ ${#MUESTRAS[@]} -gt 0 ]; then
		if command -v magick >/dev/null;    then MONTAR=( magick montage )
		elif command -v montage >/dev/null; then MONTAR=( montage )
		else MONTAR=(); fi
		if [ ${#MONTAR[@]} -gt 0 ]; then
			"${MONTAR[@]}" "${MUESTRAS[@]}" -tile 6x -geometry +3+3 \
				-background gray20 "$HOJA" 2>/dev/null &&
				echo "# hoja de contactos: $HOJA"
			echo -n "# orden (6 por fila):"
			for i in "${!ETIQUETAS[@]}"; do
				[ $(( i % 6 )) -eq 0 ] && printf '\n   '
				printf ' %-14s' "${ETIQUETAS[$i]}"
			done
			echo
		fi
	fi

	echo "# $medidos medidos, $saltados ya estaban, $fallos fallaron"
	echo "# escrito en $AJUSTES. Corrige a mano el que no te guste y vuelve a"
	echo "# grabar con:  FORZAR=1 $0 <juego>"
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

	if ya="$( video_existente "$j" )" && [ "${FORZAR:-0}" != "1" ]; then
		echo "  $j: ya tenia video ($(basename "$ya"), FORZAR=1 para rehacerlo)"
		saltados=$((saltados+1))
		continue
	fi

	# Precedencia, de mas fuerte a mas debil:
	#   SALTO= de la linea de ordenes > video= de arranque.dat >
	#   segundos= de arranque.dat (como suelo) > el defecto general.
	if [ -n "$SALTO_DE_ORDENES" ]; then
		salto=$SALTO_DE_ORDENES; origen="SALTO="
	elif salto=$( clave_de_arranque "$j" video ); then
		origen="arranque.dat video="
	elif salto=$( clave_de_arranque "$j" segundos ) && [ "$salto" -gt 0 ]; then
		origen="arranque.dat segundos="
		[ "$salto" -lt "$SALTO" ] && { salto=$SALTO; origen="defecto (segundos= es menor)"; }
	else
		salto=$SALTO; origen="defecto"
	fi

	# La duracion tambien se puede fijar por juego.
	if [ -n "$DURA_DE_ORDENES" ]; then
		dura=$DURA_DE_ORDENES
	elif ! dura=$( clave_de_arranque "$j" videodura ); then
		dura=$DURA
	fi

	echo -n "  $j: grabando (salto ${salto}s, ${dura}s, $origen)... "

	# El avi sale sin comprimir (unos 11 MB por segundo), por eso va a un
	# temporal y se borra en cuanto se convierte.
	( cd "$MAME_DIR" && xvfb-run -a "$MAME_BIN" "$j" -rompath "$ROMPATH" \
		-video soft -sound none -noswitchres -window -resolution 640x480 \
		-seconds_to_run $(( salto + dura + 2 )) -nothrottle \
		-aviwrite "$TMP/$j.avi" > "$TMP/$j.log" 2>&1 )

	if [ ! -s "$TMP/$j.avi" ]; then
		# Antes esto decia solo "no se pudo grabar" y habia que adivinar por
		# que. La causa casi siempre esta en la salida de MAME: rom que falta,
		# set que no existe en esta version, ficheros incompletos.
		echo "no se pudo grabar"
		grep -iE "not found|missing|fatal|required|unknown system" "$TMP/$j.log" |
			head -2 | sed 's/^/      /'
		fallos=$((fallos+1))
		rm -f "$TMP/$j.log"
		continue
	fi
	rm -f "$TMP/$j.log"

	echo -n "convirtiendo... "
	if convertir_a_mp4 "$TMP/$j.avi" "$j" "$salto" "$dura"; then
		echo "$(du -h "$DESTINO/$j.mp4" | cut -f1)"
		hechos=$((hechos+1))
	else
		echo "fallo la conversion (se deja el video que hubiera)"
		fallos=$((fallos+1))
	fi
	rm -f "$TMP/$j.avi"
done

echo
echo "# $hechos grabados, $saltados ya estaban, $fallos fallaron"
echo "# Recarga el layout con F5 para verlos."
