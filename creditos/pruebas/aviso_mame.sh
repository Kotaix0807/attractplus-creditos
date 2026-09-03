#!/bin/bash
# Prueba del cuadro de aviso dentro de GroovyMAME de verdad.
#
# La tecla de salir y el start se fingen sustituyendo las funciones que
# creditos.lua usa para leerlas (integracion/mame_con_captura.lua). Ojo con el
# limite de esa simulacion: la tecla fingida alimenta nuestra maquina de
# estados, pero no es una pulsacion real, asi que en el caso "no avisar" no se
# puede comprobar que MAME salga, solo que NO frenamos la salida. Salir es
# comportamiento propio de MAME, que no tocamos.
#
# Como se sabe si la partida siguio o no: el envoltorio saca una captura en el
# frame GA_SNAP_FRAMES. Si MAME salio antes, esa linea no aparece en el log.
set -u

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VECINOS="$(cd "$AQUI/../.." && pwd)"   # los tres repos viven juntos
MAME_DIR="${MAME_DIR:-$VECINOS/groovymame_src}"
ROMPATH="${ROMPATH:-/usr/share/games/mame/roms}"
JUEGO="${JUEGO:-pacman}"

[ -x "$MAME_DIR/mame" ] || { echo "no encuentro $MAME_DIR/mame" >&2; exit 1; }

T=$(mktemp -d /tmp/aviso-mame.XXXXXX)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/mamecfg"
cp "$HOME/.mame/cfg/$JUEGO.cfg" "$T/mamecfg/" 2>/dev/null || true

fallos=0
# Con -autoboot_delay 0 el script arranca en el frame 0 (es lo que cierra la
# ventana de creditos gratis), asi que los frames de la simulacion van 360 mas
# adelante para que el juego este igual de arrancado que antes.
FRAME_CORTE=760
printf 'saldo 10\ninserta 0\n' > "$T/monedero.txt"   # para el escenario del jugador despistado
printf 'saldo 2\ninserta 0\n' > "$T/corto.txt"      # para el escenario del cerrojo

correr() {  # $1 = nombre, resto = variables
	local n=$1; shift
	# Monedero propio de cada escenario: sin esto se leeria el de verdad
	# ($HOME/.attract/creditos.txt) y el resultado dependeria de lo que hubiera
	# jugado el usuario. Un escenario puede pasar su propio GA_ARCHIVO despues.
	printf 'saldo 5\ninserta 0\n' > "$T/$n.txt"
	# GA_MONEDERO=1 porque estos escenarios prueban el monedero compartido,
	# que desde el 2026-08-29 ya no es el modo por defecto (ver el escenario 9
	# para el modo de monedas de verdad).
	( cd "$MAME_DIR" && env GA_MONEDERO=1 GA_ARCHIVO="$T/$n.txt" "$@" GA_VERBOSO=1 GA_SNAP="$T/$n.png" GA_SNAP_FRAMES=$FRAME_CORTE \
		xvfb-run -a ./mame "$JUEGO" -rompath "$ROMPATH" -cfg_directory "$T/mamecfg" \
		-snapshot_directory "$T" -video soft -sound none -nothrottle -noswitchres \
		-window -resolution 640x480 -seconds_to_run 16 \
		-autoboot_script "$AQUI/integracion/mame_con_captura.lua" -autoboot_delay 0 \
		> "$T/$n.log" 2>&1 )
}

comprobar() { # nombre, condicion, detalle
	if [ "$2" = "1" ]; then echo "  ok   $1"; else echo "  FALLO $1  ($3)"; fallos=$((fallos+1)); fi
}

tiene() { grep -q "$2" "$T/$1.log" && echo 1 || echo 0; }
sigue() { grep -q '\[prueba\] captura' "$T/$1.log" && echo 1 || echo 0; }

echo "# 1. el jugador mete monedas y luego sale: se le avisa"
correr frena GA_PRUEBA_MONEDA=460,500 GA_PRUEBA_SALIR=610
comprobar "cada moneda sale del monedero" "$(tiene frena 'quedan 3 en el monedero')" "ver log"
comprobar "frena la salida" "$(tiene frena 'salida frenada')" "ver log"
comprobar "y cuenta lo que hay dentro" "$(tiene frena 'pueden quedar 2 creditos')" "ver log"
comprobar "la partida no se corta" "$(sigue frena)" "MAME salio"

