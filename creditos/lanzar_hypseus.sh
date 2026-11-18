#!/bin/sh
# Lanza Hypseus (laserdisc) preparando lo que con MAME hace creditos.lua:
#
#  - LEDs: escribe botones_juego para que el demonio del panel (moneyBank.py)
#    encienda solo esos botones. De vldp/<juego>/botones si existe (p.ej. "1 2");
#    si no, "1" -- Dragon's Lair y Space Ace usan solo la espada.
#  - Ranura de monedas: deja monedero_switch en 0 (cerrada) y le pide a Hypseus
#    (HYPSEUS_LISTO, parche parches/hypseus-cabina.patch) que escriba 1 cuando la
#    placa termine de arrancar. Antes de eso una moneda se perderia.
#  - Free play: si la tarifa del juego (tarifa_juego/<juego>, o si no la global
#    tarifa_global, las del panel) es freeplay, anade vldp/<juego>/args_freeplay
#    (el DIP de free play de esa ROM) y la ranura no se abre nunca. Hypseus se
#    queda con el ultimo -bank, asi que este manda sobre el de vldp/<juego>/args.
#    Las tarifas en pesos no se aplican aqui: cada ROM tiene sus propios DIP.
#
# Uso (desde hypseus.cfg de AM+): lanzar_hypseus.sh <juego> <resto de args de hypseus>
HY=${HYPSEUS_DIR:-/home/arcade/hypseus-singe}
AT=${GA_ATTRACT_DIR:-$HOME/.attract}
juego=$1

# temporal + rename: el demonio relee estos ficheros y nunca debe verlos a medias
escribir() { printf '%s' "$2" > "$1.tmp" && mv "$1.tmp" "$1"; }

escribir "$AT/botones_juego" "$(cat "$HY/vldp/$juego/botones" 2>/dev/null || echo 1)"
escribir "$AT/monedero_switch" 0
# Para el panel: que juego corre (set<TAB>titulo, como creditos.lua; el titulo
# de la lista de juegos de AM+), y fuera las ordenes que quedaran de MAME:
# panel_cmd solo lo lee creditos.lua, y aqui el panel manda teclas (acciones.py).
titulo=$(awk -F';' -v j="$juego" '$1==j {print $2; exit}' "$AT/romlists/groovymame.txt" 2>/dev/null)
escribir "$AT/juego_actual" "$(printf '%s\t%s' "$juego" "${titulo:-$juego}")"
rm -f "$AT/panel_cmd"

tarifa=$(head -n1 "$AT/tarifa_juego/$juego" 2>/dev/null || head -n1 "$AT/tarifa_global" 2>/dev/null)
tarifa=$(printf '%s' "$tarifa" | tr -d ' \t\r' | tr 'A-Z' 'a-z')

extra=""
if [ "$tarifa" = freeplay ] || [ "$tarifa" = free ]; then
	extra=$(cat "$HY/vldp/$juego/args_freeplay" 2>/dev/null)
	unset HYPSEUS_LISTO
else
	export HYPSEUS_LISTO="$AT/monedero_switch"
fi

# $extra sin comillas a proposito: son varias palabras (-bank 0 ...)
exec "$HY/hypseus" "$@" $extra
