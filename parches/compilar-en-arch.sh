#!/bin/bash
# Compila GroovyMAME con los parches de la cabina en Arch (GroovyArcade).
#
#   ./parches/compilar-en-arch.sh
#
# POR QUE NO SIRVE EL RELEASE. El binario del release esta compilado en Ubuntu
# 24.04 y exige glibc 2.38 o mas; y aunque arrancara, GroovyArcade ya trae su
# GroovyMAME compilado para ella, con switchres funcionando de verdad. Lo que
# corresponde aqui es compilar en la propia maquina.
#
# QUE NO TOCA. Nada del sistema. El resultado va a
# ~/.local/share/groovymame-cabina/, que es donde instalar.sh lo busca. El
# groovymame de la distro se queda como esta, y volver atras es borrar esa
# carpeta.
#
# AVISO: compilar MAME tarda. En un mini-PC de cabina son varias horas y hacen
# falta unos 10 GB libres. Se puede dejar corriendo por ssh con tmux o nohup.
set -u

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$AQUI")"
DESTINO="${DESTINO:-$HOME/.local/share/groovymame-cabina}"
FUENTES="${FUENTES:-$HOME/groovymame-fuentes}"
TRABAJOS="${TRABAJOS:-$(nproc 2>/dev/null || echo 2)}"

rojo()  { printf '\033[31m%s\033[0m\n' "$*"; }
verde() { printf '\033[32m%s\033[0m\n' "$*"; }
aviso() { printf '\033[33m%s\033[0m\n' "$*"; }
paso()  { printf '\n\033[1m== %s\033[0m\n' "$*"; }

command -v pacman >/dev/null || { rojo "Esto es para Arch. En otras distros usa la tarea 'mame' de instalar.sh."; exit 1; }
[ "$(id -u)" -eq 0 ] && { rojo "No lo lances con sudo: pide lo que necesita el solo."; exit 1; }

# ---------------------------------------------------------------- sitio
paso "Comprobando que hay sitio"
libres=$(( $(df -Pk "$HOME" | awk 'NR==2{print $4}') / 1048576 ))
echo "  libres en $HOME: ${libres} GB"
if [ "$libres" -lt 12 ]; then
	rojo "  hacen falta unos 12 GB y hay $libres"
	exit 1
fi

# ---------------------------------------------------------------- dependencias
paso "Dependencias de compilacion"
# Las de MAME en Arch. base-devel es un grupo (gcc, make, pkgconf, patch...).
PAQUETES=( base-devel git python sdl2 sdl2_ttf fontconfig libxinerama
           alsa-lib libpulse flac portaudio portmidi expat zlib
           libjpeg-turbo rapidjson glm libutf8proc asio lua )
faltan=()
for p in "${PAQUETES[@]}"; do
	pacman -Qq "$p" >/dev/null 2>&1 || pacman -Qg "$p" >/dev/null 2>&1 || faltan+=( "$p" )
