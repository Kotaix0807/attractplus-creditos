#!/usr/bin/env python3
"""Las acciones del panel (todo lo que CAMBIA algo en la cabina).

Dos clases de accion, a proposito (ver docs/panel.md):
  - de sistema: se ejecutan aqui mismo, como 'arcade' con sudo NOPASSWD o con
    systemctl --user.
  - de MAME (meter creditos, salir del juego): solo creditos.lua puede tocar el
    ioport o cerrar la maquina, asi que se dejan como orden en ~/.attract/panel_cmd
    y el Lua las aplica en su bucle por-frame.

Cada funcion devuelve un dict {"ok": bool, ...} y queda registrada en el log de
auditoria.  Nunca lanza excepcion hacia el servidor.
"""

import glob
import os
import shutil
import time

from comun import (ATTRACT, DIR_STATS, F_ARDUINO_FIFO, F_AUDITORIA, F_BRILLO,
                   F_FRONTEND_DETENIDO, F_MANTENIMIENTO, F_MONEDAS, F_PANEL_CMD,
                   F_PUNTAJES, F_TARIFA_GLOBAL, RAIZ_REPO, auditar, ejecutar, entero,
                   escribir_atomico, leer_ajustes, guardar_ajustes)

DIR_MAME = os.path.expanduser("~/.mame")


def _ok(**extra):
    d = {"ok": True}
    d.update(extra)
    return d


def _err(msg):
    return {"ok": False, "error": msg}


def _en_mantenimiento():
    return os.path.exists(F_MANTENIMIENTO)


def _exige_mantenimiento():
    if not _en_mantenimiento():
        return _err("esta accion solo se puede hacer en modo mantenimiento "
                    "(para el frontend primero)")
    return None


# ---------------------------------------------------------------------------
# Ordenes a MAME (por fichero)
# ---------------------------------------------------------------------------

def _enviar_mame(orden):
    """Anade una orden al buzon que lee creditos.lua.  Se usa append: el Lua
    renombra el fichero antes de leerlo, asi no se pierde nada si llegan dos
    ordenes seguidas."""
    try:
        os.makedirs(ATTRACT, exist_ok=True)
        with open(F_PANEL_CMD, "a", encoding="utf-8") as f:
            f.write(orden.strip() + "\n")
        return True
    except OSError:
        return False


def creditos(n):
    try:
        n = int(n)
    except (TypeError, ValueError):
        return _err("n no es un numero")
    if n < 1 or n > 20:
        return _err("n fuera de rango (1-20)")
    auditar("creditos", str(n))
    if not _enviar_mame("insertar %d" % n):
        return _err("no se pudo escribir la orden")
    return _ok(nota="se inyectaran si hay un juego en marcha")


def juego_salir():
    auditar("juego_salir")
    if not _enviar_mame("salir"):
        return _err("no se pudo escribir la orden")
    return _ok()


# El menu de MAME se abre con su tecla UI_MENU (TAB por defecto).  No va por
# panel_cmd porque no toca el ioport ni cierra la maquina: es una pulsacion a
# nivel de X, que mandamos con XTEST (como un teclado de verdad).  Verificado en
# la cabina: TAB abre/cierra el menu -- con el menu abierto MAME ignora las
# monedas, y al cerrarlo vuelven a entrar.  Corremos como 'arcade', dueno de la
# sesion X, asi que :0 se abre con ~/.Xauthority.
_XK_TAB = 0xff09


def _tecla_x(keysym):
    """Manda una pulsacion (down+up) de una tecla a la pantalla :0 con XTEST.
    Devuelve True si se envio."""
    import ctypes
    import ctypes.util
    os.environ.setdefault("DISPLAY", ":0")
    os.environ.setdefault("XAUTHORITY", os.path.expanduser("~/.Xauthority"))
    nx, nt = ctypes.util.find_library("X11"), ctypes.util.find_library("Xtst")
    if not nx or not nt:
        return False
    try:
        X, T = ctypes.CDLL(nx), ctypes.CDLL(nt)
        X.XOpenDisplay.restype = ctypes.c_void_p            # punteros de 64 bits:
        X.XKeysymToKeycode.argtypes = [ctypes.c_void_p, ctypes.c_ulong]  # hay que
        X.XKeysymToKeycode.restype = ctypes.c_ubyte         # declararlos o ctypes
        X.XFlush.argtypes = [ctypes.c_void_p]               # los trunca a int y
        X.XCloseDisplay.argtypes = [ctypes.c_void_p]        # revienta.
        T.XTestFakeKeyEvent.argtypes = [ctypes.c_void_p, ctypes.c_uint,
                                        ctypes.c_int, ctypes.c_ulong]
        d = X.XOpenDisplay(os.environ["DISPLAY"].encode())
        if not d:
            return False
        try:
            kc = X.XKeysymToKeycode(d, keysym)
            if not kc:
                return False
            # Hay que MANTENER la tecla pulsada un momento: MAME sondea el
            # teclado a ~60 Hz, asi que un down+up instantaneo cae entre dos
            # sondeos y no lo registra (medido: con 0 ms el menu no se abre, con
            # ~80 ms si).  Es lo que dura una pulsacion humana.
            import time
            T.XTestFakeKeyEvent(d, kc, 1, 0)
            X.XFlush(d)
            time.sleep(0.08)
            T.XTestFakeKeyEvent(d, kc, 0, 0)
            X.XFlush(d)
            return True
        finally:
            X.XCloseDisplay(d)
    except OSError:
        return False


