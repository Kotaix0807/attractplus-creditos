#!/bin/bash
# Deja la cabina lista en una maquina nueva, preguntando lo justo.
#
#   git clone <este repo> ~/Dev/arcade/attractplus
#   git clone <el otro>   ~/Dev/arcade/groovyarcade-creditos
#   cd ~/Dev/arcade/attractplus && ./instalar.sh
#
# Va por pasos con whiptail. TODO tiene valor por defecto: si le das a Enter a
# todo, o si lanzas con --sin-preguntar, hace lo razonable sin preguntar nada.
#
# Distros: Debian/Ubuntu/Mint (apt) y Arch/GroovyArcade (pacman). En
# GroovyArcade el emulador ya viene con el sistema y no hay que compilarlo.
#
# Opciones:
#   -s, --sin-preguntar   no pregunta nada, usa todos los valores por defecto
#   -h, --ayuda           esto
#
# Se puede fijar por entorno lo que se quiera saltar la deteccion:
#   MAME=/usr/bin/groovymame ROMS=/ruta CREDITOS=/ruta DESTINO=/ruta
#   TAREAS="config romlist"   (deps compilar config romlist arte crt mame videos)
#
# Lo que NO hace, a proposito:
#   - No toca ~/.attract/config/attract.cfg si ya existe: ahi estan tus teclas.
#   - No mapea el boton de moneda: eso hay que hacerlo dentro de MAME, con la
#     cabina delante.
set -u

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PREGUNTAR=1
DIAGNOSTICO=0
for a in "$@"; do
	case "$a" in
		-s|--sin-preguntar) PREGUNTAR=0 ;;
		-d|--diagnostico)   DIAGNOSTICO=1 ;;
		-h|--ayuda|--help)
			sed -n '2,/^set -u/p' "$0" | sed '$d; s/^# \?//'; exit 0 ;;
		*) echo "opcion desconocida: $a (prueba --ayuda)" >&2; exit 1 ;;
	esac
done

# Con sudo, HOME es /root y la configuracion entera acaba en /root/.attract:
# el frontend, que corre como tu, no la ve nunca. Ademas el sonido y la sesion
# grafica son del usuario, no de root. El script ya pide sudo el solo para los
# paquetes, que es lo unico que lo necesita.
if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
	printf '\033[31m%s\033[0m\n' "No lo lances con sudo."
	echo "  Con sudo la configuracion se escribe en /root/.attract y el"
	echo "  frontend, que corre como $SUDO_USER, no la encuentra."
	echo
	echo "  Lanzalo asi:   ./instalar.sh"
	echo "  (te pedira la contrasena solo para instalar paquetes)"
	exit 1
fi

