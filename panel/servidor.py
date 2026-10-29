#!/usr/bin/env python3
"""El panel web de la cabina (backend real).  Ver docs/panel.md para el contrato.

Sirve la GUI de panel/static/ y expone la API JSON /api/...  Escucha SOLO en
127.0.0.1: quien lo saca al mundo es cloudflared.  Corre como 'arcade' (servicio
de usuario), con sudo NOPASSWD para las pocas acciones que piden root.

    python3 panel/servidor.py        # produccion (lo lanza panel.service)

Para desarrollar la GUI sin la cabina, usa panel/simulador.py (no necesita Flask).
"""

import functools
import json
import os
import secrets
import time

from flask import (Flask, Response, abort, jsonify, request, send_from_directory,
                   session)

import acciones
import botones
import estado
import monedas
from comun import ATTRACT, auditar, clave_correcta, entero, usuario_correcto

AQUI = os.path.dirname(os.path.abspath(__file__))
ESTATICO = os.path.join(AQUI, "static")

app = Flask(__name__, static_folder=None)


def _secreto():
    """Clave de sesion persistente: sobrevive a reinicios del servicio para no
    cerrar la sesion a cada rato.  Se guarda con permisos de solo-usuario."""
    ruta = os.path.join(ATTRACT, "panel_secret")
    try:
        if os.path.exists(ruta):
            return open(ruta, "rb").read()
        os.makedirs(ATTRACT, exist_ok=True)
        s = secrets.token_bytes(32)
        with open(ruta, "wb") as f:
            f.write(s)
        os.chmod(ruta, 0o600)
        return s
    except OSError:
        return secrets.token_bytes(32)


app.secret_key = _secreto()
app.config.update(SESSION_COOKIE_HTTPONLY=True, SESSION_COOKIE_SAMESITE="Lax")
# "Mantener sesion iniciada": una sesion permanente dura esto en vez de cerrarse
# al cerrar el navegador.
from datetime import timedelta  # noqa: E402
app.permanent_session_lifetime = timedelta(days=30)

# Freno sencillo de fuerza bruta en el login (un solo usuario).
_fallos = {"n": 0, "hasta": 0}


# ---------------------------------------------------------------------------
# Decoradores de autenticacion
# ---------------------------------------------------------------------------

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


@app.post("/api/logout")
def logout():
    session.clear()
    return jsonify({"ok": True})


@app.get("/api/sesion")
def sesion():
    return jsonify({"autenticado": bool(session.get("auth")),
                    "csrf": session.get("csrf") if session.get("auth") else None})


# ---------------------------------------------------------------------------
# Lectura (GET)
# ---------------------------------------------------------------------------

@app.get("/api/estado")
@requiere_login
def api_estado():
    return jsonify(estado.completo())


@app.get("/api/sistema")
@requiere_login
def api_sistema():
    return jsonify(estado.sistema())


@app.get("/api/volumen")
@requiere_login
def api_volumen_get():
    return jsonify(acciones.volumen_actual())


@app.get("/api/tiradas")
@requiere_login
def api_tiradas():
    return jsonify(monedas.tiradas(request.args.get("desde"),
                                   request.args.get("hasta")))


@app.get("/api/puntajes")
@requiere_login
def api_puntajes():
    return jsonify(estado.puntajes())


@app.get("/api/masjugados")
@requiere_login
def api_masjugados():
    orden = request.args.get("orden", "partidas")
    limite = request.args.get("limite", "20")
    limite = int(limite) if limite.isdigit() else 20
    return jsonify(estado.masjugados(orden, limite))


@app.get("/api/monedas")
@requiere_login
def api_monedas():
    return jsonify(monedas.agregar(request.args.get("desde"),
                                   request.args.get("hasta")))


@app.get("/api/juegos")
@requiere_login
def api_juegos():
    # Lista base de mas-jugados (da titulo y partidas); la visibilidad y la
    # tarifa se resuelven en el cliente/cabina.  Aqui damos lo barato de leer.
    vistos = {j["rom"]: j for j in estado.masjugados("partidas", 1000)}
    ocultos = _ocultos_actuales()
    salida = []
    for rom in sorted(set(list(vistos) + list(_roms_romlist()))):
        j = vistos.get(rom, {"rom": rom, "titulo": estado._titulo_rom(rom),
                             "partidas": 0})
        t = acciones.tarifa_actual(rom)
        salida.append({"rom": rom, "titulo": j["titulo"],
                       "partidas": j.get("partidas", 0),
                       "visible": rom not in ocultos,
                       "tarifa": {"pesos": t["pesos"], "texto": t["texto"]}})
    return jsonify(salida)


