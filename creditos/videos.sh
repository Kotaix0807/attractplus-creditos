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
#   video=N       segundo en el que empieza lo que quieres grabar (absoluto)
#   videomas=N    segundos DESPUES de 'segundos=' (relativo; admite decimales
#                 y negativos). Si manana cambias 'segundos=', el video se
#                 mueve solo con el en vez de quedarse apuntando a un instante
#                 que ya no existe.
#   videodura=N   cuanto dura el video de ese juego
#
#   contra segundos=7 velocidad=0 video=16
#   mwalk  segundos=11.8 nvram=0 videomas=3     -> el clip empieza en 14.8
#
# 'video=' manda sobre 'videomas=': un numero absoluto escrito a mano es una
# decision, y no se pisa con una cuenta. Sin ninguno de los dos se usa
# 'segundos=' como suelo, y si tampoco lo hay, 8 s. creditos.lua ignora las
# tres claves de video.
#
# Por que grabarlos en vez de bajarlos: la fuente que AM+ trae incrustada
# (progettosnaps.net/videosnaps/mp4/) devuelve 404 desde hace tiempo, y
# arcadeitalia no sirve videos. Pero las roms y el emulador ya estan aqui.
#
# El video va a  <config>/scraper/<emulador>/snap/<juego>.mp4 , el mismo sitio
# que la captura fija. AM+ prefiere el video cuando existe.
set -u

# Lo compartido con grabar.sh -- encontrar el emulador, la proporcion del
# mueble, la conversion a mp4 -- vive en video_comun.sh. Define MAME_BIN,
# MAME_DIR, ROMPATH, proporcion(), convertir_a_mp4(), borrar_videos() y
# video_existente(), y comprueba que haya ffmpeg.
AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$AQUI/video_comun.sh"

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
#   video=N       segundo en el que empieza lo que quieres grabar (absoluto)
#   videomas=N    segundos despues de 'segundos=' (relativo, con decimales)
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
	# Los DECIMALES son legitimos: ajustes.lua los acepta desde siempre
	# (tonumber sobre [%w%.%-]+), asi que 'segundos=11.8' es una linea valida y
	# creditos.lua la aplica tal cual. Este lector pedia [0-9]+ y leia 11,
	# CALLADO: el video empezaba casi un segundo antes de donde se pidio y no
	# habia nada en pantalla que lo dijera. Y el signo tambien hace falta, para
	# que 'videomas=-2' se pueda escribir.
	v="$( printf '%s' "$linea" | grep -oE "(^|[[:space:]])$2=-?[0-9]+(\.[0-9]+)?" |
	      head -1 | cut -d= -f2 )"
	[ -n "$v" ] || return 1
	printf '%s' "$v"
}

# Y con decimales en juego, bash ya no sabe sumar ni comparar: $(( 11.8 + 3 ))
# es un error de sintaxis. Estas dos hacen la cuenta con awk y devuelven el
# numero sin decimales sobrantes (14.8 se queda en 14.8; 15.0 sale como 15).
calc() {   # calc "11.8 + 3"
	awk "BEGIN{ v = $1; printf (v == int(v)) ? \"%d\" : \"%g\", v }"
}
es_menor() { awk -v a="$1" -v b="$2" 'BEGIN{ exit !(a < b) }'; }

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
	# Red de seguridad; el Lua sale antes por su cuenta. Con awk porque 'inicio'
	# puede llevar decimales (segundos=11.8), y se redondea hacia ARRIBA: un
	# tope corto cortaria el clip por el final.
	tope=$( awk -v i="$inicio" -v d="$dura" -v m="$margen" \
		'BEGIN{ printf "%d", int(i + d + m + 4) + 1 }' )
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
	elif mas=$( clave_de_arranque "$j" videomas ); then
		# El desfase: el video empieza tantos segundos DESPUES de donde acaba el
		# arranque tapado. Se apoya en 'segundos=' en vez de repetir su valor,
		# asi que si un dia se retoca la carga del juego el video se mueve solo
		# con ella y no se queda apuntando a un instante que ya no existe.
		base=$( clave_de_arranque "$j" segundos ) || base=0
		salto=$( calc "$base + $mas" )
		es_menor "$salto" 0 && salto=0
		origen="arranque.dat segundos=$base + videomas=$mas"
		# Aqui NO se aplica el suelo de 8 s. Con 'videomas=' el punto lo has
		# elegido tu a mano; subirlo por nuestra cuenta seria ignorar la orden.
	elif salto=$( clave_de_arranque "$j" segundos ) && ! es_menor "$salto" 0.0001; then
		origen="arranque.dat segundos="
		es_menor "$salto" "$SALTO" && { salto=$SALTO; origen="defecto (segundos= es menor)"; }
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