if [ "$DIAGNOSTICO" = 1 ]; then
	echo "== Diagnostico de la maquina =="
	echo
	echo "--- distro ---"; cat /etc/os-release 2>/dev/null | head -4
	echo; echo "--- disposicion ---"
	ls -la "$HOME" 2>/dev/null | head -20
	for d in "$HOME"/shared "$HOME"/shared/frontends "$HOME"/shared/frontends/* \
	         "$HOME"/shared/configs; do
		[ -d "$d" ] && { echo; echo "  $d:"; ls -la "$d" | head -25; }
	done
	echo; echo "--- ejecutables ---"
	for b in attract attractplus mame groovymame gasetup advmame; do
		p="$(command -v "$b" 2>/dev/null)" && echo "  $b -> $p$( [ -L "$p" ] && echo " -> $(readlink -f "$p")" )"
	done
	echo; echo "--- de donde salen las rutas del frontend ---"
	for f in /usr/bin/gasetup /usr/local/bin/gasetup /etc/gasetup*; do
		[ -e "$f" ] && { echo "  $f:"; grep -inE "attract|frontend|shared" "$f" 2>/dev/null | head -20 | sed 's/^/    /'; }
	done
	grep -rlni "attract" /etc 2>/dev/null | head -10 | sed 's/^/  cfg: /'
	echo; echo "--- mame ---"
	command -v groovymame >/dev/null && groovymame -showconfig 2>/dev/null |
		grep -E "^(rompath|cfg_directory|nvram_directory|inipath|bgfx_path|homepath|snapshot_directory) " | sed 's/^/  /'
	echo; echo "--- sesion grafica ---"
	echo "  DISPLAY=[${DISPLAY:-}] WAYLAND=[${WAYLAND_DISPLAY:-}] TIPO=${XDG_SESSION_TYPE:-}"
	exit 0
fi

rojo()  { printf '\033[31m%s\033[0m\n' "$*"; }
verde() { printf '\033[32m%s\033[0m\n' "$*"; }
aviso() { printf '\033[33m%s\033[0m\n' "$*"; }
paso()  { printf '\n\033[1m== %s\033[0m\n' "$*"; }

# ---------------------------------------------------------------- dialogos
#
# Todo pasa por aqui, y todo tiene defecto. Si no hay whiptail, si la salida no
# es un terminal, o si se paso --sin-preguntar, se usa el defecto sin molestar.
# Cancelar tambien deja el defecto: cancelar una pregunta no debe tirar abajo
# una instalacion a medias.
hay_dialogo() {
	[ "$PREGUNTAR" = 1 ] && [ -t 0 ] && [ -t 1 ] && command -v whiptail >/dev/null
}

d_texto() {   # titulo mensaje defecto -> escribe el valor
	local t="$1" m="$2" def="$3" val
	case "$m" in -*) m=$'\n'"$m" ;; esac   # whiptail lo tomaria por una opcion
	if ! hay_dialogo; then echo "$def"; return; fi
	val=$( whiptail --title "$t" --inputbox "$m" 12 74 "$def" 3>&1 1>&2 2>&3 ) || val=""
	# vacio (Enter a secas o Cancelar) = el defecto
	[ -n "$val" ] || val="$def"
	echo "$val"
}

d_si() {      # titulo mensaje defecto(si|no) -> 0 si es que si
	local t="$1" m="$2" def="$3"
	case "$m" in -*) m=$'\n'"$m" ;; esac   # whiptail lo tomaria por una opcion
	if ! hay_dialogo; then [ "$def" = si ]; return; fi
	if [ "$def" = si ]; then
		whiptail --title "$t" --yesno "$m" 12 74
	else
		whiptail --title "$t" --yesno --defaultno "$m" 12 74
	fi
}

d_aviso() {   # titulo mensaje
	# El salto delante no es adorno: whiptail toma por OPCION cualquier
	# argumento que empiece por "-", y el mensaje del final empieza con una
	# lista de guiones. Sin esto responde "- ...: unknown option" y no dibuja.
	local m="$2"
	case "$m" in -*) m=$'\n'"$m" ;; esac
	if hay_dialogo; then whiptail --title "$1" --msgbox "$m" 20 74
	else printf '%b\n' "$m"; fi
}

# ---------------------------------------------------------------- deteccion
paso "Mirando que hay en esta maquina"

if   command -v pacman  >/dev/null; then GESTOR=pacman
elif command -v apt-get >/dev/null; then GESTOR=apt
elif command -v dnf     >/dev/null; then GESTOR=dnf
else GESTOR=""; fi

DISTRO="$( . /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-desconocida}" )"
echo "  distro:   $DISTRO"
echo "  paquetes: ${GESTOR:-no reconocido}"

# whiptail es lo que hace agradable el resto, y en una maquina recien instalada
# es justo lo que no esta. Se ofrece antes que nada, en texto plano, porque
# todavia no hay con que dibujar un cuadro.
if [ "$PREGUNTAR" = 1 ] && [ -t 0 ] && ! command -v whiptail >/dev/null && [ -n "$GESTOR" ]; then
	case "$GESTOR" in
		pacman) paq=libnewt ;;   # en Arch whiptail lo trae libnewt
		*)      paq=whiptail ;;
	esac
	read -r -p "  whiptail no esta, y con el se ve mucho mejor. Instalar $paq? [S/n] " r
	case "${r:-s}" in
		[SsYy]*) case "$GESTOR" in
					pacman) sudo pacman -S --needed --noconfirm "$paq" ;;
					apt)    sudo apt-get update && sudo apt-get install -y "$paq" ;;
					dnf)    sudo dnf install -y newt ;;
				 esac ;;
		*) echo "  vale, sigo en modo texto" ;;
	esac
fi

# --- GroovyArcade tiene su propia disposicion --------------------------------
#
# La distro no usa ~/.attract: guarda todo en ~/shared, y gasetup ("Start
# Front-End") lanza desde ahi.
#
#   ~/shared/roms/mame             las roms (una carpeta por emulador)
#   ~/shared/frontends/attract     la configuracion del frontend
#   ~/shared/frontends/groovymame  la del emulador
#   ~/shared/media                 artes y videos
#   ~/shared/configs               configuracion del sistema
#
# Se detecta por el directorio, no por el nombre de la distro: si alguien copia
# esa disposicion en otro sitio, tambien vale.
ES_GROOVYARCADE=0
COMPARTIDO="$HOME/shared"
if [ -d "$COMPARTIDO/frontends/attract" ] && [ -d "$COMPARTIDO/roms" ]; then
	ES_GROOVYARCADE=1
	echo "  disposicion: GroovyArcade ($COMPARTIDO)"
fi

# La configuracion de gasetup: de ahi sale QUE frontend lanza y como esta
# declarada la pantalla. Se lee, no se escribe: cambiar 'monitor' a mano no
# regenera la linea del kernel ni el xorg.conf, eso lo hace gasetup.
GA_CONF="$COMPARTIDO/configs/ga.conf"
ga_valor() { [ -f "$GA_CONF" ] && sed -n "s/^$1=//p" "$GA_CONF" | head -1; }
if [ "$ES_GROOVYARCADE" = 1 ] && [ -f "$GA_CONF" ]; then
	echo "  gasetup:  frontend=$( ga_valor frontend ) monitor=$( ga_valor monitor )" \
	     "backend=$( ga_valor video.backend )"
fi

if [ "$ES_GROOVYARCADE" = 1 ]; then
	DESTINO="${DESTINO:-$COMPARTIDO/frontends/attract}"
	# Las roms van una carpeta mas adentro, por emulador: shared/roms/mame
	if [ -z "${ROMS:-}" ]; then
		for c in "$COMPARTIDO"/roms/mame "$COMPARTIDO"/roms; do
			[ -d "$c" ] && { ROMS="$c"; break; }
		done
	fi
else
	DESTINO="${DESTINO:-$HOME/.attract}"
fi
CREDITOS="${CREDITOS:-$(cd "$AQUI/../groovyarcade-creditos" 2>/dev/null && pwd || true)}"

if [ -z "${MAME:-}" ]; then
	# El de al lado primero: si los repos estan juntos (el caso normal), ese es
	# el GroovyMAME parcheado. En GroovyArcade el bueno es el del sistema.
	for c in "$AQUI/../groovymame_src/mame" "$HOME/groovymame_src/mame" \
	         /usr/local/bin/groovymame /usr/bin/groovymame \
	         /usr/bin/mame /usr/games/mame; do
		[ -x "$c" ] && { MAME="$c"; break; }
	done
fi
if [ -z "${ROMS:-}" ]; then
	for c in /usr/share/games/mame/roms "$HOME/roms" \
	         /usr/local/share/games/mame/roms; do
		[ -d "$c" ] && { ROMS="$c"; break; }
	done
fi
# Sin "..": esta ruta acaba escrita en el .cfg del emulador y en mame.ini.
[ -n "${MAME:-}" ] && MAME="$(cd "$(dirname "$MAME")" && pwd)/$(basename "$MAME")"
echo "  emulador: ${MAME:-no encontrado}"
echo "  roms:     ${ROMS:-no encontradas}"
echo "  creditos: ${CREDITOS:-no encontrado}"

# ---------------------------------------------------------------- dependencias
#
# Lo que hace falta y quien lo trae en cada distro. La primera columna es el
# modulo de pkg-config (o el nombre del binario, para las herramientas), que es
# como se comprueba si YA esta: preguntar por el paquete no vale, porque se
# llaman distinto en cada sitio.
#
# En Arch las cabeceras van dentro del paquete normal; en Debian van aparte en
# un -dev. De ahi que las dos columnas no se parezcan.
#
#            comprobacion      debian                   arch
LIBRERIAS="
x11               libx11-dev               libx11
xinerama          libxinerama-dev          libxinerama
xrandr            libxrandr-dev            libxrandr
xcursor           libxcursor-dev           libxcursor
xi                libxi-dev                libxi
freetype2         libfreetype-dev          freetype2
libjpeg           libjpeg-turbo8-dev       libjpeg-turbo
openal            libopenal-dev            openal
gl                libgl-dev                libglvnd
glu               libglu1-mesa-dev         glu
zlib              zlib1g-dev               zlib
flac              libflac-dev              flac
ogg               libogg-dev               libogg
vorbis            libvorbis-dev            libvorbis
libudev           libudev-dev              systemd-libs
libarchive        libarchive-dev           libarchive
libcurl           libcurl4-openssl-dev     curl
libavformat       libavformat-dev          ffmpeg
libavcodec        libavcodec-dev           ffmpeg
libavutil         libavutil-dev            ffmpeg
libswscale        libswscale-dev           ffmpeg
libswresample     libswresample-dev        ffmpeg
"
HERRAMIENTAS="
git               git                      git
make              build-essential          base-devel
g++               build-essential          base-devel
pkg-config        pkg-config               base-devel
ffmpeg            ffmpeg                   ffmpeg
curl              curl                     curl
convert           imagemagick              imagemagick
"

# Donde guarda MAME cada cosa. NO se puede suponer: en Ubuntu el ini esta en
# ~/.mame/mame.ini y el bgfx junto al ejecutable, pero en GroovyArcade son
# ~/.mame/ini/mame.ini y /usr/lib/mame/bgfx. Se lo preguntamos a el.
mame_opcion() {   # $1=clave -> el valor, con $HOME ya expandido
	"$MAME" -showconfig 2>/dev/null |
		awk -v k="$1" '$1==k { $1=""; sub(/^ +/,""); print; exit }' |
		sed "s|\$HOME|$HOME|g"
}

# El mame.ini que manda es el primero del inipath.
mame_ini() {
	local rutas; rutas="$( mame_opcion inipath )"
	[ -n "$rutas" ] || { echo "$HOME/.mame/mame.ini"; return; }
	echo "${rutas%%;*}/mame.ini"
}

columna() {   # $1=arch|debian -> numero de campo
	[ "$GESTOR" = pacman ] && echo 3 || echo 2
}

# Lo que falta, ya traducido a nombres de paquete y sin repetidos.
paquetes_que_faltan() {
	local col; col=$( columna )
	{
		while read -r mod deb arch; do
			[ -n "$mod" ] || continue
			pkg-config --exists "$mod" 2>/dev/null && continue
			[ "$col" = 3 ] && echo "$arch" || echo "$deb"
		done <<< "$LIBRERIAS"
		while read -r bin deb arch; do
			[ -n "$bin" ] || continue
			command -v "$bin" >/dev/null 2>&1 && continue
			[ "$col" = 3 ] && echo "$arch" || echo "$deb"
		done <<< "$HERRAMIENTAS"
		# Y las que el emulador necesita para arrancar
		[ -n "${MAME:-}" ] && [ -x "${MAME:-}" ] && paquetes_del_emulador
	} | sort -u
}

# Las que necesita el EJECUTABLE del emulador para arrancar. No se detectan con
# pkg-config (eso mira cabeceras, y aqui hacen falta las .so de ejecucion): se
# detectan preguntandole al propio binario con ldd.
#
#     libSDL2_ttf-2.0.so.0: cannot open shared object file
#
# es lo que le paso a Eloy en Mint, y el sintoma es feo: MAME no arranca, el
# -listxml no devuelve nada y la lista de juegos sale sin un solo dato.
#           libreria                 debian                  arch
LIBRERIAS_EMULADOR="
libSDL2_ttf              libsdl2-ttf-2.0-0        sdl2_ttf
libSDL2-2.0              libsdl2-2.0-0            sdl2
libSDL2_image            libsdl2-image-2.0-0      sdl2_image
libfontconfig            libfontconfig1           fontconfig
libasound                libasound2t64            alsa-lib
libpulse                 libpulse0                libpulse
"

paquetes_del_emulador() {   # los que faltan para que el emulador arranque
	local col; col=$( columna )
	local faltantes; faltantes=$( ldd "$MAME" 2>/dev/null | awk '/not found/{print $1}' )
	[ -n "$faltantes" ] || return 0
	local lib
	while read -r pre deb arch; do
		[ -n "$pre" ] || continue
		if grep -q "^$pre" <<< "$faltantes"; then
			[ "$col" = 3 ] && echo "$arch" || echo "$deb"
		fi
	done <<< "$LIBRERIAS_EMULADOR" | sort -u
	# Las que no estan en la tabla se dicen por su nombre, que es mejor que
	# callarselas.
	while read -r lib; do
		[ -n "$lib" ] || continue
		grep -qE "^(${lib%%.*})" <<< "$( awk '{print $1}' <<< "$LIBRERIAS_EMULADOR" )" ||
			echo "# $lib" >&2
	done <<< "$faltantes"
}

instalar_paquetes() {   # $@ = paquetes
	case "$GESTOR" in
		pacman)
			# pacman aborta la instalacion ENTERA si un solo nombre no existe,
			# y perder las veinte por una no vale la pena. Se comprueban antes.
			# 'base-devel' es un grupo, no un paquete: -Si no lo ve, -Sg si.
			local -a buenos=() malos=() p
			for p in "$@"; do
				if pacman -Si "$p" >/dev/null 2>&1 || pacman -Sg "$p" >/dev/null 2>&1
				then buenos+=( "$p" ); else malos+=( "$p" ); fi
			done
			# Si NINGUNO aparece, lo que pasa es que la base de datos esta sin
			# sincronizar, no que esten todos mal: que hable pacman.
			if [ ${#buenos[@]} -eq 0 ]; then
				aviso "  la base de datos parece sin sincronizar, pruebo igual"
				sudo pacman -Sy --needed --noconfirm "$@"
			else
				[ ${#malos[@]} -gt 0 ] && aviso "  no estan en los repos: ${malos[*]}"
				sudo pacman -S --needed --noconfirm "${buenos[@]}"
			fi
			;;
		apt)    sudo apt-get update && sudo apt-get install -y "$@" ;;
		dnf)    sudo dnf install -y "$@" ;;
		*)      return 1 ;;
	esac
}

tarea_dependencias() {
	paso "Dependencias"
	# pkg-config puede no estar todavia; sin el no se puede comprobar nada mas.
	if ! command -v pkg-config >/dev/null; then
		aviso "  pkg-config no esta: lo instalo primero"
		case "$GESTOR" in
			pacman) sudo pacman -S --needed --noconfirm base-devel ;;
			apt)    sudo apt-get update && sudo apt-get install -y pkg-config ;;
			dnf)    sudo dnf install -y pkgconf-pkg-config ;;
		esac
	fi

	local faltan
	mapfile -t faltan < <( paquetes_que_faltan )
	if [ ${#faltan[@]} -eq 0 ]; then
		verde "  no falta nada"
		return 0
	fi

	echo "  faltan: ${faltan[*]}"
	if [ -z "$GESTOR" ]; then
		rojo "  No reconozco el gestor de paquetes: instalalos a mano."
		return 1
	fi
	if ! d_si "Dependencias" \
		"Faltan estos paquetes:\n\n${faltan[*]}\n\nSe instalan con sudo $GESTOR. Adelante?" si
	then
		aviso "  saltado: la compilacion fallara si falta algo"
		return 0
	fi

	instalar_paquetes "${faltan[@]}" || { rojo "  fallo la instalacion"; return 1; }

	# Volver a mirar: si algo sigue sin aparecer, el nombre del paquete estaba
	# mal para esta distro y hay que decirlo, no seguir y fallar al compilar.
	local siguen
	mapfile -t siguen < <( paquetes_que_faltan )
	if [ ${#siguen[@]} -gt 0 ]; then
		aviso "  siguen sin aparecer: ${siguen[*]}"
		aviso "  (puede que en esta distro se llamen de otra forma)"
	else
		verde "  todas las dependencias en su sitio"
	fi

	# La prueba de fuego: que el emulador arranque. Si no, el -listxml no
	# devuelve nada y la lista de juegos sale sin un solo dato, sin decir por
	# que -- que es exactamente lo que paso en Mint.
	if [ -x "$MAME" ] && ! "$MAME" -version >/dev/null 2>&1; then
		aviso "  OJO: el emulador no arranca:"
		"$MAME" -version 2>&1 | head -3 | sed 's/^/    /'
	fi
}

# ---------------------------------------------------------------- las tareas
tarea_compilar() {
	paso "Compilando Attract-Mode Plus"
	local n; n=$( nproc 2>/dev/null || echo 2 )
	# ccache y mold si estan: bajan la compilacion de unos 8 minutos a 2. Van
	# en la MISMA invocacion, no exportados antes, o no llegan al compilador.
	local -a envoltorio=()
	[ -d /usr/lib/ccache ] && envoltorio+=( env "PATH=/usr/lib/ccache:$PATH" )
	command -v mold >/dev/null && envoltorio+=( mold -run )
	( cd "$AQUI" && "${envoltorio[@]}" make -j"$n" )
}

# De donde se baja el emulador ya parcheado.
RELEASE="https://github.com/Kotaix0807/attractplus-creditos/releases/download/groovymame-0.289-cabina"

tarea_descargar() {
	paso "Bajando GroovyMAME ya parcheado"

	# Esta compilado en Ubuntu 24.04 y exige glibc 2.38 o mas. Con una anterior
	# el binario no arranca ni da un mensaje que se entienda, asi que se
	# comprueba ANTES de bajar 81 MB.
	local tengo
	tengo="$( ldd --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+$' )"
	if [ -n "$tengo" ] && ! printf '2.38\n%s\n' "$tengo" | sort -VC; then
		rojo "  este sistema tiene glibc $tengo y el binario exige 2.38 o mas"
		rojo "  aqui hay que compilarlo: marca la tarea 'mame'"
		return 1
	fi
	if [ "$ES_GROOVYARCADE" = 1 ]; then
		aviso "  OJO: GroovyArcade ya trae su GroovyMAME, compilado para ella y"
		aviso "  con switchres funcionando. Este de aqui viene de Ubuntu."
	fi

	local casa="$HOME/.local/share/groovymame-cabina"
	mkdir -p "$casa"
	local tmp; tmp="$( mktemp -d )"
	trap 'rm -rf "$tmp"' RETURN

	echo "  bajando el emulador (81 MB)..."
	curl -fL# -o "$tmp/mame.xz" "$RELEASE/groovymame-0.289-cabina.xz" || {
		rojo "  no se pudo bajar"; return 1; }
	echo "  bajando los shaders..."
	curl -fL# -o "$tmp/bgfx.tar.xz" "$RELEASE/bgfx-0.289-cabina.tar.xz" || {
		rojo "  no se pudieron bajar los shaders"; return 1; }

	xz -dc "$tmp/mame.xz" > "$casa/mame" && chmod +x "$casa/mame" || return 1
	# El bgfx va AL LADO del binario: MAME lo busca en "bgfx" relativo a su
	# directorio de trabajo, y el .cfg del emulador pone ahi el workdir.
	tar -xJf "$tmp/bgfx.tar.xz" -C "$casa" || return 1

	if ! "$casa/mame" -version >/dev/null 2>&1; then
		rojo "  se bajo pero no arranca:"
		"$casa/mame" -version 2>&1 | head -2 | sed 's/^/    /'
		rojo "  le faltan librerias del sistema; marca tambien la tarea 'deps'"
		return 1
	fi
	verde "  + $casa/mame  ($("$casa/mame" -version 2>&1 | head -1))"
	# El resto del instalador usa este
	MAME="$casa/mame"
}

tarea_mame() {
	paso "Parcheando y compilando GroovyMAME"
	local fuentes="$AQUI/../groovymame_src"
	if [ ! -d "$fuentes/src" ]; then
		aviso "  no encuentro las fuentes en $fuentes: me lo salto"
		aviso "  (en GroovyArcade el emulador ya viene con el sistema)"
		return 0
	fi
	local p
	for p in "$AQUI"/parches/*.patch; do
		echo "  aplicando $(basename "$p")"
		# -N: si ya estaba puesto, no lo pone dos veces ni se queja a gritos
		patch -d "$fuentes" -p1 -N -r - < "$p" || aviso "    (ya estaba puesto)"
	done
	local n; n=$( nproc 2>/dev/null || echo 2 )
	( cd "$fuentes" && env PATH=/usr/lib/ccache:$PATH make -j"$n" NOWERROR=1 USE_QTDEBUG=0 )
}

tarea_binario() {
	paso "Instalando el frontend en el sistema"
	if [ ! -x "$AQUI/attractplus" ]; then
		aviso "  no esta compilado todavia: me lo salto"
		return 0
	fi
	# gasetup lanza 'attractplus' del PATH, asi que el del sistema tiene que
	# ser el nuestro. En GroovyArcade ya hay uno en /usr/local/bin.
	local destino; destino="$( command -v attractplus 2>/dev/null || true )"
	[ "$destino" = "$AQUI/attractplus" ] && destino=""       # el del repo no vale
	destino="${destino:-/usr/local/bin/attractplus}"

	if [ -e "$destino" ] && [ "$destino" -ef "$AQUI/attractplus" ]; then
		verde "  $destino ya es el nuestro"
		return 0
	fi
	if [ -e "$destino" ] && [ ! -e "$destino.antes_instalar" ]; then
		sudo cp -a "$destino" "$destino.antes_instalar" &&
			echo "  el anterior queda en $destino.antes_instalar"
	fi
	sudo install -m 755 "$AQUI/attractplus" "$destino" && verde "  + $destino"
}

tarea_config() {
	paso "Instalando la configuracion"
	local MAMEDIR; MAMEDIR="$(dirname "$MAME")"

	mkdir -p "$DESTINO"/{config,plugins,emulators,layouts,romlists,scraper,modules}

	copiar_si_falta() {
		if [ -e "$2" ]; then echo "  = $(basename "$2") ya existe, no lo toco"
		else cp "$1" "$2" && echo "  + $(basename "$2")"; fi
	}
	respaldar() { [ -e "$1" ] && cp "$1" "$1.antes_instalar"; return 0; }

	# Todos, no solo los nuestros: los de serie de AM+ (KonamiCode, MultiMon...)
	# viven en el repo, y si el frontend no se instala en el sistema no hay otro
	# sitio donde los encuentre.
	for p in "$AQUI"/config/plugins/*.nut; do
		cp "$p" "$DESTINO/plugins/" && echo "  + plugins/$(basename "$p")"
	done

	rm -rf "$DESTINO/layouts/Arcade-UMAG"
	cp -r "$AQUI/config/layouts/Arcade-UMAG" "$DESTINO/layouts/" && echo "  + layouts/Arcade-UMAG"

	# Los modulos que usan los layouts (fade, animate...). Sin esto el layout
	# revienta con "the index 'FadeArt' does not exist", que no dice nada de que
	# el problema sea un modulo que falta.
	cp -r "$AQUI"/config/modules/. "$DESTINO/modules/" &&
		echo "  + $(ls "$DESTINO/modules" | wc -l) modulos"

	respaldar "$DESTINO/emulators/groovymame.cfg"
	sed -e "s|@MAMEDIR@|$MAMEDIR|g" -e "s|@CREDITOS@|$CREDITOS|g" -e "s|@ROMS@|$ROMS|g" \
		"$AQUI/config/cabina/groovymame.cfg" > "$DESTINO/emulators/groovymame.cfg"
	echo "  + emulators/groovymame.cfg (rutas de esta maquina)"

	respaldar "$DESTINO/config/plugins.cfg"
	sed -e "s|@CREDITOS@|$CREDITOS|g" "$AQUI/config/cabina/plugins.cfg" > "$DESTINO/config/plugins.cfg"
	echo "  + config/plugins.cfg"

	copiar_si_falta "$AQUI/config/cabina/displays.cfg" "$DESTINO/config/displays.cfg"
	copiar_si_falta "$AQUI/config/cabina/attract.cfg" "$DESTINO/config/attract.cfg"

	# AM+ busca su configuracion en ~/.attract y punto (fe_settings.cpp:54-60).
	# Si la cabina la tiene en otro sitio -- GroovyArcade la pone en
	# ~/shared/frontends/attract -- hay que enlazarla, o el frontend arrancara
	# con la configuracion por defecto e ignorara la cabina entera. Si gasetup
	# ya la pasa con --config, el enlace no estorba.
	if [ "$DESTINO" != "$HOME/.attract" ]; then
		if [ -L "$HOME/.attract" ]; then
			ln -sfn "$DESTINO" "$HOME/.attract"
			echo "  + ~/.attract -> $DESTINO"
		elif [ -e "$HOME/.attract" ]; then
			aviso "  ~/.attract ya existe y NO es un enlace: lo dejo como esta"
			aviso "  (si el frontend no ve esta configuracion, es por eso)"
		else
			ln -s "$DESTINO" "$HOME/.attract"
			echo "  + ~/.attract -> $DESTINO"
		fi
	fi
}

tarea_romlist() {
	paso "Construyendo la lista de juegos"
	if [ ! -x "$AQUI/attractplus" ]; then
		aviso "  el frontend no esta compilado todavia: me lo salto"
		return 0
	fi
	# Sin -o NO sobrescribe: crea groovymame1.txt, groovymame2.txt... y el
	# frontend sigue leyendo la vieja.
	( cd "$AQUI" && ./attractplus --build-romlist groovymame -o groovymame )
}

tarea_crt() {
	paso "Ajustando la salida de video para un CRT"

	local bgfx ini
	bgfx="$( mame_opcion bgfx_path )"
	ini="$( mame_ini )"
	echo "  bgfx: ${bgfx:-?}"
	echo "  ini:  $ini"

	if [ -n "$bgfx" ] && [ -d "$bgfx/chains" ]; then
		# En GroovyArcade el bgfx vive en /usr/lib/mame, que es de root.
		if [ -w "$bgfx/chains" ]; then
			cp "$AQUI/config/cabina/crt-real.json" "$bgfx/chains/"
		else
			sudo cp "$AQUI/config/cabina/crt-real.json" "$bgfx/chains/"
		fi
		echo "  + $bgfx/chains/crt-real.json"
	else
		aviso "  no encuentro $bgfx/chains: crt-real.json sin instalar"
	fi

	mkdir -p "$(dirname "$ini")"
	[ -f "$ini" ] && cp "$ini" "$ini.antes_instalar"
	poner_ini() {   # clave valor
		if [ -f "$ini" ] && grep -qE "^$1[[:space:]]" "$ini"; then
			sed -i -E "s|^($1[[:space:]]+).*|\1$2|" "$ini"
		else
			printf '%-25s %s\n' "$1" "$2" >> "$ini"
		fi
		echo "  $1 = $2"
	}
	poner_ini video              bgfx
	poner_ini bgfx_screen_chains crt-real
	poner_ini resolution         auto
	[ -n "$bgfx" ] && poner_ini bgfx_path "$bgfx"
	# switchres pisa keepaspect y scale_mode en cada arranque (autostretch).
	# OJO: en GroovyArcade con un monitor arcade de verdad SI hace su trabajo,
	# asi que ahi no se toca.
	if [ "$ES_GROOVYARCADE" = 1 ]; then
		aviso "  switchres se deja como esta: aqui si puede poner modelines"
	else
		poner_ini switchres 0
	fi
}

tarea_arte() {
	paso "Descargando artes"
	( cd "$AQUI" && ./attractplus --scrape-art groovymame )
	[ -x "$CREDITOS/aspecto.sh" ] && ( cd "$CREDITOS" && ./aspecto.sh )
}

tarea_videos() {
	paso "Grabando los videos de muestra (esto tarda unos 10 minutos)"
	( cd "$CREDITOS" && ./videos.sh )
}

# ---------------------------------------------------------------- el guion
d_aviso "Instalador de la cabina" \
"Esto deja la cabina lista en esta maquina.\n\n\
Distro:    $DISTRO\n\
Paquetes:  ${GESTOR:-no reconocido}\n\
Emulador:  ${MAME:-NO ENCONTRADO}\n\
Roms:      ${ROMS:-NO ENCONTRADAS}\n\
Creditos:  ${CREDITOS:-NO ENCONTRADO}\n\n\
En los pasos siguientes, Enter acepta siempre lo que sale por defecto."

# --- rutas ---
CREDITOS=$( d_texto "Repo de los creditos" \
"Donde esta el repo groovyarcade-creditos (creditos.lua, arranque.dat...).

Normalmente va al lado de este." "${CREDITOS:-$AQUI/../groovyarcade-creditos}" )
MAME=$( d_texto "Emulador" \
"Ruta del ejecutable de GroovyMAME.

En GroovyArcade suele ser /usr/bin/groovymame." "${MAME:-/usr/bin/groovymame}" )
ROMS=$( d_texto "Roms" "Carpeta con las roms." "${ROMS:-/usr/share/games/mame/roms}" )
DESTINO=$( d_texto "Configuracion" \
"Donde vive la configuracion de Attract-Mode." "$DESTINO" )

# --- comprobaciones: aqui se insiste, no se aborta ---
#
# Abortar deja al usuario con media instalacion y una linea de error. Se vuelve
# a preguntar tantas veces como haga falta, con el valor malo delante para que
# se vea que se escribio.
insistir() {   # $1=nombre de variable  $2=titulo  $3=mensaje  $4=comprobacion
	local -n valor="$1"
	local vueltas=0
	while ! "$4" "$valor"; do
		if ! hay_dialogo; then return 1; fi
		vueltas=$(( vueltas + 1 ))
		[ "$vueltas" -gt 10 ] && return 1     # por si alguien se atasca
		valor=$( d_texto "$2" "$3" "$valor" )
	done
	return 0
}

hay_creditos() { [ -f "$1/creditos.lua" ]; }
hay_emulador() { [ -x "$1" ]; }

# Con las roms no basta con que la carpeta exista. El token <DIR> de romext
# (el que hace que Street Fighter III, guardado en carpeta, aparezca) convierte
# CADA subcarpeta en un juego: apuntando al home salieron 36 "juegos" llamados
# .config, Descargas, .ssh... Asi que se comprueba que haya roms de verdad.
hay_roms() {
	[ -d "$1" ] || return 1
	compgen -G "$1/*.zip" >/dev/null && return 0
	compgen -G "$1/*.7z"  >/dev/null && return 0
	# o una carpeta con un .chd dentro, como los CPS3
	[ -n "$( find "$1" -maxdepth 2 -name '*.chd' -print -quit 2>/dev/null )" ]
}

if ! insistir CREDITOS "Repo de los creditos" \
"No encuentro creditos.lua ahi dentro.

Clona el repo groovyarcade-creditos al lado de este y escribe su ruta:" hay_creditos
then
	rojo "Sin el repo groovyarcade-creditos no puedo seguir: no hay plugins que instalar."
	echo "  git clone <groovyarcade-creditos> $AQUI/../groovyarcade-creditos"
	exit 1
fi

if ! insistir MAME "Emulador" \
"Ahi no hay ningun ejecutable.

Escribe la ruta del ejecutable de GroovyMAME (en GroovyArcade,
normalmente /usr/bin/groovymame):" hay_emulador
then
	rojo "Sin emulador no puedo escribir la configuracion de la cabina."
	exit 1
fi

# Las roms si se pueden dejar para luego: todo lo demas se instala igual.
SIN_ROMS=0
while ! hay_roms "$ROMS"; do
	if [ ! -d "${ROMS:-}" ]; then porque="no existe"
	else porque="existe, pero no tiene ningun .zip, .7z ni .chd dentro"; fi
	if ! hay_dialogo; then
		aviso "La carpeta de roms ($ROMS) $porque."
		SIN_ROMS=1; break
	fi
	ROMS=$( d_texto "Roms" \
"La carpeta

    ${ROMS:-(vacia)}

$porque.

Escribe donde estan las roms de verdad, o dejalo VACIO para seguir sin
ellas (se saltan la lista de juegos, los artes y los videos)." "" )
	[ -n "$ROMS" ] || { SIN_ROMS=1; break; }
done
if [ "$SIN_ROMS" = 1 ]; then
	# El .cfg del emulador necesita algo escrito. Si lo que hay no existe
	# siquiera, se pone la ruta de siempre: es mas util de leer luego que una
	# ruta inventada, y solo hay que corregir esa linea.
	[ -d "${ROMS:-}" ] || ROMS=/usr/share/games/mame/roms
	aviso "Sigo sin roms. En $DESTINO/emulators/groovymame.cfg queda"
	aviso "  rompath $ROMS  <- corrigelo cuando las tengas"
fi

# --- que hacer ---
compilar_por_defecto=ON
[ -x "$AQUI/attractplus" ] && compilar_por_defecto=OFF
# Instalar el binario en el sistema solo se da por hecho en GroovyArcade, que
# es donde gasetup lanza el del PATH y ese tiene que ser el nuestro.
binario_por_defecto=OFF
[ "$ES_GROOVYARCADE" = 1 ] && binario_por_defecto=ON

# El defecto cuando no hay dialogo: lo mismo que sale marcado en la lista.
# Se puede fijar por entorno, que es como se prueba sin ir tarea por tarea:
#   TAREAS="config romlist" ./instalar.sh --sin-preguntar
if [ -z "${TAREAS:-}" ]; then
	TAREAS="deps config romlist arte"
	[ "$compilar_por_defecto" = ON ] && TAREAS="deps compilar $TAREAS"
	[ "$binario_por_defecto"  = ON ] && TAREAS="$TAREAS binario"
	FIJADAS=0
else
	FIJADAS=1
fi
if [ "$FIJADAS" = 0 ] && hay_dialogo; then
	seleccion=$( whiptail --title "Que quieres que haga" --notags \
		--checklist "Espacio marca y desmarca, Enter confirma." 20 74 8 \
		deps     "Instalar las dependencias que falten"          ON \
		compilar "Compilar Attract-Mode Plus"                    $compilar_por_defecto \
		binario  "Instalarlo en el sistema (lo que lanza gasetup)" $binario_por_defecto \
		config   "Instalar plugins, layout y configuracion"      ON \
		romlist  "Construir la lista de juegos"                  ON \
		arte     "Descargar marquesinas y capturas"              ON \
		crt      "La pantalla es un CRT: ajustar el shader"      OFF \
		descargar "Bajar GroovyMAME ya parcheado (81 MB, sin compilar)" OFF \
		mame     "Parchear y compilar GroovyMAME (largo)"        OFF \
		videos   "Grabar los videos de muestra (~10 min)"        OFF \
		3>&1 1>&2 2>&3 ) && TAREAS="${seleccion//\"/}"
fi
# Sin roms no hay lista de juegos, ni artes que emparejar, ni videos que grabar.
if [ "$SIN_ROMS" = 1 ]; then
	TAREAS="$( tr ' ' '\n' <<< "$TAREAS" | grep -vE '^(romlist|arte|videos)$' | tr '\n' ' ' )"
fi

echo
echo "Tareas: $TAREAS"

hace() { [[ " $TAREAS " == *" $1 "* ]]; }

# --- a trabajar ---
# El orden importa: dependencias antes de compilar, compilar antes de la lista.
fallos=0
hace deps     && { tarea_dependencias || fallos=$((fallos+1)); }
hace compilar && { tarea_compilar     || fallos=$((fallos+1)); }
hace binario  && { tarea_binario      || fallos=$((fallos+1)); }
hace descargar && { tarea_descargar  || fallos=$((fallos+1)); }
hace mame      && { tarea_mame       || fallos=$((fallos+1)); }
hace config   && { tarea_config       || fallos=$((fallos+1)); }
hace crt      && { tarea_crt          || fallos=$((fallos+1)); }
hace romlist  && { tarea_romlist      || fallos=$((fallos+1)); }
hace arte     && { tarea_arte         || fallos=$((fallos+1)); }
hace videos   && { tarea_videos       || fallos=$((fallos+1)); }

# ---------------------------------------------------------------- revision
# Las tres cosas que fallaron de verdad en la maquina de pruebas y que no dan
# la cara hasta mucho despues.
paso "Revision"

if [ -x "$MAME" ] && "$MAME" -version >/dev/null 2>&1; then
	verde "  el emulador arranca"
else
	rojo  "  el emulador NO arranca:"
	"$MAME" -version 2>&1 | head -2 | sed 's/^/    /'
	rojo  "  sin esto el -listxml no devuelve nada y la lista sale vacia de datos"
fi

lista="$DESTINO/romlists/groovymame.txt"
if [ -s "$lista" ]; then
	n=$(( $(wc -l < "$lista") - 1 ))
	# Si el emulador no arranco, la lista tiene nombres pero ningun dato: se
	# nota en que la segunda columna (el titulo) es igual que la primera.
	sin_datos=$( awk -F';' 'NR>1 && $1==$2' "$lista" | wc -l )
	if [ "$sin_datos" -gt 0 ]; then
		aviso "  la lista tiene $n juegos pero $sin_datos sin datos (falta el -listxml)"
	else
		verde "  la lista tiene $n juegos"
	fi
else
	aviso "  no hay lista de juegos todavia"
fi

if [ "$ES_GROOVYARCADE" = 1 ] && [ -f "$GA_CONF" ]; then
	fe="$( ga_valor frontend )"
	if [ "$fe" = attractplus ]; then
		verde "  gasetup lanza 'attractplus': es el nombre de nuestro binario"
	else
		aviso "  gasetup lanza '$fe', no 'attractplus'"
		aviso "  cambialo en gasetup > Setup, o el nuestro no se usara"
	fi
	# monitor=lcd es lo que viene de fabrica, y con eso switchres NO genera
	# modelines de recreativa: se queda en las resoluciones del panel.
	mon="$( ga_valor monitor )"
	if hace crt && [ "$mon" = lcd ]; then
		aviso "  gasetup tiene monitor=lcd: switchres no hara modelines de CRT"
		aviso "  ponlo en gasetup > Setup (video) segun tu monitor (arcade_15, generic_15...)"
		aviso "  y revisa connector=$( ga_valor connector ), que ahi apunta al panel interno"
	fi
fi

sistema="$( command -v attractplus 2>/dev/null || true )"
if [ -n "$sistema" ] && [ "$sistema" != "$AQUI/attractplus" ]; then
	if [ "$sistema" -ef "$AQUI/attractplus" ]; then
		verde "  el frontend del sistema es el nuestro ($sistema)"
	else
		aviso "  OJO: $sistema NO es el nuestro"
		aviso "  gasetup lanzara ese, no el de este repo (marca la tarea 'binario')"
	fi
fi
if [ "$DESTINO" != "$HOME/.attract" ] && [ ! -L "$HOME/.attract" ]; then
	aviso "  ~/.attract no apunta a $DESTINO: el frontend puede no ver la cabina"
fi

if [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
	verde "  hay sesion grafica"
else
	# AM+ aqui no avisa: aborta con un volcado de memoria y una sola linea.
	aviso "  no hay sesion grafica (DISPLAY y WAYLAND_DISPLAY vacios)"
	aviso "  el frontend abortara con 'Failed to open X11 display'"
fi

# ---------------------------------------------------------------- el final
paso "Listo"
pendiente=""
[ -x "$AQUI/attractplus" ] || pendiente+="- El frontend no esta compilado: cd $AQUI && make -j\$(nproc)\n"
hace romlist || pendiente+="- La lista de juegos: ./attractplus --build-romlist groovymame -o groovymame\n"
hace videos  || pendiente+="- Los videos de muestra: cd $CREDITOS && ./videos.sh\n"

# Esto no lo puede hacer el script: hay que estar delante de la cabina.
pendiente+="- Mapear el boton de moneda: entra a un juego, pulsa Tab >\n"
pendiente+="  Input Settings > Input Assignments (General) > Coin 1.\n"
pendiente+="  Hazlo en el general, NO por juego: un mapeo propio del juego\n"
pendiente+="  deja el cerrojo del monedero sin efecto.\n"
pendiente+="- Si quieres el menu de ajustes de arranque, la tecla en\n"
pendiente+="  Configure > Plug-ins > Arranque.\n"

if [ "$fallos" -gt 0 ]; then
	rojo "Termino con $fallos paso(s) fallidos: mira lo de arriba."
else
	verde "Instalado."
fi
echo
d_aviso "Queda por hacer" "$pendiente"
