# Lo que comparten videos.sh (grabacion automatica) y grabar.sh (grabar mi
# propia partida): encontrar el emulador y convertir un AVI crudo de MAME al
# mp4 que espera el frontend.
#
# Vive aparte porque las dos cosas tienen trampas que costaron una pasada cada
# una -- la proporcion 4:3 del mueble, el ampliado en dos fases, borrar TODAS
# las extensiones de video -- y tener dos copias significa arreglarlas en una y
# no en la otra. Se carga con  . "$AQUI/video_comun.sh"  despues de definir AQUI.
#
# Lo que el script que lo carga tiene que tener puesto:
#   AQUI       directorio de este fichero
#   DESTINO    carpeta de snaps del frontend (para convertir_a_mp4)
#   CALIDAD    crf de x264
#   AMPLIAR    1 o 0
#   AUDIO_FFMPEG   argumentos de audio de ffmpeg ('-an' o un codec)

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
# /usr/share/games/mame/roms y en la cabina ~/shared/roms/mame.
. "$AQUI/comun.sh"
ROMPATH="$( rompath_de "$MAME_BIN" )"

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
	#
	# El audio lo decide quien llama, con AUDIO_FFMPEG. Los videos automaticos
	# van MUDOS ('-an'): se graban bajo Xvfb, sin tarjeta, y ahi el sonido no es
	# fiable. Una partida grabada por una persona es lo contrario -- se juega en
	# la cabina, con sonido de verdad, y ese sonido es medio video.
	#
	# Y 'dura' vacia o 0 significa "hasta el final": la toma dura lo que el
	# jugador quiso, no una ventana fijada de antemano.
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
	local corte=()
	[ -n "$dura" ] && [ "$dura" != "0" ] && corte=( -t "$dura" )
	local audio=(); read -ra audio <<< "${AUDIO_FFMPEG:--an}"

	if ffmpeg -y -loglevel error -i "$avi" -ss "$salto" "${corte[@]}" \
		-vf "scale=${entero/x/:}:flags=neighbor,scale=${final/x/:}:flags=lanczos" \
		-c:v libx264 -preset slow -crf "$CALIDAD" -pix_fmt yuv420p "${audio[@]}" \
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
