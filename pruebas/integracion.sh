#!/bin/bash
# Prueba de integracion de verdad: Attract-Mode Plus arrancando, con el plugin
# de creditos activado, lanzando GroovyMAME y volviendo. Todo en un directorio
# de configuracion aparte: no toca ni ~/.attract ni ~/.mame.
#
# Bajo Xvfb no hay nadie que pulse botones, asi que un layout de prueba dispara
# las senales (integracion/layout.nut). Las capturas las guarda AM+ solo, con
# su propia senal "screenshot".
#
# Comprueba, sin criterio humano:
#   1. el marcador se ve ENCIMA del fondo opaco del layout (zorder)
#   2. al juego va UN credito, no el monedero entero
#   3. meter una moneda DENTRO de la partida no cuesta nada: mueve un credito
#      del monedero a la maquina. Lo que cobra es jugar (pulsar START)
#   4. el frontend recoge el saldo bueno al volver, y con el se juega otra vez
#
# Variables: AM (binario), MAME_DIR, ROMPATH, JUEGO, CREDITOS
set -u

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VECINOS="$(cd "$AQUI/../.." && pwd)"   # los tres repos viven juntos
REPO="${REPO:-$VECINOS/attractplus}"
AM="${AM:-$REPO/attractplus}"
MAME_DIR="${MAME_DIR:-$VECINOS/groovymame_src}"
ROMPATH="${ROMPATH:-/usr/share/games/mame/roms}"
JUEGO="${JUEGO:-pacman}"

for f in "$AM" "$MAME_DIR/mame"; do
	[ -x "$f" ] || { echo "no encuentro $f" >&2; exit 1; }
done

T=$(mktemp -d /tmp/creditos-integracion.XXXXXX)
trap 'rm -rf "$T"' EXIT
D=$T/config
mkdir -p "$D/config" "$D/emulators" "$T/mamecfg"