done
if [ ${#faltan[@]} -gt 0 ]; then
	echo "  faltan: ${faltan[*]}"
	# Uno por uno no: pacman aborta entero si un nombre no existe en esta
	# version de los repos, asi que se filtran antes.
	buenos=()
	for p in "${faltan[@]}"; do
		pacman -Si "$p" >/dev/null 2>&1 || pacman -Sg "$p" >/dev/null 2>&1 &&
			buenos+=( "$p" ) || aviso "  no esta en los repos: $p"
	done
	if [ ${#buenos[@]} -gt 0 ] && ! sudo pacman -S --needed --noconfirm "${buenos[@]}"; then
		# 404 en todos los espejos = base de datos vieja, no problema de red.
		rojo "  Fallo la descarga en todos los espejos."
		rojo "  La base de datos de pacman esta desfasada. Arreglalo con:"
		rojo "      sudo pacman -Syu"
		rojo "  (en Arch la actualizacion hay que hacerla entera: un -Sy a"
		rojo "   secas deja el sistema a medias)"
		exit 1
	fi
else
	verde "  no falta nada"
fi

# ---------------------------------------------------------------- fuentes
paso "Fuentes de GroovyMAME"
# La version que hay instalada, para clonar la misma y no una cualquiera.
version="$( groovymame -version 2>/dev/null | grep -oE '^[0-9]+\.[0-9]+' )"
if [ -n "$version" ]; then
	echo "  el groovymame instalado es $version"
	rama="mame${version/./}"      # 0.264 -> mame0264
else
	aviso "  no pude leer la version instalada; uso la rama por defecto"
	rama=""
fi

if [ -d "$FUENTES/.git" ]; then
	echo "  ya estan en $FUENTES"
else
	echo "  clonando (esto baja bastante)..."
	git clone --depth 1 ${rama:+--branch "$rama"} \
		https://github.com/antonioginer/GroovyMAME.git "$FUENTES" || {
		aviso "  no existe la rama $rama; pruebo sin fijarla"
		git clone --depth 1 https://github.com/antonioginer/GroovyMAME.git "$FUENTES" || exit 1
	}
fi

# ---------------------------------------------------------------- parches
paso "Aplicando los parches de la cabina"
for p in "$AQUI"/*.patch; do
	nombre="$(basename "$p")"
	# -N no lo aplica dos veces; --dry-run primero para no dejarlo a medias.
	if patch -d "$FUENTES" -p1 -N --dry-run -s -r - < "$p" >/dev/null 2>&1; then
		patch -d "$FUENTES" -p1 -N -r - < "$p" >/dev/null && echo "  + $nombre"
	else
		aviso "  = $nombre ya estaba (o no encaja en estas fuentes)"
	fi
done

# ---------------------------------------------------------------- compilar
paso "Compilando con $TRABAJOS trabajos (esto tarda horas)"
extra=()
command -v ccache >/dev/null && extra+=( "PATH=/usr/lib/ccache:$PATH" )
( cd "$FUENTES" && env "${extra[@]}" make -j"$TRABAJOS" NOWERROR=1 USE_QTDEBUG=0 ) || {
	rojo "Fallo la compilacion. Lo mas comun es quedarse sin memoria:"
	rojo "  vuelve a lanzarlo con TRABAJOS=1 ./parches/compilar-en-arch.sh"
	exit 1
}

# ---------------------------------------------------------------- instalar
paso "Colocandolo"
binario="$( find "$FUENTES" -maxdepth 1 -type f -executable -name 'mame*' | head -1 )"
[ -n "$binario" ] || { rojo "No encuentro el binario recien compilado"; exit 1; }

mkdir -p "$DESTINO"
cp "$binario" "$DESTINO/mame" && chmod +x "$DESTINO/mame"
# El bgfx va AL LADO: MAME lo busca en "bgfx" relativo a su directorio de
# trabajo, y el .cfg del emulador pone ahi el workdir.
cp -r "$FUENTES/bgfx" "$DESTINO/" 2>/dev/null
cp "$REPO/config/cabina/crt-real.json" "$DESTINO/bgfx/chains/" 2>/dev/null &&
	echo "  + bgfx/chains/crt-real.json"

if "$DESTINO/mame" -version >/dev/null 2>&1; then
	verde "Listo: $DESTINO/mame  ($("$DESTINO/mame" -version 2>&1 | head -1))"
	echo
	echo "Ahora pasa el instalador para que la cabina lo use:"
	echo "    cd $REPO && MAME=$DESTINO/mame ./instalar.sh"
	echo
	echo "El groovymame de la distro sigue intacto. Para volver atras:"
	echo "    rm -rf $DESTINO"
else
	rojo "Compilo pero no arranca:"
	"$DESTINO/mame" -version 2>&1 | head -3 | sed 's/^/  /'
	exit 1
fi
