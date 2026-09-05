#!/bin/bash
# Pruebas de las dos mitades del sistema de creditos, sin necesidad de tener
# Attract-Mode Plus compilado:
#
#   * pruebas.nut       ejercita el plugin Squirrel contra maqueta.nut, una
#                       imitacion de la API de AM+ hecha a partir de src/ y
#                       Layouts.md. Corre en sqhost, un interprete minimo
#                       construido con las MISMAS fuentes de Squirrel 3.0.7
#                       que compila AM+ (attractplus/extlibs/squirrel).
#   * prueba_tarifa.lua ejercita el analizador de DIP de tarifa con cadenas
#                       reales sacadas de MAME.
#   * prueba_monedero.lua ejercita la contabilidad del monedero compartido:
#                       formatos del fichero, escritura atomica y el vigilante
#                       del boton de moneda.
#   * prueba_aviso.lua  ejercita el cuadro de aviso: la estimacion de lo que hay
#                       dentro y la maquina de estados del dialogo.
#   * prueba_ajustes.lua ejercita los ajustes por juego de arranque.dat.
#   * prueba_cerrojo.lua ejercita el cerrojo del boton de moneda: que el
#     jugador no pueda meter mas monedas que creditos tiene.
#   * prueba_memoria.lua ejercita la lectura de creditos de la RAM del juego:
#                       la tabla creditos.dat y el reparto de subidas y bajadas.
#
# Las dos partes que necesitan emulador o frontend estan aparte:
#   ./integracion.sh   AM+ + GroovyMAME de punta a punta
#   ./aviso_mame.sh    el cuadro de aviso dentro de MAME de verdad
#
# Lo que NO cubren: el propio AM+ en marcha. Para eso hace falta compilarlo.
set -eu
cd "$(dirname "${BASH_SOURCE[0]}")"

# creditos/ esta dentro de attractplus, asi que squirrel queda dos
# niveles arriba. Si los repos estuvieran al lado, seria ../../attractplus.
SQ=${SQ:-$( [ -d ../../extlibs/squirrel ] && echo ../../extlibs/squirrel \
                                          || echo ../../attractplus/extlibs/squirrel )}

if [ ! -x ./sqhost ] || [ sqhost.cpp -nt ./sqhost ]; then
	echo "# compilando sqhost..."
	g++ -O0 -w -I "$SQ/include" -I "$SQ/squirrel" -I "$SQ/sqstdlib" \
		-o sqhost sqhost.cpp "$SQ"/squirrel/*.cpp "$SQ"/sqstdlib/*.cpp
fi

echo "### plugin Creditos.nut ###"
./sqhost pruebas.nut

LUA=""
for l in lua5.4 lua5.3 lua; do
	if command -v $l >/dev/null; then LUA=$l; break; fi
done
if [ -z "$LUA" ]; then echo "no encuentro un interprete de lua" >&2; exit 1; fi

echo
echo "### analizador de tarifas ###"
$LUA prueba_tarifa.lua

echo
echo "### monedero compartido ###"
$LUA prueba_monedero.lua

echo
echo "### cuadro de aviso ###"
$LUA prueba_aviso.lua

echo
echo "### creditos leidos de la memoria ###"
$LUA prueba_memoria.lua

echo
echo "### editor de ajustes en la cabina (plugin Arranque) ###"
./sqhost prueba_arranque.nut

echo
echo "### ajustes de arranque por juego ###"
$LUA prueba_ajustes.lua

echo
echo "### cerrojo del boton de moneda ###"
$LUA prueba_cerrojo.lua

echo
echo "### importador de la coleccion de cheats ###"
./prueba_importar.sh

# --- compatibilidad con Lua 5.5 --------------------------------------------
#
# La cabina tiene DOS binarios de MAME con Lua distinta: el nuestro lleva 5.4 y
# el de la distro 5.5. En 5.5 la variable de control de un 'for' es CONST, asi
# que asignarle valor es un error de COMPILACION y el fichero entero deja de
# cargar:
#
#     for linea in f:lines() do
#         linea = linea:gsub(...)     -- revienta con 5.5, pasa con 5.4
#
# Le paso a ajustes.lua y es MUDO: probando con 5.4 no se ve. Esta comprobacion
# es gratis y lo caza. Se salta -- avisando -- si el luac de la maquina no es de
# 5.5, para no romper la tanda donde no se pueda comprobar.
echo
echo "### compatibilidad con Lua 5.5 ###"
LUAC=""
for c in luac5.5 luac; do
	if command -v $c >/dev/null && $c -v 2>&1 | grep -q "Lua 5\.5"; then
		LUAC=$c; break
	fi
done
if [ -z "$LUAC" ]; then
	echo "  sin luac de 5.5 en esta maquina: me la salto"
	echo "  (en la cabina si lo hay: 'lua -v' dice 5.5.1)"
else
	fallos_lua=0
	for f in ../*.lua; do
		if $LUAC -p "$f" 2>/tmp/luac_err.$$; then
			echo "  ok   $(basename "$f")"
		else
			echo "  FALLA $(basename "$f"): $(head -1 /tmp/luac_err.$$)"
			fallos_lua=$((fallos_lua + 1))
		fi
	done
	rm -f /tmp/luac_err.$$
	[ "$fallos_lua" -eq 0 ] && echo "  los $(ls ../*.lua | wc -l) ficheros compilan con Lua 5.5" \
	                        || { echo "  $fallos_lua ficheros NO compilan con Lua 5.5"; exit 1; }
fi