@app.get("/api/juegos/<rom>/tarifa")
@requiere_login
def api_juego_tarifa_get(rom):
    return jsonify(acciones.tarifa_actual(rom))


@app.get("/api/logs/retencion")
@requiere_login
def api_retencion_get():
    return jsonify(acciones.logs_retencion())


@app.get("/api/logs")
@requiere_login
def api_logs():
    fuente = request.args.get("fuente", "panel")
    n = request.args.get("lineas", "200")
    n = int(n) if n.isdigit() else 200
    acciones.limpiar_logs()   # aprovecha para aplicar la retencion configurada
    return jsonify({"fuente": fuente, "lineas": _leer_log(fuente, n)})


@app.get("/api/eventos")
@requiere_login
def api_eventos():
    def flujo():
        while True:
            d = estado.completo()
            chico = {"cpu": d["cpu"]["uso_pct"], "temperatura_c": d["temperatura_c"],
                     "juego_actual": d["juego_actual"], "hora": d["hora"]}
            yield "data: " + json.dumps(chico) + "\n\n"
            time.sleep(2)
    return Response(flujo(), mimetype="text/event-stream")


@app.get("/api/botones")
@requiere_login
def api_botones():
    """SSE: cada pulsacion de los mandos (no del teclado), para 'Test botones'."""
    auditar("test_botones")
    def flujo():
        for ev in botones.eventos_botones():
            yield "data: " + json.dumps(ev) + "\n\n"
    return Response(flujo(), mimetype="text/event-stream")


# ---------------------------------------------------------------------------
# Acciones (POST, con CSRF)
# ---------------------------------------------------------------------------

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


@app.post("/api/accion/mantenimiento")
@requiere_csrf
def api_mantenimiento():
    return jsonify(acciones.mantenimiento(cuerpo().get("activo")))


@app.post("/api/frontend/reiniciar")
@requiere_csrf
def api_frontend():
    return jsonify(acciones.frontend_reiniciar())


@app.post("/api/frontend/detener")
@requiere_csrf
def api_frontend_detener():
    return jsonify(acciones.frontend_detener())


@app.post("/api/frontend/iniciar")
@requiere_csrf
def api_frontend_iniciar():
    return jsonify(acciones.frontend_iniciar())


@app.post("/api/monedero/reiniciar")
@requiere_csrf
def api_monedero():
    return jsonify(acciones.monedero_reiniciar())


@app.post("/api/juego/salir")
@requiere_csrf
def api_salir():
    return jsonify(acciones.juego_salir())


@app.post("/api/juego/menu")
@requiere_csrf
def api_juego_menu():
    return jsonify(acciones.juego_menu())


@app.post("/api/frontend/menu")
@requiere_csrf
def api_frontend_menu():
    return jsonify(acciones.frontend_menu())


@app.post("/api/creditos")
@requiere_csrf
def api_creditos():
    return jsonify(acciones.creditos(cuerpo().get("n", 1)))


@app.post("/api/pantalla")
@requiere_csrf
def api_pantalla():
    return jsonify(acciones.pantalla(cuerpo().get("destino", "")))


@app.post("/api/volumen")
@requiere_csrf
def api_volumen():
    return jsonify(acciones.volumen(cuerpo().get("nivel", 80)))


@app.post("/api/puntajes/actualizar")
@requiere_csrf
def api_puntajes_act():
    return jsonify(acciones.puntajes_actualizar())


@app.post("/api/juegos/<rom>/visible")
@requiere_csrf
def api_juego_visible(rom):
    return jsonify(acciones.juego_visible(rom, cuerpo().get("visible", True)))


@app.post("/api/juegos/<rom>/tarifa")
@requiere_csrf
def api_juego_tarifa(rom):
    return jsonify(acciones.juego_tarifa(rom, cuerpo().get("pesos", 100)))


@app.post("/api/juegos/<rom>/eliminar")
@requiere_csrf
def api_juego_eliminar(rom):
    return jsonify(acciones.juego_eliminar(rom))


@app.post("/api/juegos/<rom>/reset-nvram")
@requiere_csrf
def api_juego_nvram(rom):
    return jsonify(acciones.juego_reset_nvram(rom))


