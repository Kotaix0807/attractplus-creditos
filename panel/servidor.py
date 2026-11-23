#!/usr/bin/env python3
"""El panel web de la cabina (backend real).  Ver docs/panel.md para el contrato.

Expone la API JSON /api/...  La pagina (la GUI) NO se sirve desde aqui: la sirve
la Raspberry Pi con pi/portero.py, que reenvia /api/* a este servidor.  Escucha en
127.0.0.1 o en la IP del cable con la Pi (panel.conf, 'escucha').  Corre como
'arcade' (servicio de usuario), con sudo NOPASSWD para las acciones que piden root.

    python3 panel/servidor.py        # produccion (lo lanza panel.service)

Solo estan las rutas que usan las paginas de pi/web/.  Lo que ninguna usaba
(gestion de juegos, mantenimiento, actualizar, logs, ingresos, MJPEG...) se quito
el 2026-11-22 por decision de Eloy; esta en el historial de git si hace falta.
"""

import functools
import json
import os
import secrets
import time
from datetime import timedelta

from flask import Flask, Response, jsonify, request, session

import acciones
import botones
import estado
from comun import ATTRACT, CONF, auditar, clave_correcta, entero, usuario_correcto

app = Flask(__name__, static_folder=None)


# ---------------------------------------------------------------------------
# Configuracion de la sesion
# ---------------------------------------------------------------------------

def _secreto():
    """Clave de sesion persistente: sobrevive a reinicios del servicio para no
    cerrar la sesion a cada rato.  Se crea ya con permisos de solo-usuario."""
    ruta = os.path.join(ATTRACT, "panel_secret")
    try:
        if os.path.exists(ruta):
            return open(ruta, "rb").read()
        os.makedirs(ATTRACT, exist_ok=True)
        s = secrets.token_bytes(32)
        # os.open con 0o600: el fichero nunca existe con permisos abiertos (antes
        # se creaba normal y se le hacia chmod despues).
        fd = os.open(ruta, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "wb") as f:
            f.write(s)
        return s
    except OSError:
        return secrets.token_bytes(32)


app.secret_key = _secreto()
app.config.update(SESSION_COOKIE_HTTPONLY=True, SESSION_COOKIE_SAMESITE="Lax")
# "Mantener sesion iniciada": una sesion permanente dura esto en vez de cerrarse
# al cerrar el navegador.
app.permanent_session_lifetime = timedelta(days=30)

# Freno sencillo de fuerza bruta en el login (un solo usuario).
_fallos = {"n": 0, "hasta": 0}


def requiere_login(fn):
    @functools.wraps(fn)
    def envoltorio(*a, **k):
        if not session.get("auth"):
            return jsonify({"error": "no autenticado"}), 401
        return fn(*a, **k)
    return envoltorio


def requiere_csrf(fn):
    """Para las acciones (POST): sesion valida Y cabecera X-CSRF-Token correcta."""
    @functools.wraps(fn)
    def envoltorio(*a, **k):
        if not session.get("auth"):
            return jsonify({"error": "no autenticado"}), 401
        if request.headers.get("X-CSRF-Token", "") != session.get("csrf"):
            return jsonify({"error": "token CSRF invalido"}), 403
        return fn(*a, **k)
    return envoltorio


def cuerpo():
    return request.get_json(silent=True) or {}


def _arg_rango(nombre, defecto, lo, hi):
    """Lee request.args[nombre] como entero acotado a [lo, hi] (a prueba de basura:
    los valores van a un comando ffmpeg)."""
    try:
        v = int(request.args.get(nombre, defecto))
    except (TypeError, ValueError):
        v = defecto
    return max(lo, min(hi, v))


# ---------------------------------------------------------------------------
# Sesion
# ---------------------------------------------------------------------------

@app.post("/api/login")
def login():
    ahora = time.time()
    if _fallos["n"] >= 5 and ahora < _fallos["hasta"]:
        return jsonify({"ok": False, "error": "demasiados intentos, espera"}), 429
    datos = cuerpo()
    clave = datos.get("clave", "")
    usuario = datos.get("usuario", "")
    if not (usuario_correcto(usuario) and clave_correcta(clave)):
        _fallos["n"] += 1
        _fallos["hasta"] = ahora + 30
        auditar("login_fallido")
        return jsonify({"ok": False, "error": "usuario o clave incorrectos"}), 401
    _fallos["n"] = 0
    session.permanent = bool(datos.get("recordar"))   # "mantener sesion iniciada"
    session["auth"] = True
    session["csrf"] = secrets.token_hex(16)
    auditar("login")
    return jsonify({"ok": True, "csrf": session["csrf"]})