echo "# 2. segunda pulsacion: sale de verdad"
correr confirma GA_PRUEBA_MONEDA=460 GA_PRUEBA_SALIR=610,670
comprobar "confirma la salida" "$(tiene confirma 'salida confirmada')" "ver log"
comprobar "y MAME se cierra" "$([ "$(sigue confirma)" = "0" ] && echo 1 || echo 0)" "seguia corriendo"

echo "# 3. START cancela y se sigue jugando"
correr cancela GA_PRUEBA_MONEDA=460 GA_PRUEBA_SALIR=610 GA_PRUEBA_START=650
comprobar "el jugador sigue jugando" "$(tiene cancela 'sigue jugando')" "ver log"
comprobar "la partida continua" "$(sigue cancela)" "MAME salio"

echo "# 4. si nadie contesta, el cuadro se rinde y NO sale"
correr espera GA_PRUEBA_MONEDA=460 GA_PRUEBA_SALIR=610 GA_AVISO_ESPERA=60
comprobar "el cuadro se quita solo" "$(tiene espera 'nadie contesta')" "ver log"
comprobar "sin salir" "$(sigue espera)" "MAME salio"

echo "# 5. entrar a mirar un juego y salir: no molestar"
correr mirar GA_PRUEBA_SALIR=610
comprobar "no aparece ningun aviso" "$([ "$(tiene mirar 'salida frenada')" = "0" ] && echo 1 || echo 0)" "aviso indebido"

echo "# 6. el jugador mete cuatro monedas de diez: se le cobran las cuatro"
# Ojo, esto es lo CONTRARIO de lo que se comprobaba antes: con contador fisico
# el gasto es visible, asi que la moneda se cobra al meterla.
correr loco GA_ARCHIVO="$T/monedero.txt" GA_PRUEBA_MONEDA=460,500,540,580 GA_PRUEBA_START=620
comprobar "las cuatro monedas se cobran" \
	"$([ "$(grep -c 'en el monedero' "$T/loco.log")" -ge "4" ] && echo 1 || echo 0)" \
	"$(grep -c 'en el monedero' "$T/loco.log") monedas contadas"
comprobar "jugar no cobra por segunda vez" \
	"$([ "$(tiene loco 'el juego se lleva 1 credito, quedan 5')" = "0" ] && echo 1 || echo 0)" \
	"$(grep 'se lleva' "$T/loco.log" | head -1)"
comprobar "y el monedero queda en 6 de 10" "$(grep -q '^saldo 6$' "$T/monedero.txt" && echo 1 || echo 0)" \
	"$(cat "$T/monedero.txt" 2>/dev/null | tr '\n' ' ')"

echo "# 6b. con dos creditos, la tercera moneda se rechaza"
correr cerrojo GA_ARCHIVO="$T/corto.txt" GA_PRUEBA_MONEDA=460,500,540,580
comprobar "el cerrojo se monta con el saldo justo" \
	"$(tiene cerrojo 'cerrojo puesto: el jugador puede meter 2')" "ver log"
comprobar "entran dos monedas" \
	"$([ "$(grep -c 'entra en la maquina' "$T/cerrojo.log")" = "2" ] && echo 1 || echo 0)" \
	"$(grep -c 'entra en la maquina' "$T/cerrojo.log") entradas"
comprobar "y se bloquea el boton" "$(tiene cerrojo 'bloqueo el boton de moneda')" "ver log"
comprobar "las otras dos se rechazan" \
	"$([ "$(grep -c 'moneda rechazada' "$T/cerrojo.log")" = "2" ] && echo 1 || echo 0)" \
	"$(grep -c 'moneda rechazada' "$T/cerrojo.log") rechazos"
comprobar "el monedero queda a cero, no en negativo" \
	"$(grep -q '^saldo 0$' "$T/corto.txt" && echo 1 || echo 0)" \
	"$(cat "$T/corto.txt" 2>/dev/null | tr '\n' ' ')"

echo "# 6c. el jugador pillo: pulsar la moneda nada mas arrancar"
# Reproduce el agujero que encontro Eloy. Con -autoboot_delay 6 el script no
# existia durante los primeros 6 segundos y esas monedas eran gratis. Ahora el
# cerrojo se monta en el frame 0.
#
# Ojo con el alcance de la simulacion: la moneda fingida llama ademas a
# set_value(), que salta la secuencia vacia del cerrojo. O sea que esto prueba
# la SEGUNDA red (la limpieza al asentarse), que es justo la que hace falta si
# alguna moneda se colara de verdad.
printf 'saldo 0\ninserta 0\n' > "$T/w_pillo.txt"
correr pillo GA_ARCHIVO="$T/w_pillo.txt" GA_PRUEBA_MONEDA=5,25,45,65
comprobar "el cerrojo ya esta puesto en el frame 0" \
	"$(tiene pillo 'cerrojo puesto: el jugador puede meter 0')" "ver log"
