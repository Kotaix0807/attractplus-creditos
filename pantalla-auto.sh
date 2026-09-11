#!/usr/bin/env bash
# pantalla-auto.sh - manda el video al CRT del VGA si lo hay, y al panel
# interno si no lo hay. Pensado para la cabina (GroovyArcade, sesion X).
#
#   ./pantalla-auto.sh estado        que ve ahora mismo, sin tocar nada
#   ./pantalla-auto.sh una-vez       decide y aplica una sola vez
#   ./pantalla-auto.sh vigilar       se queda vigilando (es lo que corre el servicio)
#   sudo ./pantalla-auto.sh crt      fuerza el video al CRT, a mano
#   sudo ./pantalla-auto.sh panel    fuerza el video al panel interno, a mano
#   sudo ./pantalla-auto.sh instalar
#   sudo ./pantalla-auto.sh desinstalar
#   sudo ./pantalla-auto.sh pausar / reanudar
#
# POR QUE HACE FALTA FORZAR EL CONECTOR, Y NO BASTA XRANDR
# -------------------------------------------------------
# La cabina arranca con esto en la linea del kernel:
#
#     video=VGA-1:e video=LVDS-1:d
#
# Ese `:d` deshabilita el panel interno EN EL KERNEL, asi que aparece como
# `disconnected` en /sys/class/drm y **X no lo ve en absoluto**. No es que este
# apagado y se pueda encender con xrandr: no esta. Por eso el primer paso
# siempre es el conector, y xrandr viene despues.
#
# Lo bueno es que se puede deshacer en caliente, sin tocar GRUB ni reiniciar:
# escribir `on` en el `status` del conector lo devuelve a la vida. Comprobado en
# la cabina: pasa a `connected` y ofrece su modo nativo 1366x768.
#
# Y AL REVES, apagar el conector del que no se usa es mejor que `xrandr --off`:
# una salida `connected` pero sin CRTC hace que AM+ pida XRRGetCrtcInfo(0) y
# reviente con BadRRCrtc (fe_present.cpp:391). Dejandola `disconnected` a nivel
# de kernel, X ni la considera y ese fallo no puede darse.
#
# DESACTIVARLO
# ------------
# Tres niveles, de mas suave a mas definitivo:
#   1. `pausar`  - deja el servicio vivo pero sin tocar nada (fichero de freno).
#   2. `systemctl disable --now pantalla-auto` - lo para y no arranca mas.
#   3. `desinstalar` - lo quita todo y devuelve los conectores a como arrancan.
set -u

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------- ajustes ---
# Se pueden cambiar en /etc/pantalla-auto.conf sin tocar este fichero.
EXTERNA="${EXTERNA:-VGA-1}"        # el CRT de la cabina
INTERNA="${INTERNA:-LVDS-1}"       # el panel del portatil que hace de chasis
INTERVALO="${INTERVALO:-4}"        # segundos entre comprobaciones
CONFIRMAR="${CONFIRMAR:-2}"        # lecturas iguales seguidas antes de cambiar
# Vacio = no se toca la resolucion: si la salida ya esta encendida se la deja
# como este, y si hay que encenderla se usa --auto (la preferida del EDID).
# Poner un modo aqui es para forzar uno concreto, y conviene NO hacerlo salvo
# que se quiera: la cabina estaba a 1024x768 y un 1280x1024 puesto a ciegas le
# habria cambiado la resolucion en cada conmutacion, sin que nadie lo pidiera.
MODO_EXTERNA="${MODO_EXTERNA:-}"
MODO_INTERNA="${MODO_INTERNA:-}"
FRENO="${FRENO:-/etc/pantalla-auto.off}"
UNIDAD=/etc/systemd/system/pantalla-auto.service
CONF=/etc/pantalla-auto.conf
[ -r "$CONF" ] && . "$CONF"

decir() { printf '[pantalla-auto] %s\n' "$*" >&2; }

# ------------------------------------------------------------ conectores ---
# El numero de tarjeta NO es estable: en la cabina vieja era card0 (NVIDIA) y
# en la de ahora es card1 (Intel). Se busca por comodin, nunca a mano.
dir_de() {
	local n="$1" d
	for d in /sys/class/drm/card*-"$n"; do
		[ -d "$d" ] && { printf '%s\n' "$d"; return 0; }
	done
	return 1
}

estado_de() {
	local d; d="$(dir_de "$1")" || { echo ausente; return; }
	cat "$d/status" 2>/dev/null || echo ausente
}

