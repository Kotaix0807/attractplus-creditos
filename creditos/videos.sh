#!/bin/bash
# Graba un video de muestra de cada juego, del propio emulador.
#
#   ./videos.sh pacman dkong       # esos juegos
#   ./videos.sh                    # todos los de la romlist
#   ./videos.sh --tira simpsons    # hoja de contactos de un juego, para ver el salto
#   ./videos.sh --hojas            # hoja de contactos de todos + fichero de tiempos
#   ./videos.sh --desde hojas/tiempos.txt   # graba cada juego en el segundo apuntado
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
# normal y --desde --, para que el pipeline de escalado y calidad sea el mismo
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

# El binario de ImageMagick: 'magick' en la 7, 'montage'/'convert' sueltos en
# la 6. Se resuelve una vez.
montador() {
	if command -v magick >/dev/null;    then echo "magick montage"
	elif command -v montage >/dev/null; then echo "montage"
	else return 1; fi
}

# Hoja de contactos de un AVI: doce fotogramas repartidos por la grabacion,
# etiquetados con su segundo, para VER de un vistazo en que momento empieza el
# juego. $1=avi  $2=png de salida  $3=juego (solo para el mensaje).
# Devuelve por stdout los segundos de cada fotograma, en orden.
# Los doce instantes de la hoja se reparten por la VENTANA grabada, no fijos:
# con una ventana de 120s hay que mirar tambien la segunda mitad, que es justo
# donde asoma el gameplay de los juegos con intro larga. Antes estaban clavados
# a 60s y una hoja de 120s salia identica a una de 62s (no servia de nada).
instantes_tira() {   # -> 12 segundos repartidos en la ventana
	local vent="${VENTANA:-62}" i paso
	paso=$(( vent / 13 )); [ "$paso" -lt 1 ] && paso=1
	for i in $(seq 1 12); do echo -n "$(( paso * i )) "; done
}
hacer_tira() {
	local avi="$1" salida="$2" T archivos=() t
	local INSTANTES_TIRA; INSTANTES_TIRA="$( instantes_tira )"
	local -a MONTAR; read -ra MONTAR < <( montador ) || {
		echo "hace falta imagemagick" >&2; return 1; }
	T=$(mktemp -d /tmp/tira-mame.XXXXXX)
	for t in $INSTANTES_TIRA; do
		ffmpeg -y -loglevel error -ss "$t" -i "$avi" -vframes 1 \
			-vf scale=150:-1 "$T/$t.png" 2>/dev/null && archivos+=( "$T/$t.png" )
	done
	# montage rotula con -label pero necesita una fuente; en GroovyArcade no hay
	# ninguna configurada y sale "unable to read font (null)". Se le da una si el
	# sistema sabe cual, y si no, la tira sale sin numeros (el orden se sabe por
	# INSTANTES_TIRA de todas formas).
	local fuente; fuente="$( fc-match -f '%{file}' sans 2>/dev/null )"
	if [ -n "$fuente" ] && [ -f "$fuente" ]; then
		"${MONTAR[@]}" "${archivos[@]}" -tile 4x3 -geometry +4+4 -background gray \
			-font "$fuente" -pointsize 14 -label '%t s' "$salida" 2>/dev/null
	fi
	[ -s "$salida" ] || "${MONTAR[@]}" "${archivos[@]}" -tile 4x3 -geometry +4+4 \
		-background gray "$salida" 2>/dev/null
	rm -rf "$T"
	[ -s "$salida" ]
}

# creditos.lua, el mismo autoboot que la cabina: arranca cada juego con los
# ajustes de arranque.dat (velocidad=, segundos=) y tapa la carga. Asi el video
# se graba del juego arrancado EXACTAMENTE como en la cabina. La carga tapada
# (negro) se descarta al cortar el clip desde video=.
CREDITOS_LUA="${CREDITOS_LUA:-$AQUI/creditos.lua}"

# Graba con MAME a un AVI crudo, arrancando el juego con creditos.lua.
#   $1=juego  $2=segundos a grabar  $3=avi de salida  $4=log
grabar_avi() {
	local j="$1" segs="$2" avi="$3" log="$4" ga
	ga=$(mktemp)   # monedero aislado: no tocar el de verdad al grabar
	( cd "$MAME_DIR" && env GA_ARCHIVO="$ga" ${GA_VERBOSO:+GA_VERBOSO=1} \
		xvfb-run -a "$MAME_BIN" "$j" -rompath "$ROMPATH" \
		-video soft -sound none -noswitchres -window -resolution 640x480 \
		-seconds_to_run "$segs" -nothrottle -aviwrite "$avi" \
		-autoboot_script "$CREDITOS_LUA" -autoboot_delay 0 > "$log" 2>&1 )
	rm -f "$ga"
	[ -s "$avi" ]
}

