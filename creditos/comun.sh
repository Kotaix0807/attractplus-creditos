# Trozos que comparten los scripts de creditos/. No se ejecuta suelto: se
# carga con `. "$AQUI/comun.sh"` (o ../comun.sh desde pruebas/).
#
# Lo unico que hay aqui de momento es la ruta de las roms, y esta aqui porque
# suponerla es un fallo de portabilidad: /usr/share/games/mame/roms solo
# existe en Debian y derivados. En Arch no, y en GroovyArcade es
# ~/shared/roms/mame. La forma buena es preguntarsela al emulador, que es
# quien sabe cual de sus mame.ini manda.

# $1 = clave de configuracion, $2 = binario de MAME -> el valor, o vacio
mame_opcion() {
	local clave="$1" bin="$2"
	[ -x "$bin" ] || return 0
	"$bin" -showconfig 2>/dev/null |
		sed -n "s/^$clave[[:space:]]\+//p" | head -1
}

# $1 = binario de MAME -> donde estan las roms.
# Precedencia: ROMPATH del entorno > lo que diga MAME > el defecto de Debian.
rompath_de() {
	local bin="$1" r="${ROMPATH:-}"
	[ -n "$r" ] || r="$( mame_opcion rompath "$bin" )"
	[ -n "$r" ] || r=/usr/share/games/mame/roms
	# -showconfig devuelve el valor CRUDO del ini, asi que puede traer un
	# $HOME literal (en GroovyArcade el rompath es "$HOME/shared/roms/mame").
	# MAME sabe expandirlo; nosotros comprobamos el directorio, asi que se
	# expande aqui tambien.
	r="${r//\$HOME/$HOME}"
	r="${r//\$\{HOME\}/$HOME}"
	r="${r/#\~/$HOME}"
	# MAME admite varias rutas separadas por ";". Nos quedamos con la primera
	# que exista de verdad, y si ninguna existe, con la primera a secas.
	local trozo
	while IFS= read -r trozo; do
		[ -d "$trozo" ] && { echo "$trozo"; return; }
	done <<< "${r//;/$'\n'}"
	echo "${r%%;*}"
}