def _mame_corriendo():
    rc, _, _ = ejecutar(["pgrep", "-x", "mame"], timeout=5)
    return rc == 0


def juego_menu():
    """Abre (o cierra) el menu de MAME con TAB.  Solo con un juego en marcha:
    sin el, la tecla iria al frontend.  Se navega con los controles de la
    cabina."""
    auditar("juego_menu")
    if not _mame_corriendo():
        return _err("no hay ningun juego en marcha")
    if _tecla_x(_XK_TAB):
        return _ok(nota="menu de MAME (TAB); navega con los controles de la cabina")
    return _err("no se pudo enviar la tecla a la pantalla")


def frontend_menu():
    """Abre el menu de configuracion de Attract-Mode Plus.  Su accion
    'configure' es TAB, la misma tecla -- pero al frente esta AM+ (no hay
    juego), asi que TAB abre SU menu, no el de MAME.  Por eso va al reves que
    juego_menu: solo sin juego en marcha."""
    auditar("frontend_menu")
    if _mame_corriendo():
        return _err("hay un juego en marcha; el menu de AM+ es para el frontend")
    if _tecla_x(_XK_TAB):
        return _ok(nota="menu de Attract-Mode (TAB); navega con los controles de la cabina")
    return _err("no se pudo enviar la tecla a la pantalla")


# Joystick virtual (panel tester).  En JUEGO cualquier control se acciona por el
# ioport, cosa que solo puede creditos.lua -> va por panel_cmd ("pulsar <ctrl>").
# En el MENU no hay juego y el frontend lee teclas, asi que solo tienen sentido
# navegar y salir, y se mandan por XTEST.  Los nombres de control son los mismos
# que usa la GUI (tester.html) y creditos.lua.
_CONTROLES = {
    "salir", "start1", "start2",
    "p1_up", "p1_down", "p1_left", "p1_right",
    "p1_b1", "p1_b2", "p1_b3", "p1_b4", "p1_b5", "p1_b6",
    "p2_up", "p2_down", "p2_left", "p2_right",
    "p2_b1", "p2_b2", "p2_b3", "p2_b4", "p2_b5", "p2_b6",
}
# keysyms X para el menu (lo que AM+ lee por teclado): flechas, Return, Esc.
_XK_MENU = {"p1_up": 0xff52, "p1_down": 0xff54, "p1_left": 0xff51, "p1_right": 0xff53,
            "start1": 0xff0d, "p1_b1": 0xff0d, "salir": 0xff1b}


def pulsar(control):
    control = (control or "").strip()
    if control not in _CONTROLES:
        return _err("control desconocido: %r" % control)
    auditar("pulsar", control)
    if _mame_corriendo():
        # 'salir' cierra la maquina; el resto se acciona por el ioport en creditos.lua
        orden = "salir" if control == "salir" else ("pulsar " + control)
        if not _enviar_mame(orden):
            return _err("no se pudo escribir la orden")
        return _ok(nota="en el juego")
    ks = _XK_MENU.get(control)
    if ks is None:
        return _ok(nota="en el menú ese control no hace nada (usa cruceta / START / SALIR)")
    if _tecla_x(ks):
        return _ok(nota="en el menú")
    return _err("no se pudo enviar la tecla a la pantalla")


# ---------------------------------------------------------------------------
# Sistema
# ---------------------------------------------------------------------------

def reiniciar():
    auditar("reiniciar")
    rc, _, err = ejecutar(["sudo", "-n", "systemctl", "reboot"], timeout=10)
    return _ok() if rc == 0 else _err(err or "fallo al reiniciar")


def apagar():
    auditar("apagar")
    rc, _, err = ejecutar(["sudo", "-n", "systemctl", "poweroff"], timeout=10)
    return _ok() if rc == 0 else _err(err or "fallo al apagar")


def suspender():
    """Suspende la cabina (S3).  A diferencia de apagar (S5), de aqui SI se puede
    volver a encender por Wake-on-LAN: este VAIO corta la corriente de la tarjeta
    de red en apagado total, pero la mantiene en suspension con el cargador puesto.
    Por eso el 'apagar remoto' util es este."""
    auditar("suspender")
    rc, _, err = ejecutar(["sudo", "-n", "systemctl", "suspend"], timeout=10)
    return _ok() if rc == 0 else _err(err or "fallo al suspender")


