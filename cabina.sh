#!/bin/bash
# Arranca el frontend en el CRT y devuelve el escritorio al salir.
#
# El CRT se queda como UNICA pantalla mientras dura la sesion de juego.  No es
# capricho: bajo GNOME Wayland el gestor de ventanas decide donde va cada
# ventana y no hace caso al cliente X, asi que la unica forma de garantizar que
# Attract-Mode cae en el CRT es que no haya otro sitio donde caer.
#
# En una sesion Xorg esto no haria falta, pero tampoco estorba.
set -u
cd "$( dirname "$( readlink -f "$0" )" )"

# Sin sesion grafica, AM+ no avisa: aborta con un volcado de memoria y una sola
# linea ("Failed to open X11 display"). Mejor decirlo aqui, con la causa.
if [ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
	echo "No hay sesion grafica: DISPLAY y WAYLAND_DISPLAY estan vacios." >&2
	echo >&2
	echo "  - Si estas en una consola de texto (Ctrl+Alt+F3), vuelve a la" >&2
	echo "    grafica con Ctrl+Alt+F1 o F2." >&2
	echo "  - Si entraste por ssh, DISPLAY no viaja solo: prueba 'ssh -X'." >&2
	echo "  - Si es una sesion Wayland sin Xwayland, el frontend no puede" >&2
	echo "    correr: hace falta una sesion Xorg." >&2
	exit 1
fi

restaurar() { ./pantalla.py escritorio; }
trap restaurar EXIT INT TERM

./pantalla.py cabina || exit 1
sleep 1
./attractplus "$@"