# Graba SOLO la ventana del clip, acelerando toda la carga con frameskip. En vez
# de renderizar y escribir al AVI los ~90 s entre el arranque y el gameplay para
# que ffmpeg los tire, creditos.lua (modo GA_GRABAR) corre la carga a maxima
# velocidad y arranca el AVI de MAME (begin_recording) justo en el segundo del
# video. El AVI resultante ES el clip: empieza en 0, dura 'dura' segundos.
#   $1=juego  $2=inicio(salto)  $3=dura  $4=avi (ABSOLUTO)  $5=log
grabar_clip() {
	local j="$1" inicio="$2" dura="$3" avi="$4" log="$5" ga margen=2 tope
	ga=$(mktemp)
	tope=$(( inicio + dura + margen + 4 ))   # red de seguridad; Lua sale antes
	( cd "$MAME_DIR" && env GA_ARCHIVO="$ga" ${GA_VERBOSO:+GA_VERBOSO=1} \
		GA_GRABAR="$inicio" GA_GRABAR_DURA="$dura" GA_GRABAR_MARGEN="$margen" \
		GA_GRABAR_ARCHIVO="$avi" \
		xvfb-run -a "$MAME_BIN" "$j" -rompath "$ROMPATH" \
		-video soft -sound none -noswitchres -window -resolution 640x480 \
		-seconds_to_run "$tope" -nothrottle \
		-autoboot_script "$CREDITOS_LUA" -autoboot_delay 0 > "$log" 2>&1 )
	rm -f "$ga"
	[ -s "$avi" ]
}

case "${1:-}" in
	-h|--help|--ayuda)
		sed -n '2,16p' "$0" | sed 's/^# \?//'
		exit 0 ;;
	--*)
		case "$1" in
			--tira|--hojas|--desde) ;;
			*) echo "opcion desconocida: $1 (prueba --ayuda)" >&2; exit 1 ;;
		esac ;;
esac

