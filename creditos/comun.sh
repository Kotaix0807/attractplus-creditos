# Trozos que comparten los scripts de creditos/. No se ejecuta suelto: se
# carga con `. "$AQUI/comun.sh"` (o ../comun.sh desde pruebas/).
#
# Dos cosas: donde esta el emulador y donde estan las roms. Las dos estan aqui
# porque suponerlas es un fallo de portabilidad. Las roms: /usr/share/games/mame/roms solo
# existe en Debian y derivados. En Arch no, y en GroovyArcade es
# ~/shared/roms/mame. La forma buena es preguntarsela al emulador, que es
# quien sabe cual de sus mame.ini manda. Es la misma tecnica que usa
# instalar.sh con mame_opcion(), y esta documentada en CLAUDE.md.

# $1 = clave de configuracion, $2 = binario de MAME -> el valor, o vacio
mame_opcion() {
	local clave="$1" bin="$2"
	[ -x "$bin" ] || return 0
	"$bin" -showconfig 2>/dev/null |
		sed -n "s/^$clave[[:space:]]\+//p" | head -1
}

# $1 = binario de MAME -> el rompath ENTERO, tal cual se le pasa a -rompath.
#
# Ojo: son VARIAS rutas separadas por ";", no una. En esta maquina MAME declara
#   $HOME/mame/roms;/usr/local/share/games/mame/roms;/usr/share/games/mame/roms
# y las roms de verdad estan en la tercera. Quedarse con la primera que exista
# es un error silencioso: se encontrarian 11 juegos en vez de 104. Asi que se
# devuelven todas y es MAME quien busca en ellas, que para eso las declara.
#
# Precedencia: ROMPATH del entorno > lo que diga MAME > el defecto de Debian.
rompath_de() {
	local bin="$1" r="${ROMPATH:-}"
	[ -n "$r" ] || r="$( mame_opcion rompath "$bin" )"
	[ -n "$r" ] || r=/usr/share/games/mame/roms
	# -showconfig devuelve el valor CRUDO del ini, asi que puede traer un
	# $HOME literal (en GroovyArcade el rompath es "$HOME/shared/roms/mame").
	# MAME sabe expandirlo; nosotros comprobamos los directorios, asi que se
	# expande aqui tambien.
	r="${r//\$HOME/$HOME}"
	r="${r//\$\{HOME\}/$HOME}"
	r="${r/#\~/$HOME}"
	echo "$r"
}

# $1 = rompath (una o varias rutas con ";") -> los directorios que EXISTEN,
# uno por linea. Es lo que necesitan los `find` que enumeran las roms.
dirs_de_rompath() {
	local trozo
	while IFS= read -r trozo; do
		[ -n "$trozo" ] && [ -d "$trozo" ] && echo "$trozo"
	done <<< "${1//;/$'\n'}"
}

# $1 = rompath -> los nombres de set que hay, sin extension y sin repetir.
listar_roms() {
	local dirs; mapfile -t dirs < <( dirs_de_rompath "$1" )
	[ ${#dirs[@]} -gt 0 ] || return 0
	find "${dirs[@]}" -maxdepth 1 -type f \
		\( -name '*.zip' -o -name '*.7z' \) -printf '%f\n' 2>/dev/null |
		sed 's/\.[^.]*$//' | sort -u
}

# --- Donde esta el emulador -------------------------------------------------
#
# En una maquina de desarrollo el emulador esta en el arbol de fuentes
# (groovymame_src/mame), que puede estar al lado del repo o en $HOME. En la
# cabina GroovyArcade NO hay tal arbol: el binario esta instalado (el nuestro en
# ~/.local/share/groovymame-cabina, el de la distro en el PATH). Antes cada
# script tenia su propia lista y la mitad solo miraba groovymame_src, asi que en
# la cabina fallaban con "no encuentro /mame" (fijar_tarifa.sh, 2026-11-22).
#
# Orden: MAME_DIR= o MAME= del entorno > nuestra compilacion de la cabina >
# arbol de fuentes > groovymame o mame del PATH.

_COMUN_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# $1 = fichero que debe haber dentro, $2.. = directorios candidatos -> el primero
vecino() {
	local marca="$1"; shift
	local c
	for c in "$@"; do
		[ -e "$c/$marca" ] && { ( cd "$c" && pwd ); return 0; }
	done
	return 1
}

# -> la ruta del binario de MAME, o falla
buscar_mame() {
	local c fuentes
	fuentes="$( vecino mame "$_COMUN_DIR/../../groovymame_src" \
		"$_COMUN_DIR/../groovymame_src" "$HOME/groovymame_src" 2>/dev/null )"
	for c in "${MAME_DIR:+$MAME_DIR/mame}" "${MAME:-}" \
		"$HOME/.local/share/groovymame-cabina/mame" \
		${fuentes:+"$fuentes/mame"} \
		"$( command -v groovymame 2>/dev/null )" \
		"$( command -v mame 2>/dev/null )"
	do
		[ -n "$c" ] && [ -x "$c" ] && { echo "$c"; return 0; }
	done
	return 1
}

# Deja MAME_BIN (el binario) y MAME_DIR (su carpeta), o sale con la ayuda.
# Se lanza siempre desde MAME_DIR: nuestra compilacion lleva al lado su bgfx y
# sus plugins, igual que hace el frontend con 'workdir'.
preparar_mame() {
	MAME_BIN="$( buscar_mame )" || {
		echo "no encuentro el emulador. Lo busco, por este orden, en:" >&2
		echo "  \$MAME_DIR/mame o \$MAME (variables de entorno)" >&2
		echo "  ~/.local/share/groovymame-cabina/mame" >&2
		echo "  groovymame_src/mame (al lado del repo o en \$HOME)" >&2
		echo "  groovymame o mame en el PATH" >&2
		echo "Lanzalo asi:  MAME=/ruta/al/mame $0 ..." >&2
		exit 1
	}
	MAME_DIR="$( cd "$( dirname "$MAME_BIN" )" && pwd )"
}