@app.get("/api/sesion")
def sesion():
    return jsonify({"autenticado": bool(session.get("auth")),
                    "csrf": session.get("csrf") if session.get("auth") else None})


# ---------------------------------------------------------------------------
# Pagina principal (pi/web/index.html)
# ---------------------------------------------------------------------------

@app.get("/api/estado")
@requiere_login
def api_estado():
    return jsonify(estado.completo())


@app.get("/api/masjugados")
@requiere_login
def api_masjugados():
    orden = request.args.get("orden", "partidas")
    limite = request.args.get("limite", "20")
    limite = int(limite) if limite.isdigit() else 20
    return jsonify(estado.masjugados(orden, limite))


@app.get("/api/volumen")
@requiere_login
def api_volumen_get():
    return jsonify(acciones.volumen_actual())


@app.post("/api/volumen")
@requiere_csrf
def api_volumen():
    return jsonify(acciones.volumen(cuerpo().get("nivel", 80)))


@app.post("/api/sonido/prueba")
@requiere_csrf
def api_sonido_prueba():
    """Prueba de altavoces: reproduce un tono en 'izquierda', 'derecha' o 'ambos'."""
    return jsonify(acciones.prueba_sonido(cuerpo().get("canal", "ambos")))


@app.get("/api/tarifa-global")
@requiere_login
def api_tarifa_global_get():
    return jsonify(acciones.tarifa_global_actual())


@app.post("/api/tarifa-global")
@requiere_csrf
def api_tarifa_global():
    return jsonify(acciones.fijar_tarifa_global(cuerpo().get("valor")))


@app.get("/api/leds/brillo")
@requiere_login
def api_brillo_get():
    return jsonify(acciones.brillo_actual())


@app.post("/api/leds/brillo")
@requiere_csrf
def api_brillo_set():
    return jsonify(acciones.fijar_brillo(cuerpo().get("brillo")))


# --- la maquina ---

@app.post("/api/accion/reiniciar")
@requiere_csrf
def api_reiniciar():
    return jsonify(acciones.reiniciar())


@app.post("/api/accion/apagar")
@requiere_csrf
def api_apagar():
    return jsonify(acciones.apagar())


@app.post("/api/accion/suspender")
@requiere_csrf
def api_suspender():
    return jsonify(acciones.suspender())


@app.post("/api/frontend/reiniciar")
@requiere_csrf
def api_frontend():
    return jsonify(acciones.frontend_reiniciar())


@app.post("/api/frontend/menu")
@requiere_csrf
def api_frontend_menu():
    return jsonify(acciones.frontend_menu())


@app.post("/api/monedero/reiniciar")
@requiere_csrf
def api_monedero():
    return jsonify(acciones.monedero_reiniciar())


@app.post("/api/arduino/reiniciar")
@requiere_csrf
def api_arduino():
    return jsonify(acciones.arduino_reiniciar())


# --- el juego en marcha ---

@app.post("/api/creditos")
@requiere_csrf
def api_creditos():
    return jsonify(acciones.creditos(cuerpo().get("n", 1)))


@app.post("/api/juego/salir")
@requiere_csrf
def api_salir():
    return jsonify(acciones.juego_salir())


@app.post("/api/juego/menu")
@requiere_csrf
def api_juego_menu():
    return jsonify(acciones.juego_menu())


# ---------------------------------------------------------------------------
# Tester de botones y joystick virtual (pi/web/tester.html)
# ---------------------------------------------------------------------------

@app.get("/api/botones")
@requiere_login
def api_botones():
    """SSE: cada pulsacion de los mandos (no del teclado), para 'Test botones'."""
    auditar("test_botones")

    def flujo():
        for ev in botones.eventos_botones():
            yield "data: " + json.dumps(ev) + "\n\n"
    return Response(flujo(), mimetype="text/event-stream")


@app.post("/api/pulsar")
@requiere_csrf
def api_pulsar():
    """Joystick virtual: envia un control del mueble a la cabina (en juego por
    panel_cmd->creditos.lua; en el menu por tecla XTEST)."""
    return jsonify(acciones.pulsar(cuerpo().get("control", "")))


# ---------------------------------------------------------------------------
# Puntajes (pi/web/puntajes.html)
# ---------------------------------------------------------------------------

@app.get("/api/puntajes")
@requiere_login
def api_puntajes():
    return jsonify(estado.puntajes())


# ---------------------------------------------------------------------------
# Pantalla remota (pi/web/pantalla.html)
# ---------------------------------------------------------------------------