# --tira <juego>: graba un minuto y saca una tira de fotogramas, para VER en
# que segundo empieza lo que quieres grabar en vez de adivinarlo.
# --tira <juego>: hoja de contactos de UN juego, para VER en que segundo empieza
# lo que quieres grabar en vez de adivinarlo.
if [ "${1:-}" = "--tira" ]; then
	[ $# -eq 2 ] || { echo "uso: $0 --tira <juego>" >&2; exit 1; }
	j="$2"
	T=$(mktemp -d /tmp/tira-mame.XXXXXX); trap 'rm -rf "$T"' EXIT
	echo "grabando ${VENTANA:-62}s de $j (arrancando con creditos.lua)..."
	grabar_avi "$j" "${VENTANA:-62}" "$T/v.avi" "$T/mame.log" || {
		echo "no se pudo grabar $j:" >&2
		grep -iE "not found|missing|fatal|error" "$T/mame.log" | head -3 >&2; exit 1; }
	SALIDA="${SALIDA:-$PWD/tira-$j.png}"
	hacer_tira "$T/v.avi" "$SALIDA" "$j" || exit 1
	echo "tira en $SALIDA"
	echo -n "orden de los fotogramas (4 por fila), en segundos:"
	i=0; for t in $( instantes_tira ); do
		[ $(( i % 4 )) -eq 0 ] && printf '\n   '; printf '%4s' "$t"; i=$((i+1)); done
	echo
	echo "Apunta el segundo del gameplay en $AJUSTES, en la linea de $j, como"
	echo "  video=<segundos>   (o pruebalo sin tocar nada:  SALTO=<n> FORZAR=1 $0 $j)"
	exit 0
fi

# --hojas [juegos...]: la hoja de contactos de MUCHOS juegos de una tacada, mas
# un fichero de tiempos para que apuntes el segundo bueno de cada uno. Es la
# FASE 1 del flujo semiautomatico:
#
#   1. ./videos.sh --hojas            -> graba y deja hojas/<juego>.png + hojas/tiempos.txt
#   2. miras cada hoja y escribes el segundo del GAMEPLAY en tiempos.txt
#   3. ./videos.sh --desde hojas/tiempos.txt   -> graba cada video en su punto
#
# Distinguir "juego jugandose" de "titulo/tabla" a ojo es trivial y 100% fiable;
# hacerlo con analisis de imagen no lo es (el titulo de Mario parpadea mas que
# su demo). Por eso la eleccion la haces tu, una vez, mirando las hojas.
if [ "${1:-}" = "--hojas" ]; then
	shift
	HOJAS="${HOJAS:-$PWD/hojas}"; mkdir -p "$HOJAS"
	TIEMPOS="$HOJAS/tiempos.txt"
	if [ $# -gt 0 ]; then JUEGOS=( "$@" )
	else mapfile -t JUEGOS < <(cut -d';' -f1 "$ROMLIST" | grep -v '^#'); fi

	# El fichero de tiempos se crea si no existe, y NO se pisa si ya esta: asi
	# puedes parar y seguir sin perder lo que ya apuntaste.
	[ -f "$TIEMPOS" ] || {
		echo "# Apunta el segundo donde empieza el GAMEPLAY de cada juego, mirando"  >  "$TIEMPOS"
		echo "# su hoja en $HOJAS/<juego>.png. Deja en blanco para saltarlo."        >> "$TIEMPOS"
		echo "# Formato:  juego=segundos     Ejemplo:  galaga=20"                     >> "$TIEMPOS"
	}

	hechas=0; saltadas=0; fallos=0
	for j in "${JUEGOS[@]}"; do
		[ -n "$j" ] || continue
		if [ -z "${FORZAR:-}" ] && [ -s "$HOJAS/$j.png" ]; then
			echo "  $j: ya tenia hoja (FORZAR=1 para rehacerla)"; saltadas=$((saltadas+1)); continue
		fi
		echo -n "  $j: grabando ${VENTANA:-62}s... "
		T=$(mktemp -d /tmp/hojas-mame.XXXXXX)
		if ! grabar_avi "$j" "${VENTANA:-62}" "$T/v.avi" "$T/mame.log"; then
			echo "no se pudo grabar"
			grep -iE "not found|missing|fatal|required|unknown system" "$T/mame.log" | head -2 | sed 's/^/      /'
			fallos=$((fallos+1)); rm -rf "$T"; continue
		fi
		if hacer_tira "$T/v.avi" "$HOJAS/$j.png" "$j"; then
			# sugerencia: si ya habia un video= apuntado, se respeta como valor de partida
			ya=$( clave_de_arranque "$j" video ) || ya=""
			grep -q "^$j=" "$TIEMPOS" 2>/dev/null || echo "$j=$ya" >> "$TIEMPOS"
			echo "hoja lista"; hechas=$((hechas+1))
		else
			echo "no pude hacer la hoja"; fallos=$((fallos+1))
		fi
		rm -rf "$T"
	done
	echo "# $hechas hojas nuevas, $saltadas ya estaban, $fallos fallaron"
	echo "# Ahora mira las hojas en $HOJAS/ y rellena $TIEMPOS,"
	echo "# luego:  ./videos.sh --desde $TIEMPOS"
	exit 0
fi

# --desde <tiempos.txt>: FASE 2. Lee 'juego=segundos', escribe cada uno en
# arranque.dat como video= y graba su mp4 cortando en ese punto. Los que esten
# en blanco se saltan (aun no los has mirado).
if [ "${1:-}" = "--desde" ]; then
	[ $# -eq 2 ] && [ -f "$2" ] || { echo "uso: $0 --desde <tiempos.txt>" >&2; exit 1; }
	grabados=0; saltados=0; fallos=0
	# El fichero se lee por el descriptor 3, no por stdin: si fuera stdin, el
	# MAME (o ffmpeg) que graba cada juego se comeria el resto de las lineas y
	# solo se procesaria el primero. Paso una pasada averiguarlo.
	while IFS='=' read -r j t <&3; do
		j="${j%%[[:space:]]*}"; t="${t//[[:space:]]/}"
		[ -n "$j" ] || continue
		case "$j" in \#*) continue ;; esac
		if [ -z "$t" ]; then saltados=$((saltados+1)); continue; fi
		case "$t" in *[!0-9]*) echo "  $j: '$t' no es un numero, lo salto"; fallos=$((fallos+1)); continue ;; esac
		"$AQUI/escribir_ajuste.py" "$AJUSTES" "$j" video "$t" || {
			echo "  $j: no pude escribir en $AJUSTES"; fallos=$((fallos+1)); continue; }
		echo "  $j: video=$t, grabando..."
		if FORZAR=1 SALTO="$t" "$0" "$j" </dev/null >/dev/null 2>&1 && [ -s "$DESTINO/$j.mp4" ]; then
			echo "     $(du -h "$DESTINO/$j.mp4" | cut -f1)"; grabados=$((grabados+1))
		else
			echo "     fallo la grabacion"; fallos=$((fallos+1))
		fi
	done 3< "$2"
	echo "# $grabados grabados, $saltados en blanco (sin apuntar), $fallos fallaron"
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

	# Se acelera la carga y se graba SOLO la ventana: el AVI ya es el clip. Antes
	# se grababa desde el frame 0 (11 MB/s de AVI crudo) y ffmpeg tiraba la carga;
	# para un gameplay a los 90 s eran gigas escritos para nada.
	grabar_clip "$j" "$salto" "$dura" "$TMP/$j.avi" "$TMP/$j.log"

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
	if convertir_a_mp4 "$TMP/$j.avi" "$j" 0 "$dura"; then
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