def _matar_frontend():
    for nombre in ("attractplus", "attractplus-x11", "attractplus-kms"):
        ejecutar(["pkill", "-x", nombre], timeout=5)


def frontend_reiniciar():
    """Mata el frontend; el wrapper de ~/.xinitrc lo relanza solo."""
    auditar("frontend_reiniciar")
    if _en_mantenimiento() or os.path.exists(F_FRONTEND_DETENIDO):
        return _err("el frontend esta parado a proposito (mantenimiento o 'detener')")
    _matar_frontend()
    return _ok()


def frontend_detener():
    """Para el frontend y lo DEJA parado (centinela aparte del de mantenimiento).
    A diferencia de modo mantenimiento, NO abre la ventana de gestion de juegos."""
    auditar("frontend_detener")
    try:
        open(F_FRONTEND_DETENIDO, "w").close()
    except OSError as ex:
        return _err(str(ex))
    _matar_frontend()   # el wrapper vera el centinela y no lo relanzara
    return _ok(detenido=True)


def frontend_iniciar():
    """Quita el centinela de 'detener'; el wrapper vuelve a lanzar el frontend."""
    auditar("frontend_iniciar")
    try:
        if os.path.exists(F_FRONTEND_DETENIDO):
            os.remove(F_FRONTEND_DETENIDO)
    except OSError as ex:
        return _err(str(ex))
    if _en_mantenimiento():
        return _ok(detenido=False,
                   nota="sigue parado por modo mantenimiento; sal de mantenimiento")
    return _ok(detenido=False)


def _fifo_arduino(linea):
    """Escribe una linea en el FIFO que drena moneyBank.py (unico dueno del
    puerto serie). No bloquea: con O_NONBLOCK, si el demonio no esta leyendo da
    ENXIO en vez de colgarse."""
    fd = os.open(F_ARDUINO_FIFO, os.O_WRONLY | os.O_NONBLOCK)
    try:
        os.write(fd, (linea + "\n").encode())
    finally:
        os.close(fd)


def monedero_reiniciar():
    """Apaga el monedero, espera 2 s y lo enciende otra vez: es el canal 13 del
    PCA (comando R0/R1 del Arduino). moneyBank.py es el unico que escribe el
    puerto, asi que la orden va por su FIFO y el demonio reenvia las lineas R; la
    espera de 2 s la hace el panel."""
    auditar("monedero_reiniciar")
    try:
        _fifo_arduino("R0")
        time.sleep(2)
        _fifo_arduino("R1")
    except OSError as e:
        return _err("no pude hablar con el monedero (demonio parado?): %s" % e)
    return _ok()


def mantenimiento(activo):
    """Entra o sale de modo mantenimiento.  En mantenimiento el frontend se para
    (el wrapper de .xinitrc lo deja parado mientras exista el fichero centinela),
    lo que da una ventana segura para tocar la lista de juegos, tarifas, etc."""
    activo = bool(activo)
    auditar("mantenimiento", "on" if activo else "off")
    try:
        if activo:
            open(F_MANTENIMIENTO, "w").close()
            _matar_frontend()   # el wrapper vera el fichero y no lo relanzara
        else:
            if os.path.exists(F_MANTENIMIENTO):
                os.remove(F_MANTENIMIENTO)
            # al desaparecer el fichero, el wrapper relanza el frontend solo
    except OSError as ex:
        return _err(str(ex))
    return _ok(mantenimiento=activo)


def _pantalla_bin():
    for c in ("/usr/local/bin/pantalla-auto.sh",
              os.path.join(RAIZ_REPO, "pantalla-auto.sh")):
        if os.path.exists(c):
            return c
    return None


def pantalla(destino):
    if destino not in ("crt", "panel"):
        return _err("destino debe ser 'crt' o 'panel'")
    binp = _pantalla_bin()
    if not binp:
        return _err("no encuentro pantalla-auto.sh")
    auditar("pantalla", destino)
    rc, _, err = ejecutar(["sudo", "-n", binp, destino], timeout=20)
    return _ok() if rc == 0 else _err(err or "fallo al conmutar la pantalla")


def volumen(nivel):
    try:
        nivel = int(nivel)
    except (TypeError, ValueError):
        return _err("nivel no es un numero")
    nivel = max(0, min(100, nivel))
    auditar("volumen", str(nivel))
    rc, _, err = ejecutar(["amixer", "-q", "sset", "Master", "%d%%" % nivel, "unmute"],
                         timeout=10)
    return _ok(nivel=nivel) if rc == 0 else _err(err or "fallo al cambiar el volumen")