comprobar "las cuatro pulsaciones se rechazan" \
	"$([ "$(grep -c 'moneda rechazada' "$T/pillo.log")" = "4" ] && echo 1 || echo 0)" \
	"$(grep -c 'moneda rechazada' "$T/pillo.log") rechazos"
comprobar "no entra ni un credito en la cuenta" \
	"$([ "$(grep -c 'entra en la maquina' "$T/pillo.log")" = "0" ] && echo 1 || echo 0)" \
	"$(grep -c 'entra en la maquina' "$T/pillo.log") entradas"
comprobar "el arranque los cubre enteros" \
	"$(tiene pillo 'arranque terminado')" "ver log"
comprobar "el monedero sigue a cero" \
	"$(grep -q '^saldo 0$' "$T/w_pillo.txt" && echo 1 || echo 0)" \
	"$(cat "$T/w_pillo.txt" 2>/dev/null | tr '\n' ' ')"

echo "# 6e. con monedero lleno, pulsar durante el arranque tampoco cuesta"
# El segundo agujero que cerro la idea de Eloy: durante su test de RAM/ROM la
# placa IGNORA las monedas, asi que cobrarlas seria cobrar por nada.
printf 'saldo 5\ninserta 0\n' > "$T/w_arranque.txt"
correr arranque GA_ARCHIVO="$T/w_arranque.txt" GA_PRUEBA_MONEDA=30,60,90
comprobar "la maquina arranca con el boton cerrado" \
	"$(tiene arranque 'la maquina esta arrancando: boton de moneda cerrado')" "ver log"
comprobar "las pulsaciones del arranque se rechazan" \
	"$([ "$(grep -c 'todavia esta arrancando' "$T/arranque.log")" = "3" ] && echo 1 || echo 0)" \
	"$(grep -c 'todavia esta arrancando' "$T/arranque.log") rechazos"
comprobar "y luego se abre solo" \
	"$(tiene arranque 'arranque terminado')" "ver log"
comprobar "el monedero sigue intacto" \
	"$(grep -q '^saldo 5$' "$T/w_arranque.txt" && echo 1 || echo 0)" \
	"$(cat "$T/w_arranque.txt" 2>/dev/null | tr '\n' ' ')"

echo "# 6d. la moneda metida mientras la placa se asienta NO se le quita"
# SIN arranque tapado y con asentamiento largo, para que la moneda caiga en la
# ventana en la que el boton ya esta abierto pero la RAM aun no es de fiar. Con
# arranque tapado esto no puede pasar: ahi el boton esta cerrado y el barrido va
# justo al terminar.
printf 'saldo 3\ninserta 0\n' > "$T/w_pronto.txt"
correr pronto GA_ARCHIVO="$T/w_pronto.txt" GA_PRUEBA_MONEDA=420 GA_ARRANQUE=0 GA_ASENTAR=600
comprobar "la moneda entra aunque sea pronto" \
	"$(tiene pronto 'entra en la maquina')" "ver log"
comprobar "y la limpieza le respeta su credito" \
	"$([ "$(tiene pronto 'solo 0 estan pagados')" = "0" ] && echo 1 || echo 0)" \
	"$(grep 'estan pagados' "$T/pronto.log" | head -1)"
comprobar "el monedero queda en 2" \
	"$(grep -q '^saldo 2$' "$T/w_pronto.txt" && echo 1 || echo 0)" \
	"$(cat "$T/w_pronto.txt" 2>/dev/null | tr '\n' ' ')"

echo "# 6f. el barrido quita lo que la maquina traiga sin pagar"
# Sin arranque tapado a proposito: asi la RAM de Pac-Man todavia tiene su
# patron del test (176) cuando se asienta el contador, que es justo el caso que
# el barrido tiene que limpiar (creditos colados, o la NVRAM de antes).
printf 'saldo 2\ninserta 0\n' > "$T/w_barrido.txt"
correr barrido GA_ARCHIVO="$T/w_barrido.txt" GA_ARRANQUE=0 GA_ASENTAR=180
comprobar "encuentra creditos sin pagar" \
	"$(tiene barrido 'estan pagados')" "$(grep 'estan pagados' "$T/barrido.log" | head -1)"
comprobar "y no le cobra nada al jugador" \
	"$(grep -q '^saldo 2$' "$T/w_barrido.txt" && echo 1 || echo 0)" \
	"$(cat "$T/w_barrido.txt" 2>/dev/null | tr '\n' ' ')"

