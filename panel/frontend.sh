#!/bin/bash
# Supervisor del frontend, para que el panel pueda reiniciarlo y pararlo.
#
# En vez de lanzar 'attractplus' a secas, la cabina lo lanza a traves de este
# bucle.  Asi:
#   * "Reiniciar frontend" (pkill -x attractplus) -> el bucle lo vuelve a lanzar.
#   * "Modo mantenimiento" -> mientras exista ~/.attract/mantenimiento, el bucle
#     NO lanza el frontend (queda la sesion X limpia para trabajar en remoto).
#   * "Detener Attract-Plus" -> igual, con ~/.attract/frontend_detenido (es otro
#     centinela: parar el frontend SIN abrir la ventana de gestion de juegos).
#
# Como enchufarlo (en la cabina, con el frontend parado): donde el arranque
# lanza el frontend (p.ej. /opt/galauncher/startfe-X.sh hace 'exec attractplus'),
# se cambia por 'exec .../panel/frontend.sh'.  instalar.sh (tarea panel) lo
# explica; no reescribe la cadena de arranque de GroovyArcade por su cuenta.
#
# Variables:
#   FE_BIN   el binario del frontend (por defecto, el primero que exista de la
#            lista de abajo)
#   FRENO    fichero centinela de mantenimiento (~/.attract/mantenimiento)

set -u

FRENO="${FRENO:-$HOME/.attract/mantenimiento}"
DETENIDO="${DETENIDO:-$HOME/.attract/frontend_detenido}"

elegir_fe() {
	local c
	for c in "${FE_BIN:-}" attractplus attractplus-x11 attractplus-kms; do
		[ -n "$c" ] && command -v "$c" >/dev/null 2>&1 && { echo "$c"; return; }
	done
	echo attractplus   # ultimo recurso; que falle diciendo que no esta
}

FE="$( elegir_fe )"

while true; do
	if [ -f "$FRENO" ] || [ -f "$DETENIDO" ]; then
		sleep 2
		continue
	fi
	# Lanza el frontend y espera a que termine (lo mate el panel o salga solo).
	"$FE" "$@"
	# Pausa corta para no entrar en un bucle cerrado si el binario revienta al
	# instante (p.ej. falta la pantalla); da tiempo a meter el freno.
	sleep 1
done