# on = forzado encendido, off = forzado apagado, detect = que lo averigue el kernel
forzar() {
	local d; d="$(dir_de "$1")" || return 1
	printf '%s\n' "$2" > "$d/status" 2>/dev/null
}

# El VGA no tiene una linea de "me han enchufado" fiable, asi que no vale
# esperar un evento: hay que pedirle al kernel que lo compruebe de verdad.
# Comprobado en la cabina que la deteccion es REAL y no el forzado del kernel:
# quitando el `:e`, el conector sigue `connected` y entrega un EDID de 128 bytes.
hay_crt() {
	forzar "$EXTERNA" detect
	sleep 1
	[ "$(estado_de "$EXTERNA")" = connected ]
}

# ------------------------------------------------------------------- X ---
# Se usa el DISPLAY del Xorg que este corriendo, no `:0` a ciegas.
display_vivo() {
	local linea
	linea="$(pgrep -a -x Xorg 2>/dev/null | head -1)" || return 1
	[ -n "$linea" ] || return 1
	printf '%s\n' "$linea" | grep -oE ' :[0-9]+' | head -1 | tr -d ' '
}

# ~/.xinitrc de la cabina hace `xhost +`, asi que root puede hablar con la
# sesion; aun asi se pasa el XAUTHORITY si esta, por si algun dia deja de estar.
xr() {
	local d="$1"; shift
	local casa=/home/arcade
	XAUTHORITY="${XAUTHORITY:-$casa/.Xauthority}" DISPLAY="$d" xrandr "$@" 2>&1
}

# Que argumento de modo pasarle a xrandr. La regla es la de menor sorpresa:
# si la salida YA esta encendida con una resolucion, no se le toca; solo hay
# que elegir modo cuando esta apagada y hay que encenderla.
arg_modo() {
	local conector="$1" modo="$2" d display="$3"
	# ¿ya esta encendida con un modo? -> no se toca
	if [ -n "$display" ] && xr "$display" --query |
			grep -qE "^$conector connected [0-9]+x[0-9]+\+"; then
		echo ""
		return
	fi
	[ -n "$modo" ] || { echo "--auto"; return; }
	d="$(dir_de "$conector")" || { echo "--auto"; return; }
	if grep -qx "$modo" "$d/modes" 2>/dev/null; then
		echo "--mode $modo"
	else
		decir "$conector no ofrece $modo, uso --auto"
		echo "--auto"
	fi
}

# ------------------------------------------------------------- aplicar ---
# Orden deliberado: primero se deja utilizable el destino y solo despues se
# apaga el otro. Al reves, un fallo a mitad deja la cabina sin ninguna imagen.
aplicar() {
	local destino="$1" apagar="$2" modo="$3" d
	forzar "$destino" on
	sleep 1
	if [ "$(estado_de "$destino")" != connected ]; then
		decir "NO aplico: $destino sigue sin estar disponible. Lo dejo como esta."
		return 1
	fi
	forzar "$apagar" off

	if d="$(display_vivo)" && [ -n "$d" ]; then
		sleep 1     # que Xorg se entere del cambio de conector
		# Una sola orden de xrandr, no dos: asi el cambio es atomico y nunca
		# queda un instante con las dos salidas apagadas.
		xr "$d" --output "$destino" --primary $(arg_modo "$destino" "$modo" "$d") \
			--output "$apagar" --off >/dev/null
		decir "aplicado en $d: $destino primaria, $apagar apagada"
	else
		decir "X no esta corriendo: dejo $destino listo para cuando arranque"
	fi
	return 0
}

al_crt()   { aplicar "$EXTERNA" "$INTERNA" "$MODO_EXTERNA"; }
al_panel() { aplicar "$INTERNA" "$EXTERNA" "$MODO_INTERNA"; }

# -------------------------------------------------------------- ordenes ---
cmd_estado() {
	local c
	echo "conectores:"
	for c in "$EXTERNA" "$INTERNA"; do
		printf '  %-10s %s\n' "$c" "$(estado_de "$c")"
	done
	printf 'X: %s\n' "$(display_vivo || echo 'no esta corriendo')"
	printf 'freno: %s\n' "$([ -e "$FRENO" ] && echo "PUESTO ($FRENO)" || echo no)"
	if [ -e "$UNIDAD" ]; then
		printf 'servicio: %s / %s\n' \
			"$(systemctl is-enabled pantalla-auto 2>/dev/null)" \
			"$(systemctl is-active pantalla-auto 2>/dev/null)"
	else
		echo "servicio: no instalado"
	fi
}