def volumen_actual():
    """Lee el nivel actual de 'Master' (para que el slider arranque donde toca)."""
    rc, out, _ = ejecutar(["amixer", "sget", "Master"], timeout=10)
    nivel = None
    if rc == 0:
        import re
        m = re.search(r"\[(\d+)%\]", out)
        if m:
            nivel = int(m.group(1))
    return {"ok": nivel is not None, "nivel": nivel}


def prueba_sonido(canal):
    """Reproduce un tono suave en los altavoces de la cabina para probar los
    canales: 'izquierda', 'derecha' o 'ambos' (estereo: do5 a la izquierda, mi5 a
    la derecha). Sirve para diagnosticar un canal mudo sin tener que lanzar un juego."""
    canal = (canal or "ambos").strip().lower()
    if canal not in ("izquierda", "derecha", "ambos"):
        return _err("canal invalido (izquierda|derecha|ambos)")
    auditar("prueba_sonido", canal)
    # paplay (compat PipeWire) necesita el runtime del usuario.
    os.environ.setdefault("XDG_RUNTIME_DIR", "/run/user/%d" % os.getuid())
    import wave
    import math
    import array
    import tempfile
    sr = 48000
    n = int(sr * 1.2)
    amp = 0.33
    def tono(freq, i):
        env = min(1.0, i / (0.04 * sr), (n - i) / (0.04 * sr))   # fade 40 ms: sin clics
        return int(amp * env * math.sin(2 * math.pi * freq * i / sr) * 32767)
    a = array.array("h")
    for i in range(n):
        izq = tono(523.25, i) if canal in ("izquierda", "ambos") else 0
        der = tono(659.25 if canal == "ambos" else 523.25, i) if canal in ("derecha", "ambos") else 0
        a.append(izq)
        a.append(der)
    fd, ruta = tempfile.mkstemp(suffix=".wav")
    os.close(fd)
    try:
        w = wave.open(ruta, "wb")
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(a.tobytes())
        w.close()
        rc, _, err = ejecutar(["paplay", ruta], timeout=8)
    finally:
        try:
            os.remove(ruta)
        except OSError:
            pass
    return _ok(canal=canal) if rc == 0 else _err(err or "no se pudo reproducir (paplay)")


# ---------------------------------------------------------------------------
# Puntajes y monedas
# ---------------------------------------------------------------------------

def puntajes_actualizar():
    """Re-ejecuta puntajes.py, que reescribe ~/.attract/puntajes.json."""
    auditar("puntajes_actualizar")
    script = os.path.join(RAIZ_REPO, "creditos", "puntajes.py")
    if not os.path.exists(script):
        return _err("no encuentro creditos/puntajes.py")
    rc, out, err = ejecutar(["python3", script], timeout=600)
    return _ok(salida=out[-2000:]) if rc == 0 else _err((err or out)[-2000:])


# ---------------------------------------------------------------------------
# Opciones de arranque por juego (arranque.dat). Las lee creditos.lua en cada
# lanzamiento, asi que un cambio aplica al PROXIMO arranque de ese juego, sin
# reiniciar nada. Se escribe con escribir_ajuste.py (una clave, atomico).
# ---------------------------------------------------------------------------
F_ARRANQUE = os.path.join(RAIZ_REPO, "creditos", "arranque.dat")

# clave -> (tipo, etiqueta). bool_on: el defecto es encendido (nvram, negro);
# bool_off: el defecto es apagado (contador, indicador...).
ARRANQUE_CLAVES = {
    "nvram":     ("bool_on",  "Guardar NVRAM (creditos/records entre sesiones)"),
    "negro":     ("bool_on",  "Tapar la pantalla en negro al arrancar"),
    "contador":  ("bool_off", "Mostrar creditos en pantalla"),
    "indicador": ("bool_off", "Mostrar el cartel '>> CARGANDO AL N%'"),
    "auto":      ("bool_off", "Alargar el arranque hasta detectar la placa lista"),
    "limite":    ("num",      "Limite de creditos (0 = sin limite)"),
    "segundos":  ("num",      "Segundos de arranque tapado (del juego)"),
    "velocidad": ("num",      "Velocidad al cargar (%, 0 = sin freno)"),
    "barrido":   ("num",      "Segundos hasta limpiar creditos viejos de la NVRAM"),
}


def _arranque_parse():
    datos = {}
    try:
        with open(F_ARRANQUE, encoding="utf-8") as f:
            for linea in f:
                linea = linea.strip()
                if not linea or linea.startswith("#"):
                    continue
                campos = linea.split()
                juego = campos[0].lower()
                datos[juego] = {}
                for kv in campos[1:]:
                    if "=" in kv:
                        k, v = kv.split("=", 1)
                        datos[juego][k] = v
    except OSError:
        pass
    return datos


def arranque_opciones(rom):
    """Ajustes actuales de arranque.dat para <rom> (y la linea 'defecto')."""
    d = _arranque_parse()
    claves = {k: {"tipo": t, "etiqueta": e} for k, (t, e) in ARRANQUE_CLAVES.items()}
    return {"rom": rom, "juego": d.get((rom or "").lower(), {}),
            "defecto": d.get("defecto", {}), "claves": claves}


