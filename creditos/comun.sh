# Trozos que comparten los scripts de creditos/. No se ejecuta suelto: se
# carga con `. "$AQUI/comun.sh"` (o ../comun.sh desde pruebas/).
#
# Lo unico que hay aqui de momento es la ruta de las roms, y esta aqui porque
# suponerla es un fallo de portabilidad: /usr/share/games/mame/roms solo
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