cp -r "$REPO"/config/* "$D"/
rm -rf "$D/intro"                 # el intro se comeria las primeras senales
cp "$REPO/config/plugins/Creditos.nut" "$D/plugins/"
mkdir -p "$D/layouts/PruebaCreditos"
cp "$AQUI/integracion/layout.nut" "$D/layouts/PruebaCreditos/layout.nut"

# MAME se cierra solo y saca su propia captura
cat > "$D/emulators/groovymame.cfg" <<CFG
executable           $MAME_DIR/mame
args                 "[romfilename]" -rompath $ROMPATH -cfg_directory $T/mamecfg -video soft -sound none -nothrottle -noswitchres -window -resolution 640x480 -seconds_to_run 16 -autoboot_script $AQUI/integracion/mame_con_captura.lua -autoboot_delay 0
workdir              $MAME_DIR
rompath              $ROMPATH
romext               .zip
CFG

printf 'plugin\tCreditos\n\tenabled\tyes\n\tparam\tsenal\tcustom1\n\tparam\tboton\t\n\tparam\tbuzon\t%s\n\tparam\ttamano\t28\n\n' "$T/buzon.txt" > "$D/config/plugins.cfg"
printf 'display\tArcade\n\tlayout\tPruebaCreditos\n\tromlist\tgroovymame\n\tin_cycle\tyes\n\tin_menu\tyes\n\n' > "$D/config/attract.cfg"

echo "# construyendo romlist..."
( cd "$REPO" && "$AM" --config "$D" --build-romlist groovymame ) > "$T/romlist.log" 2>&1 || {
	tail -5 "$T/romlist.log"; echo "fallo construyendo la romlist" >&2; exit 1; }

echo "# arrancando Attract-Mode Plus bajo Xvfb (tarda ~1 min: son dos partidas)..."
( cd "$REPO" && env GA_MONEDERO=1 GA_VERBOSO=1 GA_ARCHIVO="$T/buzon.txt" GA_SNAP="$T/mame.png" GA_SNAP_FRAMES=650 \
	GA_PRUEBA_MONEDA=480 GA_PRUEBA_START=560 \
	timeout 300 xvfb-run -a "$AM" --config "$D" ) > "$T/am.log" 2>&1
echo "#   (codigo de salida $?)"

fallos=0
comprobar() {  # nombre, condicion_ya_evaluada, detalle
	if [ "$2" = "1" ]; then echo "  ok   $1"; else echo "  FALLO $1  ($3)"; fallos=$((fallos+1)); fi
}

# 1. el marcador se dibuja encima del fondo del layout
brillo() { convert "$1" -crop 400x60+20+950 +repage -format '%[fx:mean]' info: 2>/dev/null; }
FONDO=$(convert "$D/screen.png" -crop 400x60+20+500 +repage -format '%[fx:mean]' info: 2>/dev/null || echo 0)
CON=$(brillo "$D/screen.png")
comprobar "el marcador se ve encima del layout" \
	"$(awk -v a="$CON" -v b="$FONDO" 'BEGIN{print (a>b+0.01)?1:0}')" "marcador=$CON fondo=$FONDO"

# 2. tres monedas, y el plugin NO inserta ninguna: es una hucha
comprobar "el plugin guarda 3 y no ordena insertar nada" \
	"$(grep -q 'saldo 3, a insertar 0' "$T/am.log" && echo 1 || echo 0)" \
	"$(grep -c 'a insertar' "$T/am.log") lineas"

# ...y NO se le escribe el monedero en la RAM: eso meteria los 3 creditos de
# golpe y el boton de moneda no pintaria nada
comprobar "el monedero no se vuelca en la RAM del juego" \
	"$([ "$(grep -c 'creditos sincronizados' "$T/am.log")" = "0" ] && echo 1 || echo 0)" \
	"$(grep 'sincroniza' "$T/am.log" | head -1)"
comprobar "y se monta el cerrojo con los 3 creditos" \
	"$(grep -q 'cerrojo puesto: el jugador puede meter 3' "$T/am.log" && echo 1 || echo 0)" \
	"$(grep 'cerrojo' "$T/am.log" | head -1)"

# 3. la moneda metida en la partida SE COBRA al meterla: el contador fisico lo
# ensena, asi que el gasto es visible y honesto
comprobar "meter una moneda descuenta del monedero" \
	"$(grep -q 'quedan 2 en el monedero' "$T/am.log" && echo 1 || echo 0)" "ver $T/am.log"
comprobar "y jugarla no lo cobra otra vez" \
	"$(grep -q 'el juego se lleva 1 credito, quedan 2' "$T/am.log" && echo 1 || echo 0)" \
	"$(grep -c 'se lleva' "$T/am.log") lineas"

# ...y el frontend recoge ese saldo: 3 monedas - 1 partida jugada = 2
comprobar "el frontend adopta el saldo al volver" \
	"$(grep -E '^ESTADO' "$T/am.log" | grep -q 'partidas=1 creditos=2' && echo 1 || echo 0)" \
	"$(grep -E '^ESTADO' "$T/am.log" | head -1)"

# 4. y con lo que queda se juega otra partida
VECES=$(grep -c 'a insertar' "$T/am.log")
comprobar "queda para otra partida" "$([ "$VECES" = "2" ] && echo 1 || echo 0)" "MAME arranco $VECES veces"
comprobar "y tras la segunda queda un credito" \
	"$(grep -E '^ESTADO' "$T/am.log" | grep -q 'partidas=2 creditos=1' && echo 1 || echo 0)" \
	"$(grep -E '^ESTADO' "$T/am.log" | tail -1)"

echo "# capturas y registro en $T (se borran al salir; copialos si quieres verlos)"
if [ "${GUARDAR:-}" != "" ]; then
	mkdir -p "$GUARDAR" && cp "$D"/screen*.png "$T/mame.png" "$T/am.log" "$GUARDAR"/ 2>/dev/null
	echo "# copiados a $GUARDAR"
fi

echo "# fallos=$fallos"
exit $(( fallos > 0 ))