def arranque_fijar(rom, clave, valor):
    """Pone UNA clave de arranque.dat para <rom>, via escribir_ajuste.py."""
    if clave not in ARRANQUE_CLAVES:
        return _err("opcion no permitida: %s" % clave)
    if not rom or "/" in rom or " " in rom or ".." in rom:
        return _err("rom invalido")
    valor = str(valor).strip()
    if ARRANQUE_CLAVES[clave][0].startswith("bool"):
        if valor not in ("0", "1"):
            return _err("valor booleano invalido (0/1): %r" % valor)
    else:
        try:
            float(valor)
        except ValueError:
            return _err("valor numerico invalido: %r" % valor)
    auditar("arranque_fijar %s %s=%s" % (rom, clave, valor))
    script = os.path.join(RAIZ_REPO, "creditos", "escribir_ajuste.py")
    rc, out, err = ejecutar(["python3", script, F_ARRANQUE, rom, clave, valor],
                            timeout=15)
    if rc != 0:
        return _err((err or out or "fallo escribir_ajuste.py")[-500:])
    return _ok(**arranque_opciones(rom))


# ---------------------------------------------------------------------------
# Gestion de juegos (exigen modo mantenimiento: el frontend reescribe sus .cfg)
# ---------------------------------------------------------------------------

def _rompath():
    """Primer directorio del rompath de MAME que exista y sea escribible."""
    mame = shutil.which("mame") or shutil.which("groovymame")
    if not mame:
        return None
    rc, out, _ = ejecutar([mame, "-showconfig"], timeout=8)
    if rc != 0:
        return None
    crudo = ""
    for linea in out.splitlines():
        if linea.startswith("rompath"):
            crudo = linea.split(None, 1)[1].strip() if " " in linea else ""
            break
    crudo = crudo.replace("$HOME", os.path.expanduser("~"))
    for trozo in crudo.split(";"):
        trozo = trozo.strip()
        if trozo and os.path.isdir(trozo) and os.access(trozo, os.W_OK):
            return trozo
    return None


def _reconstruir_romlist():
    """Reconstruye la lista de juegos.  Incluye hypseus si esta definido, porque
    reconstruir con un solo emulador borraria Dragon's Lair (ver CLAUDE.md)."""
    am = (shutil.which("attractplus") or shutil.which("attractplus-x11")
          or os.path.join(RAIZ_REPO, "attractplus"))
    if not os.path.exists(am):
        return False, "no encuentro attractplus"
    emuladores = ["groovymame"]
    if os.path.exists(os.path.join(ATTRACT, "emulators", "hypseus.cfg")):
        emuladores.append("hypseus")
    rc, out, err = ejecutar([am, "--build-romlist"] + emuladores
                            + ["-o", "groovymame"], timeout=300)
    return rc == 0, (err or out)[-2000:]


def juego_subir(ruta_tmp, nombre):
    """Mueve un .zip/.7z subido al rompath y reconstruye la lista."""
    g = _exige_mantenimiento()
    if g:
        return g
    if not nombre.lower().endswith((".zip", ".7z")):
        return _err("solo .zip o .7z")
    destino_dir = _rompath()
    if not destino_dir:
        return _err("no encuentro un rompath escribible")
    rom = os.path.splitext(os.path.basename(nombre))[0]
    destino = os.path.join(destino_dir, os.path.basename(nombre))
    try:
        shutil.move(ruta_tmp, destino)
    except OSError as ex:
        return _err(str(ex))
    auditar("juego_subir", rom)
    ok, salida = _reconstruir_romlist()
    return _ok(rom=rom, salida=salida) if ok else _err(salida)


def juego_eliminar(rom):
    g = _exige_mantenimiento()
    if g:
        return g
    destino_dir = _rompath()
    if not destino_dir:
        return _err("no encuentro el rompath")
    retirados = os.path.join(destino_dir, "retirados")
    os.makedirs(retirados, exist_ok=True)
    movido = False
    for ext in (".zip", ".7z"):
        origen = os.path.join(destino_dir, rom + ext)
        if os.path.exists(origen):
            shutil.move(origen, os.path.join(retirados, rom + ext))
            movido = True
    if not movido:
        return _err("no encuentro el ROM de %s" % rom)
    auditar("juego_eliminar", rom)
    ok, salida = _reconstruir_romlist()
    return _ok(rom=rom, salida=salida) if ok else _err(salida)


def _ruta_displays():
    return os.path.join(ATTRACT, "displays.cfg")