@app.post("/api/juegos/<rom>/reset-puntajes")
@requiere_csrf
def api_juego_rpunt(rom):
    return jsonify(acciones.juego_reset_puntajes(rom))


@app.post("/api/juegos/subir")
@requiere_csrf
def api_juego_subir():
    f = request.files.get("archivo")
    if not f or not f.filename:
        return jsonify({"ok": False, "error": "falta el archivo"}), 400
    tmp = os.path.join("/tmp", "panel_sube_" + secrets.token_hex(6))
    f.save(tmp)
    return jsonify(acciones.juego_subir(tmp, f.filename))


@app.post("/api/monedas/cero")
@requiere_csrf
def api_monedas_cero():
    monedas.poner_a_cero()
    auditar("monedas_cero")
    return jsonify({"ok": True})


@app.get("/api/actualizar/estado")
@requiere_login
def api_act_estado():
    return jsonify(acciones.actualizar_estado())


@app.post("/api/actualizar")
@requiere_csrf
def api_actualizar():
    return jsonify(acciones.actualizar())


@app.post("/api/restaurar-fabrica")
@requiere_csrf
def api_restaurar():
    d = cuerpo()
    return jsonify(acciones.restaurar_fabrica(bool(d.get("records", True)),
                                              bool(d.get("stats", True))))


@app.post("/api/logs/retencion")
@requiere_csrf
def api_retencion_set():
    d = cuerpo()
    return jsonify(acciones.fijar_retencion(d.get("cada", 12),
                                            d.get("unidad", "horas")))


# ---------------------------------------------------------------------------
# Ficheros estaticos (la GUI de Eloy)
# ---------------------------------------------------------------------------

@app.get("/")
def raiz():
    return send_from_directory(ESTATICO, "index.html")


@app.get("/<path:ruta>")
def estatico(ruta):
    if ruta.startswith("api/"):
        abort(404)
    destino = os.path.normpath(os.path.join(ESTATICO, ruta))
    if not destino.startswith(ESTATICO) or not os.path.isfile(destino):
        abort(404)
    return send_from_directory(ESTATICO, ruta)


# ---------------------------------------------------------------------------
# Auxiliares
# ---------------------------------------------------------------------------

def _leer_log(fuente, n):
    import glob
    from comun import F_AUDITORIA, RAIZ_REPO
    rutas = {
        "auditoria": [F_AUDITORIA],
        "attract": [os.path.join(ATTRACT, "last_run.log"),
                    os.path.join(ATTRACT, "attract.log")],
        "monedero": sorted(glob.glob(os.path.join(RAIZ_REPO, "arduino", "log*.txt")))[-1:],
        "panel": [],
    }
    for ruta in rutas.get(fuente, []):
        if ruta and os.path.exists(ruta):
            try:
                return open(ruta, encoding="utf-8", errors="replace").read().splitlines()[-n:]
            except OSError:
                pass
    if fuente == "panel":
        rc, out, _ = acciones.ejecutar(
            ["journalctl", "--user", "-u", "panel.service", "-n", str(n), "--no-pager"])
        return out.splitlines() if rc == 0 else ["(sin log)"]
    return ["(sin log)"]


def _ocultos_actuales():
    ruta = os.path.join(ATTRACT, "displays.cfg")
    try:
        for l in open(ruta, encoding="utf-8"):
            if "Name" in l and "not_equals" in l and l.strip().startswith("rule"):
                trozo = l.split("not_equals", 1)[1].strip()
                return set(x for x in trozo.split("|") if x)
    except OSError:
        pass
    return set()


def _roms_romlist():
    ruta = os.path.join(ATTRACT, "romlists", "groovymame.txt")
    roms = []
    try:
        for l in open(ruta, encoding="utf-8"):
            if l and not l.startswith("#") and ";" in l:
                roms.append(l.split(";", 1)[0])
    except OSError:
        pass
    return roms


def main():
    from comun import CONF
    puerto = entero("puerto", 8808)
    # 127.0.0.1 por defecto (solo cloudflared local).  Si hay un Pi delante por
    # cable LAN, se pone en panel.conf la IP de ESE enlace punto-a-punto
    # (p.ej. escucha=10.55.0.2), nunca una LAN compartida sin confianza.
    escucha = CONF.get("escucha", "127.0.0.1").strip() or "127.0.0.1"
    # threaded=True para que el SSE de /api/eventos no bloquee al resto.
    app.run(host=escucha, port=puerto, threaded=True)


if __name__ == "__main__":
    main()