@app.get("/api/pantalla.mp4")
@requiere_login
def api_pantalla_mp4():
    """Stream H.264 (MP4 fragmentado) en vivo, para <video> por MSE en el navegador.
    H.264 comprime entre cuadros -> fluido en 4G. Ajustable: ?ancho=&kbps=&fps=."""
    # 60fps por defecto: la cabina va a 60Hz; capturar a 30 muestrea 1 de cada 2
    # cuadros sin sincronizar -> tironeo. El i3 encode a 60 a speed 1.0 (medido).
    gen = acciones.stream_pantalla_h264(fps=_arg_rango("fps", 60, 5, 60),
                                        ancho=_arg_rango("ancho", 640, 320, 1280),
                                        kbps=_arg_rango("kbps", 1500, 300, 8000))
    return Response(gen, mimetype="video/mp4",
                    headers={"Cache-Control": "no-store", "X-Accel-Buffering": "no"})


@app.get("/api/pantalla.h264")
@requiere_login
def api_pantalla_h264():
    """H.264 crudo fotograma a fotograma, para WebCodecs (el de menor retardo)."""
    gen = acciones.stream_pantalla_crudo(fps=_arg_rango("fps", 60, 5, 60),
                                         ancho=_arg_rango("ancho", 480, 320, 1280),
                                         kbps=_arg_rango("kbps", 800, 300, 8000))
    return Response(gen, mimetype="video/h264",
                    headers={"Cache-Control": "no-store", "X-Accel-Buffering": "no"})


# ---------------------------------------------------------------------------
# Avance de la compilacion de GroovyMAME (pi/web/compilacion.html)
# ---------------------------------------------------------------------------

_compilacion = {"total": 0, "visto": 0.0, "respuesta": None}


@app.get("/api/compilacion")
def api_compilacion():
    """PUBLICO a proposito (la pagina se mira sin login mientras compila).  Cuenta
    los .o de ~/groovymame-fuentes contra el total de .cpp/.cc y lee
    ~/compilar-cabina.log para saber si termino.  Recorrer el arbol (3 GB) cuesta,
    asi que la respuesta se guarda 10 s: sin eso cualquiera podia ponerse a
    pedirla en bucle y cargar el i3 mientras se juega."""
    if _compilacion["respuesta"] and time.time() - _compilacion["visto"] < 10:
        return jsonify(_compilacion["respuesta"])
    _compilacion["respuesta"] = _medir_compilacion()
    _compilacion["visto"] = time.time()
    return jsonify(_compilacion["respuesta"])


def _medir_compilacion():
    base = os.path.expanduser("~/groovymame-fuentes")
    log = os.path.expanduser("~/compilar-cabina.log")
    out = {"estado": "sin datos", "activo": False, "nobj": 0, "total": 0,
           "pct": 0, "ultima": "", "ts": int(time.time())}

    txt = ""
    try:
        with open(log, "rb") as f:
            f.seek(0, 2)
            f.seek(max(0, f.tell() - 4000))
            txt = f.read().decode("utf-8", "replace")
    except OSError:
        pass
    lineas = txt.strip().splitlines()
    out["ultima"] = lineas[-1][:120] if lineas else ""

    if "Listo:" in txt:
        out.update(estado="ok", pct=100)
        return out
    if any(m in txt for m in ("Fallo la compilacion", "No encuentro el binario",
                              "Compilo pero no arranca")):
        out.update(estado="fallo")
        return out
    if not os.path.isdir(base):
        return out

    contar_total = (_compilacion["total"] == 0)
    nobj = total = 0
    for _r, _d, ficheros in os.walk(base):
        for n in ficheros:
            if n.endswith(".o"):
                nobj += 1
            elif contar_total and n.endswith((".cpp", ".cc")):
                total += 1
    if contar_total:
        _compilacion["total"] = total
    total = _compilacion["total"]
    out.update(estado="compilando", activo=True, nobj=nobj, total=total,
               pct=round(nobj * 100.0 / total, 1) if total else 0)
    return out


def main():
    puerto = entero("puerto", 8808)
    # 127.0.0.1 por defecto (solo cloudflared local).  Si hay un Pi delante por
    # cable LAN, se pone en panel.conf la IP de ESE enlace punto-a-punto
    # (p.ej. escucha=10.55.0.2), nunca una LAN compartida sin confianza.
    escucha = CONF.get("escucha", "127.0.0.1").strip() or "127.0.0.1"
    # threaded=True para que los streams (SSE, video) no bloqueen al resto.
    app.run(host=escucha, port=puerto, threaded=True)


if __name__ == "__main__":
    main()