def juego_visible(rom, visible):
    """Oculta o muestra un juego mediante el global_filter de displays.cfg.
    Hay que hacerlo con el frontend parado (AM+ reescribe displays.cfg al salir)."""
    g = _exige_mantenimiento()
    if g:
        return g
    ruta = _ruta_displays()
    if not os.path.exists(ruta):
        return _err("no encuentro displays.cfg")
    try:
        lineas = open(ruta, encoding="utf-8").read().splitlines()
    except OSError as ex:
        return _err(str(ex))

    # Busca una linea  'rule  Name not_equals a|b|c'  dentro de global_filter.
    idx = None
    for i, l in enumerate(lineas):
        if "Name" in l and "not_equals" in l and l.strip().startswith("rule"):
            idx = i
            break
    ocultos = set()
    sangria = "    "
    if idx is not None:
        trozo = lineas[idx].split("not_equals", 1)[1].strip()
        ocultos = set(x for x in trozo.split("|") if x)
        sangria = lineas[idx][:len(lineas[idx]) - len(lineas[idx].lstrip())]

    if visible:
        ocultos.discard(rom)
    else:
        ocultos.add(rom)

    nueva = "%srule                    Name not_equals %s" % (
        sangria, "|".join(sorted(ocultos)))
    if idx is not None:
        lineas[idx] = nueva
    else:
        return _err("displays.cfg no tiene un global_filter con Name not_equals; "
                    "hay que anadirlo a mano la primera vez")
    try:
        with open(ruta, "w", encoding="utf-8") as f:
            f.write("\n".join(lineas) + "\n")
    except OSError as ex:
        return _err(str(ex))
    auditar("juego_visible", "%s=%s" % (rom, visible))
    return _ok(rom=rom, visible=bool(visible), ocultos=sorted(ocultos))


def juego_tarifa(rom, pesos):
    """Fija la tarifa (coinage) de un juego lanzando la pasada fijar_tarifa.sh."""
    g = _exige_mantenimiento()
    if g:
        return g
    try:
        pesos = int(pesos)
    except (TypeError, ValueError):
        return _err("pesos no es un numero")
    rom = os.path.basename(rom)   # nombre de set, sin separadores de ruta
    # Fichero por juego que lee creditos.lua; MANDA sobre tarifa_global. Asi un
    # juego con tarifa propia cobra aunque el free play global este puesto.
    pj = os.path.join(os.path.dirname(F_TARIFA_GLOBAL), "tarifa_juego", rom)
    # pesos<=0 = quitar el override: el juego vuelve a seguir la tarifa global.
    if pesos <= 0:
        try:
            os.remove(pj)
        except FileNotFoundError:
            pass
        aj = leer_ajustes()
        aj.setdefault("tarifas", {}).pop(rom, None)
        guardar_ajustes(aj)
        auditar("juego_tarifa", "%s=global" % rom)
        return _ok(pesos=0, modo="global")
    script = os.path.join(RAIZ_REPO, "creditos", "fijar_tarifa.sh")
    if not os.path.exists(script):
        return _err("no encuentro creditos/fijar_tarifa.sh")
    auditar("juego_tarifa", "%s=%d" % (rom, pesos))
    rc, out, err = ejecutar(["bash", script, rom, str(pesos)], timeout=60)
    if rc != 0:
        return _err((err or out)[-1500:])
    os.makedirs(os.path.dirname(pj), exist_ok=True)
    escribir_atomico(pj, str(pesos))
    # Recuerda el valor fijado, para enseñarlo sin relanzar MAME (leer el DIP del
    # .cfg y traducirlo a pesos exigiria arrancar el juego).
    aj = leer_ajustes()
    aj.setdefault("tarifas", {})[rom] = pesos
    guardar_ajustes(aj)
    return _ok(salida=out[-1500:], pesos=pesos)


