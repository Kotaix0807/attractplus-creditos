#!/usr/bin/env python3
"""Trozos que comparten los modulos del panel (como creditos/comun.sh para shell).

Aqui viven: las rutas de la cabina, la carga de la configuracion (panel.conf),
el lanzador de ordenes del sistema y el registro de auditoria. No se ejecuta
suelto; lo importan servidor.py, estado.py, acciones.py y monedas.py.
"""

import hashlib
import os
import subprocess
import time

AQUI = os.path.dirname(os.path.abspath(__file__))
# El repo es el padre de panel/.  Sirve para 'git' y para localizar creditos/.
RAIZ_REPO = os.path.dirname(AQUI)

# La configuracion de AM+ en Linux es ~/.attract (en GroovyArcade es un enlace a
# shared/frontends/attract).  Es donde viven los ficheros de estado compartidos.
ATTRACT = os.path.expanduser("~/.attract")

# Ficheros de estado que escribe creditos.lua / moneyBank.py / el propio panel.
F_PANEL_CMD = os.path.join(ATTRACT, "panel_cmd")
F_MONEDAS = os.path.join(ATTRACT, "monedas.log")
F_CREDITOS_JUEGO = os.path.join(ATTRACT, "creditos_juego")
F_MONEDERO_SWITCH = os.path.join(ATTRACT, "monedero_switch")
F_JUEGO_ACTUAL = os.path.join(ATTRACT, "juego_actual")
F_MANTENIMIENTO = os.path.join(ATTRACT, "mantenimiento")
F_AUDITORIA = os.path.join(ATTRACT, "panel_auditoria.log")
F_PUNTAJES = os.path.join(ATTRACT, "puntajes.json")
F_FRONTEND_DETENIDO = os.path.join(ATTRACT, "frontend_detenido")
F_AJUSTES = os.path.join(ATTRACT, "panel_ajustes.json")
DIR_STATS = os.path.join(ATTRACT, "stats", "groovymame")


# ---------------------------------------------------------------------------
# Configuracion
# ---------------------------------------------------------------------------

_DEFECTOS = {
    "puerto": "8808",
    "escucha": "127.0.0.1",   # IP en que escucha el panel; la LAN del Pi si lo hay
    "valor_moneda": "100",
    "paso_tarifa": "100",
    "temp_aviso": "80",
    "usuario": "",        # vacio = no se exige usuario, solo la clave
    "clave_hash": "",
}


def _leer_conf_fichero(ruta):
    datos = {}
    try:
        with open(ruta, encoding="utf-8") as f:
            for linea in f:
                linea = linea.strip()
                if not linea or linea.startswith("#") or "=" not in linea:
                    continue
                k, v = linea.split("=", 1)
                datos[k.strip()] = v.strip()
    except OSError:
        pass
    return datos


def cargar_conf():
    """Devuelve la config efectiva.  Precedencia:
    entorno (PANEL_CLAVE) > ~/.config/panel.conf > panel/panel.conf (plantilla) > defecto.
    """
    conf = dict(_DEFECTOS)
    conf.update(_leer_conf_fichero(os.path.join(AQUI, "panel.conf")))
    conf.update(_leer_conf_fichero(os.path.expanduser("~/.config/panel.conf")))
    for k in list(conf):
        env = os.environ.get("PANEL_" + k.upper())
        if env is not None:
            conf[k] = env
    return conf


CONF = cargar_conf()


def entero(clave, por_defecto=0):
    try:
        return int(CONF.get(clave, por_defecto))
    except (TypeError, ValueError):
        return por_defecto


def clave_correcta(clave):
    """True si 'clave' coincide con clave_hash.  Si no hay hash configurado, se
    acepta 'arcade' como clave por defecto (y conviene cambiarla)."""
    h = CONF.get("clave_hash", "").strip()
    if not h:
        return clave == "arcade"
    return hashlib.sha256(clave.encode("utf-8")).hexdigest() == h


def usuario_correcto(usuario):
    """True si el usuario vale.  Si no hay 'usuario' configurado, no se exige
    (cualquiera, incluso vacio, vale: la seguridad la da la clave + Cloudflare)."""
    esperado = CONF.get("usuario", "").strip()
    return not esperado or (usuario or "").strip() == esperado


def leer_ajustes():
    """Ajustes que el propio panel escribe (retencion de logs, tarifa fijada por
    juego...).  Van en panel_ajustes.json, aparte de panel.conf (que es plantilla
    del repo y no se reescribe)."""
    import json
    try:
        with open(F_AJUSTES, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def guardar_ajustes(d):
    import json
    escribir_atomico(F_AJUSTES, json.dumps(d, ensure_ascii=False, indent=2))


# ---------------------------------------------------------------------------
# Ordenes del sistema y auditoria
# ---------------------------------------------------------------------------

def ejecutar(cmd, timeout=20, entrada=None):
    """Lanza una orden (lista de argumentos).  Devuelve (rc, salida, error).
    Nunca lanza excepcion: un fallo se refleja en rc!=0 y en 'error'.
    """
    try:
        p = subprocess.run(cmd, capture_output=True, text=True,
                           timeout=timeout, input=entrada)
        return p.returncode, p.stdout, p.stderr
    except FileNotFoundError:
        return 127, "", "no existe la orden: %s" % (cmd[0] if cmd else "?")
    except subprocess.TimeoutExpired:
        return 124, "", "la orden tardo demasiado"
    except Exception as ex:  # pragma: no cover
        return 1, "", str(ex)


def auditar(accion, detalle=""):
    """Apunta una accion en el log de auditoria (append, con fecha)."""
    try:
        os.makedirs(ATTRACT, exist_ok=True)
        with open(F_AUDITORIA, "a", encoding="utf-8") as f:
            f.write("%s  %s  %s\n" % (
                time.strftime("%Y-%m-%d %H:%M:%S"), accion, detalle))
    except OSError:
        pass


def escribir_atomico(ruta, texto):
    """Escribe a un temporal y renombra (atomico en POSIX), como hacen los demas
    scripts del proyecto: si esto se corta a medias, el fichero no queda roto."""
    tmp = ruta + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(texto)
    os.replace(tmp, ruta)
