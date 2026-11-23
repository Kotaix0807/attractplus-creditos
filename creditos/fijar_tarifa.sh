#!/bin/bash
# Fija la tarifa de UN juego a un precio por jugada en pesos.
#
#   ./fijar_tarifa.sh pacman 200      # $200 por jugada = 2 monedas/credito
#
# La cabina usa monedas de $100, asi que pesos/100 = monedas por credito.  Arranca
# el juego dos segundos, cambia el DIP de tarifa y sale; MAME guarda el .cfg.
# Lo usa el panel web (panel/acciones.py, juego_tarifa).
#
# OJO: para que una tarifa distinta de $100 PERSISTA, la cabina tiene que lanzar
# creditos.lua con GA_TARIFA=auto; con el 1c1c por defecto se vuelve a forzar 1
# moneda/credito en cada arranque.  Ver docs/panel.md.
#
# Variables:
#   VALOR_MONEDA  pesos por moneda (por defecto 100)
#   MAME_DIR      carpeta del ejecutable (si no, lo busca comun.sh: ver preparar_mame)
#   ROMPATH       donde estan las roms     (por defecto la que declare MAME)
#   MAME_EXTRA    opciones extra para MAME

set -u

if [ $# -lt 2 ]; then
	echo "uso: $0 <juego> <pesos>" >&2
	exit 2
fi
juego="$1"; pesos="$2"
valor_moneda="${VALOR_MONEDA:-100}"

case "$pesos" in (*[!0-9]*|'') echo "pesos debe ser un numero" >&2; exit 2;; esac
if [ "$(( pesos % valor_moneda ))" -ne 0 ] || [ "$pesos" -lt "$valor_moneda" ]; then
	echo "pesos ($pesos) debe ser multiplo de la moneda ($valor_moneda) y >= $valor_moneda" >&2
	exit 2
fi
monedas=$(( pesos / valor_moneda ))

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$AQUI/comun.sh"
preparar_mame
ROMPATH="$( rompath_de "$MAME_BIN" )"
MAME_EXTRA="${MAME_EXTRA:-}"

LANZA=()
if [ -z "${DISPLAY:-}" ] && command -v xvfb-run >/dev/null; then
	LANZA=( xvfb-run -a )
fi

salida=$( cd "$MAME_DIR" && GA_FIJAR_MONEDAS="$monedas" "${LANZA[@]}" "$MAME_BIN" "$juego" \
	-rompath "$ROMPATH" $MAME_EXTRA \
	-video none -sound none -nothrottle -noswitchres -seconds_to_run 2 \
	-autoboot_script "$AQUI/fijar_tarifa.lua" -autoboot_delay 1 2>&1 )

linea=$( echo "$salida" | grep '^TARIFA ' | head -1 )
if [ -z "$linea" ]; then
	echo "ERROR juego=$juego   $(echo "$salida" | grep -iE 'error|not found' | head -1)"
	exit 1
fi
echo "$linea"
case "$linea" in
	*estado=cambiado*|*estado=ya-estaba*) exit 0 ;;
	*) exit 1 ;;
esac