def tarifa_actual(rom):
    """Tarifa en pesos de un juego.  Es la ultima fijada desde el panel; si nunca
    se cambio, el valor base (la cabina fuerza 1 moneda/credito = un paso)."""
    base = entero("paso_tarifa", 100)
    pesos = leer_ajustes().get("tarifas", {}).get(rom, base)
    monedas = max(1, pesos // base) if base else 1
    return {"rom": rom, "pesos": pesos,
            "texto": "%d moneda%s / 1 crédito" % (monedas, "" if monedas == 1 else "s")}


def tarifa_global_actual():
    """La tarifa GLOBAL que aplica a TODOS los juegos (la lee creditos.lua al
    lanzar): 'freeplay', N pesos, o 'defecto' (sin fichero = cada juego como
    venga / 1 moneda por credito)."""
    try:
        with open(F_TARIFA_GLOBAL, encoding="utf-8") as f:
            t = f.read().strip().lower()
    except OSError:
        t = ""
    if t == "freeplay":
        return {"modo": "freeplay"}
    try:
        pesos = int(t)
    except ValueError:
        pesos = 0
    if pesos >= 100:
        return {"modo": "pesos", "pesos": pesos}
    return {"modo": "defecto"}


def fijar_tarifa_global(valor):
    """Fija la tarifa global.  valor: 'freeplay', un numero de pesos (>=100, en
    pasos de 100) o 'defecto'/'' para quitarla."""
    v = str(valor if valor is not None else "").strip().lower()
    if v in ("", "defecto", "default"):
        try:
            os.remove(F_TARIFA_GLOBAL)
        except OSError:
            pass
        auditar("tarifa_global", "defecto")
        return _ok(**tarifa_global_actual())
    if v in ("freeplay", "free"):
        contenido = "freeplay"
    else:
        try:
            pesos = int(float(v))
        except ValueError:
            return _err("valor no valido (freeplay, pesos o defecto)")
        if pesos < 100 or pesos % 100 != 0:
            return _err("los pesos van en pasos de 100, minimo 100")
        contenido = str(pesos)
    try:
        os.makedirs(ATTRACT, exist_ok=True)
        with open(F_TARIFA_GLOBAL, "w", encoding="utf-8") as f:
            f.write(contenido + "\n")
    except OSError as e:
        return _err("no se pudo escribir: %s" % e)
    auditar("tarifa_global", contenido)
    return _ok(**tarifa_global_actual())


def brillo_actual():
    """Brillo global de los LEDs (0..255) que escala TODO lo que corra en el
    Arduino.  Sin fichero = la placa va a 255 (maximo), que es su valor por
    defecto; lo aplica moneyBank.py mandando L<n>."""
    try:
        with open(F_BRILLO, encoding="utf-8") as f:
            n = max(0, min(255, int(f.read().strip())))
    except (OSError, ValueError):
        n = 255
    return {"brillo": n}


def fijar_brillo(valor):
    """Fija el brillo global de los LEDs (0..255).  Lo recoge moneyBank.py en su
    ronda (~0.1 s) y lo manda a la placa como L<n>."""
    try:
        n = int(valor)
    except (TypeError, ValueError):
        return _err("valor no valido (0..255)")
    n = max(0, min(255, n))
    try:
        os.makedirs(ATTRACT, exist_ok=True)
        escribir_atomico(F_BRILLO, str(n) + "\n")
    except OSError as e:
        return _err("no se pudo escribir: %s" % e)
    auditar("brillo_leds", str(n))
    return _ok(brillo=n)


def juego_reset_nvram(rom):
    g = _exige_mantenimiento()
    if g:
        return g
    d = os.path.join(DIR_MAME, "nvram", rom)
    if os.path.isdir(d):
        shutil.rmtree(d, ignore_errors=True)
    auditar("juego_reset_nvram", rom)
    return _ok(rom=rom)


def juego_reset_puntajes(rom):
    g = _exige_mantenimiento()
    if g:
        return g
    borrados = []
    for ruta in (os.path.join(DIR_MAME, "hiscore", rom + ".hi"),):
        if os.path.exists(ruta):
            os.remove(ruta)
            borrados.append(ruta)
    auditar("juego_reset_puntajes", rom)
    return _ok(rom=rom, borrados=borrados)


# ---------------------------------------------------------------------------
# Actualizar el repositorio (la accion mas delicada)
# ---------------------------------------------------------------------------

def actualizar_estado():
    """Lo que un 'git pull' cambiaria, para ensenarlo ANTES de tocar nada."""
    rc, out, _ = ejecutar(["git", "-C", RAIZ_REPO, "status", "--porcelain"], timeout=10)
    modificados = [l[3:] for l in out.splitlines() if l.strip()]
    ejecutar(["git", "-C", RAIZ_REPO, "fetch"], timeout=30)
    rc2, detras, _ = ejecutar(["git", "-C", RAIZ_REPO, "rev-list", "--count",
                               "HEAD..@{u}"], timeout=10)
    return {"modificados": modificados,
            "commits_detras": int(detras.strip()) if detras.strip().isdigit() else 0}


def actualizar():
    """Actualiza el repo protegiendo los cambios locales (sobre todo arranque.dat,
    que puede llevar calibracion medida que solo vive en la cabina).

    Estrategia prudente: respalda TODO lo modificado con fecha, y hace
    'git pull --rebase --autostash'.  Si hay conflicto, aborta y avisa; no
    intenta fusionar a ciegas.
    """
    g = _exige_mantenimiento()
    if g:
        return g
    auditar("actualizar")
    # 1) respaldo de lo modificado
    rc, out, _ = ejecutar(["git", "-C", RAIZ_REPO, "status", "--porcelain"], timeout=10)
    modificados = [l[3:] for l in out.splitlines() if l.strip()]
    import time
    resp = os.path.join(ATTRACT, "respaldo_update_" + time.strftime("%Y%m%d_%H%M%S"))
    if modificados:
        os.makedirs(resp, exist_ok=True)
        for rel in modificados:
            origen = os.path.join(RAIZ_REPO, rel)
            if os.path.isfile(origen):
                dest = os.path.join(resp, rel.replace("/", "__"))
                try:
                    shutil.copy2(origen, dest)
                except OSError:
                    pass
    # 2) pull con autostash
    rc, out, err = ejecutar(["git", "-C", RAIZ_REPO, "pull", "--rebase",
                             "--autostash"], timeout=120)
    salida = (out + "\n" + err).strip()[-3000:]
    if rc != 0:
        ejecutar(["git", "-C", RAIZ_REPO, "rebase", "--abort"], timeout=20)
        return _err("el pull fallo (rebase abortado). Respaldo en %s.\n%s"
                    % (resp, salida))
    return _ok(respaldo=resp if modificados else None, salida=salida,
               nota="revisa arranque.dat y vuelve a correr instalar.sh tarea config "
                    "para los ficheros que son copias")


# ---------------------------------------------------------------------------
# Restaurar de fabrica (solo records y estadisticas; NUNCA la config de juegos
# ni la NVRAM, que guardan calibracion medida)
# ---------------------------------------------------------------------------

def restaurar_fabrica(records=True, stats=True):
    """Borra puntajes/records y/o estadisticas e ingresos.  Exige mantenimiento:
    con el frontend y MAME vivos, volverian a escribir esos ficheros enseguida."""
    g = _exige_mantenimiento()
    if g:
        return g
    borrados = []
    if records:
        if os.path.exists(F_PUNTAJES):
            os.remove(F_PUNTAJES)
            borrados.append("puntajes.json")
        for hi in glob.glob(os.path.join(DIR_MAME, "hiscore", "*.hi")):
            try:
                os.remove(hi)
            except OSError:
                pass
        borrados.append("*.hi")
    if stats:
        for st in glob.glob(os.path.join(DIR_STATS, "*.stat")):
            try:
                os.remove(st)
            except OSError:
                pass
        borrados.append("*.stat")
        if os.path.exists(F_MONEDAS):
            import time
            try:
                os.rename(F_MONEDAS, F_MONEDAS + time.strftime(".%Y%m%d_%H%M%S"))
            except OSError:
                pass
        borrados.append("monedas.log")
    auditar("restaurar_fabrica", "records=%s stats=%s" % (records, stats))
    # Reinicia el monedero (el resto de servicios no guardan estado que borrar).
    ejecutar(["systemctl", "--user", "restart", "monedero.service"], timeout=15)
    return _ok(borrados=borrados)


# ---------------------------------------------------------------------------
# Tiempo de vida de los logs (retencion + limpieza)
# ---------------------------------------------------------------------------

_UNIDADES = {"horas": 3600, "dias": 86400, "meses": 2592000}  # mes = 30 dias


def logs_retencion():
    aj = leer_ajustes().get("retencion_logs", {})
    return {"cada": int(aj.get("cada", 12)), "unidad": aj.get("unidad", "horas")}


def fijar_retencion(cada, unidad):
    try:
        cada = int(cada)
    except (TypeError, ValueError):
        return _err("'cada' no es un numero")
    if cada < 1 or unidad not in _UNIDADES:
        return _err("unidad debe ser horas/dias/meses y 'cada' >= 1")
    aj = leer_ajustes()
    aj["retencion_logs"] = {"cada": cada, "unidad": unidad}
    guardar_ajustes(aj)
    auditar("retencion_logs", "%d %s" % (cada, unidad))
    limpiar_logs()
    return _ok(cada=cada, unidad=unidad)


def limpiar_logs():
    """Borra los ficheros de log mas viejos que la retencion configurada.  Solo
    toca LOGS (no datos): los log del demonio, la auditoria del panel y los
    respaldos de monedas/update.  shortcut: se corre al pedir logs o al fijar la
    retencion, no por temporizador; basta para una cabina de un solo usuario."""
    import time
    r = logs_retencion()
    corte = time.time() - r["cada"] * _UNIDADES[r["unidad"]]
    patrones = [
        os.path.join(RAIZ_REPO, "arduino", "log*.txt"),
        os.path.join(ATTRACT, "monedas.log.*"),
        os.path.join(ATTRACT, "respaldo_update_*"),
    ]
    borrados = 0
    for pat in patrones:
        for ruta in glob.glob(pat):
            try:
                if os.path.getmtime(ruta) < corte:
                    if os.path.isdir(ruta):
                        shutil.rmtree(ruta, ignore_errors=True)
                    else:
                        os.remove(ruta)
                    borrados += 1
            except OSError:
                pass
    # La auditoria es un solo fichero que crece: si pasa el corte, se trunca.
    try:
        if os.path.exists(F_AUDITORIA) and os.path.getmtime(F_AUDITORIA) < corte:
            open(F_AUDITORIA, "w").close()
            borrados += 1
    except OSError:
        pass
    return borrados