echo "# 6g. si la placa no recoge la moneda, se devuelve el credito"
printf 'saldo 5\ninserta 0\n' > "$T/w_devuelve.txt"
correr devuelve GA_ARCHIVO="$T/w_devuelve.txt" GA_ARRANQUE=0 GA_PRUEBA_MONEDA=200
comprobar "la moneda se cobra al meterla" \
	"$(tiene devuelve 'entra en la maquina')" "ver log"
comprobar "el juego no la recoge y se devuelve" \
	"$(tiene devuelve 'no recogio')" "$(grep 'devuelvo' "$T/devuelve.log" | head -1)"
comprobar "el monedero acaba como empezo" \
	"$(grep -q '^saldo 5$' "$T/w_devuelve.txt" && echo 1 || echo 0)" \
	"$(cat "$T/w_devuelve.txt" 2>/dev/null | tr '\n' ' ')"

echo "# 7. GA_AVISO=0 lo desactiva del todo"
correr apagado GA_AVISO=0 GA_PRUEBA_MONEDA=460 GA_PRUEBA_SALIR=610
comprobar "el aviso no se monta" "$([ "$(tiene apagado 'aviso de creditos dentro')" = "0" ] && echo 1 || echo 0)" "seguia activo"
comprobar "y no frena nada" "$([ "$(tiene apagado 'salida frenada')" = "0" ] && echo 1 || echo 0)" "freno la salida"

echo "# 8. si el juego esta en creditos.dat, los creditos se leen de su RAM"
correr memoria GA_PRUEBA_MONEDA=460 GA_PRUEBA_START=560
comprobar "lee el contador de la RAM" "$(tiene memoria 'creditos leidos de la memoria del juego')" \
	"$JUEGO no esta en creditos.dat?"
comprobar "y el consumo sale de ahi, no de una estimacion" \
	"$(tiene memoria 'el juego se lleva 1 credito (contador en')" "ver log"

echo "# 9. modo monedas de verdad: solo arranque tapado y aviso al salir"
# El modo por defecto desde el 2026-08-29. Sin monedero: las monedas entran
# solas en el emulador y este script solo tapa el arranque y avisa al salir.
( cd "$MAME_DIR" && env GA_VERBOSO=1 GA_PRUEBA_MONEDA=460,500 GA_PRUEBA_SALIR=610 \
	GA_SNAP="$T/reales.png" GA_SNAP_FRAMES=$FRAME_CORTE \
	xvfb-run -a ./mame "$JUEGO" -rompath "$ROMPATH" -cfg_directory "$T/mamecfg" \
	-snapshot_directory "$T" -video soft -sound none -nothrottle -noswitchres \
	-window -resolution 640x480 -seconds_to_run 16 \
	-autoboot_script "$AQUI/integracion/mame_con_captura.lua" -autoboot_delay 0 \
	> "$T/reales.log" 2>&1 )
comprobar "no busca monedero" \
	"$(tiene reales 'sin monedero')" "ver log"
comprobar "monta cerrojo sin limite" \
	"$(tiene reales 'puede meter las que quiera')" "ver log"
comprobar "tapa el arranque igual" "$(tiene reales 'arranque terminado')" "ver log"
comprobar "y avisa al salir con creditos dentro" "$(tiene reales 'salida frenada')" "ver log"
comprobar "la partida no se corta" "$(sigue reales)" "MAME salio"

echo "# 9b. sin monedero, la moneda durante la carga tampoco cuenta"
# El caso de Q*bert: pulsar el boton de creditos mientras carga daba 52.
( cd "$MAME_DIR" && env GA_VERBOSO=1 GA_PRUEBA_MONEDA=5,40,80,120 \
	xvfb-run -a ./mame "$JUEGO" -rompath "$ROMPATH" -cfg_directory "$T/mamecfg" \
	-video none -sound none -nothrottle -noswitchres -seconds_to_run 16 \
	-autoboot_script "$AQUI/integracion/mame_con_captura.lua" -autoboot_delay 0 \
	> "$T/carga.log" 2>&1 )
comprobar "el boton esta cerrado mientras carga" \
	"$(tiene carga 'la maquina esta arrancando: boton de moneda cerrado')" "ver log"
comprobar "las cuatro pulsaciones se rechazan" \
	"$([ "$(grep -c 'todavia esta arrancando' "$T/carga.log")" = "4" ] && echo 1 || echo 0)" \
	"$(grep -c 'todavia esta arrancando' "$T/carga.log") rechazos"