cmd_una_vez() {
	[ -e "$FRENO" ] && { decir "freno puesto, no toco nada"; return 0; }
	if hay_crt; then al_crt; else al_panel; fi
}

cmd_vigilar() {
	decir "vigilando $EXTERNA cada ${INTERVALO}s (freno: $FRENO)"
	local ultimo="" visto="" veces=0 frenado="" ultimo_x=""
	while :; do
		if [ -e "$FRENO" ]; then
			[ "$frenado" = si ] || { decir "freno puesto: no toco nada"; frenado=si; ultimo=""; }
			sleep "$INTERVALO"; continue
		fi
		[ "$frenado" = si ] && { decir "freno quitado"; frenado=""; }

		local ahora; ahora=$(hay_crt && echo crt || echo panel)
		# Un cable flojo puede parpadear; se exige leer lo mismo varias veces.
		if [ "$ahora" = "$visto" ]; then veces=$((veces + 1)); else visto="$ahora"; veces=1; fi

		# Tambien hay que reaplicar cuando X aparece o se reinicia, aunque el
		# cable no se haya movido: si el servicio arranca antes que Xorg -- que
		# es lo normal en el arranque de la cabina -- la parte de xrandr no
		# llego a correr, y sin esto no volveria a intentarlo nunca.
		local x_ahora; x_ahora="$(display_vivo || echo -)"
		local motivo=""
		[ "$veces" -ge "$CONFIRMAR" ] && [ "$ahora" != "$ultimo" ] && motivo="cambio de cable -> $ahora"
		[ -z "$motivo" ] && [ -n "$ultimo" ] && [ "$x_ahora" != "$ultimo_x" ] &&
			motivo="X paso de [$ultimo_x] a [$x_ahora]: reaplico $ahora"

		if [ -n "$motivo" ]; then
			decir "$motivo"
			if [ "$ahora" = crt ]; then al_crt && ultimo=crt; else al_panel && ultimo=panel; fi
			ultimo_x="$x_ahora"
		fi
		sleep "$INTERVALO"
	done
}

necesita_root() {
	[ "$(id -u)" = 0 ] || { decir "esto necesita root: usa sudo"; exit 1; }
}

cmd_instalar() {
	necesita_root
	install -m 755 "$AQUI/pantalla-auto.sh" /usr/local/bin/pantalla-auto.sh
	[ -e "$CONF" ] || cat > "$CONF" <<-EOF
		# Ajustes de pantalla-auto. Cambiar aqui, no en el script.
		EXTERNA=$EXTERNA
		INTERNA=$INTERNA
		INTERVALO=$INTERVALO
		MODO_EXTERNA=$MODO_EXTERNA
		MODO_INTERNA=$MODO_INTERNA
	EOF
	cat > "$UNIDAD" <<-EOF
		[Unit]
		Description=Manda el video al CRT del VGA si lo hay, y al panel si no
		After=multi-user.target

		[Service]
		Type=simple
		ExecStart=/usr/local/bin/pantalla-auto.sh vigilar
		Restart=on-failure
		RestartSec=5

		[Install]
		WantedBy=multi-user.target
	EOF
	systemctl daemon-reload
	systemctl enable --now pantalla-auto
	decir "instalado y arrancado. Para quitarlo: sudo pantalla-auto.sh desinstalar"
}

cmd_desinstalar() {
	necesita_root
	systemctl disable --now pantalla-auto 2>/dev/null
	rm -f "$UNIDAD" "$CONF" "$FRENO" /usr/local/bin/pantalla-auto.sh
	systemctl daemon-reload
	# Se devuelven los conectores a como los deja la linea del kernel
	# (video=VGA-1:e video=LVDS-1:d), para no dejar la maquina distinta de
	# como arranca.
	forzar "$EXTERNA" on
	forzar "$INTERNA" off
	decir "desinstalado y conectores devueltos al estado de arranque"
}

cmd_pausar()   { necesita_root; : > "$FRENO"; decir "freno puesto: el servicio sigue vivo pero no toca nada"; }
cmd_reanudar() { necesita_root; rm -f "$FRENO"; decir "freno quitado"; }

case "${1:-estado}" in
	estado)      cmd_estado ;;
	una-vez)     cmd_una_vez ;;
	crt)         necesita_root; al_crt ;;
	panel)       necesita_root; al_panel ;;
	vigilar)     cmd_vigilar ;;
	instalar)    cmd_instalar ;;
	desinstalar) cmd_desinstalar ;;
	pausar)      cmd_pausar ;;
	reanudar)    cmd_reanudar ;;
	*) sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'; exit 1 ;;
esac
