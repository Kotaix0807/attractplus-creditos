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

SQ=${SQ:-/home/eloy/attractplus/extlibs/squirrel}

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