comprobar "y ninguna entra en la maquina" \
	"$([ "$(grep -c 'entra en la maquina' "$T/carga.log")" = "0" ] && echo 1 || echo 0)" \
	"$(grep -c 'entra en la maquina' "$T/carga.log") entradas"

echo "# 10. un juego que reinicia la placa deja el emulador como estaba"
# elevator se reinicia durante el arranque y MAME relanza el autoboot. Sin
# cuidado, la segunda ejecucion guardaba como "original" lo que dejo la primera
# (freno ya quitado, moneda ya bloqueada) y lo restauraba al terminar: el
# emulador se quedaba sin freno y el boton de moneda muerto.
( cd "$MAME_DIR" && env GA_VERBOSO=1 \
	xvfb-run -a ./mame elevator -rompath "$ROMPATH" -cfg_directory "$T/mamecfg" \
	-video none -sound none -noswitchres -seconds_to_run 40 \
	-autoboot_script "$AQUI/integracion/estado_final.lua" -autoboot_delay 0 \
	> "$T/reinicio.log" 2>&1 )
comprobar "el script se ejecuta dos veces" \
	"$([ "$(grep -c 'encontrado COIN1' "$T/reinicio.log")" -ge "2" ] && echo 1 || echo 0)" \
	"$(grep -c 'encontrado COIN1' "$T/reinicio.log") veces"
comprobar "y lo detecta" "$(tiene reinicio 'la placa se reinicio')" "ver log"
comprobar "el emulador vuelve a su velocidad" \
	"$(grep -q '\[final\] throttled=true' "$T/reinicio.log" && echo 1 || echo 0)" \
	"$(grep '\[final\] throttled' "$T/reinicio.log")"
comprobar "y sin quedarse mudo" \
	"$(grep -q 'mute=false' "$T/reinicio.log" && echo 1 || echo 0)" \
	"$(grep '\[final\] throttled' "$T/reinicio.log")"
comprobar "el boton de moneda sigue vivo" \
	"$([ "$(grep -q '\[final\] moneda: 0 codigos' "$T/reinicio.log" && echo 1 || echo 0)" = "0" ] && echo 1 || echo 0)" \
	"$(grep '\[final\] moneda' "$T/reinicio.log")"

echo "# 11. nvram=0 evita que el juego guarde sus creditos"
# Los juegos con NVRAM arrancan con los creditos de la sesion anterior. Limpiar
# el contador no vale: el barrido llega despues de que el juego haya pintado su
# mensaje, y adelantarlo rompe el test de RAM de la placa (medido: Pac-Man no
# arrancaba hasta el frame 302 en vez del 14). La salida es no guardar la NVRAM.
mkdir -p "$T/nv"
cat > "$T/ajustes_nv.dat" <<'AJU'
defecto velocidad=0 arranque=5
tapper nvram=0
AJU
( cd "$MAME_DIR" && env GA_VERBOSO=1 GA_AJUSTES="$T/ajustes_nv.dat" \
	xvfb-run -a ./mame tapper -rompath "$ROMPATH" -cfg_directory "$T/mamecfg" \
	-nvram_directory "$T/nv" -video none -sound none -nothrottle -noswitchres \
	-seconds_to_run 14 -autoboot_script "$AQUI/../creditos.lua" -autoboot_delay 0 \
	> "$T/nvram.log" 2>&1 )
comprobar "el ajuste se aplica" "$(tiene nvram 'nvram=0')" "ver log"
comprobar "y no se escribe la NVRAM" \
	"$([ -f "$T/nv/tapper/nvram" ] && echo 0 || echo 1)" "se escribio"

# y con el ajuste quitado, si se guarda
cat > "$T/ajustes_nv2.dat" <<'AJU'
defecto velocidad=0 arranque=5
AJU
( cd "$MAME_DIR" && env GA_VERBOSO=1 GA_AJUSTES="$T/ajustes_nv2.dat" \
	xvfb-run -a ./mame tapper -rompath "$ROMPATH" -cfg_directory "$T/mamecfg" \
	-nvram_directory "$T/nv" -video none -sound none -nothrottle -noswitchres \
	-seconds_to_run 14 -autoboot_script "$AQUI/../creditos.lua" -autoboot_delay 0 \
	> "$T/nvram2.log" 2>&1 )
comprobar "sin el ajuste, la NVRAM si se guarda" \
	"$([ -f "$T/nv/tapper/nvram" ] && echo 1 || echo 0)" "no se escribio"

echo "# fallos=$fallos"
exit $(( fallos > 0 ))
