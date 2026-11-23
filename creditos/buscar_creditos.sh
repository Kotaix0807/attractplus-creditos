#!/bin/bash
# Recorre los juegos buscando donde guarda cada uno sus creditos, y escribe lo
# encontrado en creditos.dat.nuevo. Es una pasada de calibracion: se hace una vez
# por juego, como poner_1c1c.sh.
#
# NO escribe en creditos.dat: ese fichero lleva ~5000 direcciones importadas y las
# marcas bcd/(cheat) que esta pasada no conoce, y antes se perdian todas. Lo nuevo
# hay que fundirlo a mano, juego a juego. SALIDA= cambia el destino.
#
#   ./buscar_creditos.sh                 # todas las roms de ROMPATH
#   ./buscar_creditos.sh pacman dkong    # solo esos
#
# El fichero resultante tiene el mismo espiritu que el hiscore.dat de MAME:
#   pacman @:maincpu,program,4e6e
set -u

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

. "$AQUI/comun.sh"
preparar_mame
ROMPATH="$( rompath_de "$MAME_BIN" )"
SALIDA="${SALIDA:-$AQUI/creditos.dat.nuevo}"
MAME_EXTRA="${MAME_EXTRA:-}"


juegos=( "$@" )
if [ ${#juegos[@]} -eq 0 ]; then
	mapfile -t juegos < <( listar_roms "$ROMPATH" )
fi

LANZA=()
if [ -z "${DISPLAY:-}" ] && command -v xvfb-run >/dev/null; then LANZA=( xvfb-run -a ); fi

OPC_CFG=()
[ -n "${CFG_DIR:-}" ] && OPC_CFG=( -cfg_directory "$CFG_DIR" )

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

echo "# ${#juegos[@]} juegos; esto tarda ~15 s por juego"
encontrados=0; fallidos=0

for j in "${juegos[@]}"; do
	salida=$( cd "$MAME_DIR" && "${LANZA[@]}" "$MAME_BIN" "$j" \
		-rompath "$ROMPATH" "${OPC_CFG[@]}" $MAME_EXTRA \
		-video none -sound none -nothrottle -noswitchres -seconds_to_run 60 \
		-autoboot_script "$AQUI/buscar_creditos.lua" -autoboot_delay 6 2>&1 )

	# La linea buena es la ultima: antes va la de "probando"
	linea=$( echo "$salida" | grep '^CREDITOS ' | tail -1 )
	if [ -z "$linea" ]; then
		echo "  $j: no arranco"
		fallidos=$((fallidos+1))
		continue
	fi

	echo "  $linea"
	dir=$( echo "$linea" | sed -n 's/.* dir=\([0-9a-f+]*\) .*/\1/p' )
	cpu=$( echo "$linea" | sed -n 's/.* cpu=\([^ ]*\) .*/\1/p' )
	if [ -n "$dir" ]; then
		echo "$j @${cpu:-:maincpu},program,$dir" >> "$TMP"
		encontrados=$((encontrados+1))
	else
		fallidos=$((fallidos+1))
	fi
done

{
	echo "# creditos.dat - donde guarda cada juego su contador de creditos."
	echo "# Generado por buscar_creditos.sh; formato: <juego> @<cpu>,<espacio>,<direccion>"
	echo "# Se encontro mirando que byte de la RAM sube al meter una moneda y baja al"
	echo "# pulsar START. Si un juego da problemas, borra su linea y volvera a la"
	echo "# estimacion por pulsaciones de START."
	sort "$TMP" 2>/dev/null
} > "$SALIDA"

echo "# encontrados=$encontrados fallidos=$fallidos -> $SALIDA"
echo "# (creditos.dat no se ha tocado: funde a mano las lineas que quieras)"
