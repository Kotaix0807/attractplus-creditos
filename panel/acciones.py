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
import queue
import struct
import subprocess
import threading
import time

from comun import (ATTRACT, F_ARDUINO_RESET, F_BRILLO, F_FRONTEND_DETENIDO,
                   F_MANTENIMIENTO, F_MONEDAS, F_MONEDERO_RESET, F_PANEL_CMD,
                   F_TARIFA_GLOBAL, auditar, ejecutar, escribir_atomico)

DIR_MAME = os.path.expanduser("~/.mame")


def _ok(**extra):
    d = {"ok": True}
    d.update(extra)
    return d


def _err(msg):
    return {"ok": False, "error": msg}


def _en_mantenimiento():
    return os.path.exists(F_MANTENIMIENTO)


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
    if _hypseus_corriendo():
        return _creditos_hypseus(n)
    if not _enviar_mame("insertar %d" % n):
        return _err("no se pudo escribir la orden")
    return _ok(nota="se inyectaran si hay un juego en marcha")


def juego_salir():
    auditar("juego_salir")
    if _hypseus_corriendo():
        if _tecla_x(_XK_HYPSEUS["salir"]):
            return _ok()
        return _err("no se pudo enviar la tecla a la pantalla")
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


# Hypseus (laserdisc: Dragon's Lair) no corre creditos.lua, asi que NO lee
# panel_cmd: una orden dejada ahi se quedaria esperando y la cumpliria el
# siguiente juego de MAME (un 'salir' viejo lo cerraria nada mas abrir). Ahi el
# panel hace de teclado (XTEST), con las teclas de config/cabina/hypinput.ini.
_XK_HYPSEUS = {"salir": 0xff1b, "start1": 0x31, "start2": 0x32,
               "p1_up": 0xff52, "p1_down": 0xff54, "p1_left": 0xff51, "p1_right": 0xff53,
               "p1_b1": 0xffe3}   # espada = Ctrl izquierdo (KEY_BUTTON1)
_XK_MONEDA = 0x35                 # tecla 5 = KEY_COIN1


def _hypseus_corriendo():
    rc, _, _ = ejecutar(["pgrep", "-x", "hypseus"], timeout=5)
    return rc == 0


def _creditos_hypseus(n):
    """Mete n monedas en Hypseus pulsando su tecla de moneda. Cuentan para el
    juego igual que una moneda de verdad, pero se apuntan como regalo del panel
    (evento 'panel' en monedas.log, como hace creditos.lua), no como ingreso."""
    for i in range(n):
        if i:
            time.sleep(0.15)      # hueco entre monedas: la ROM cuenta flancos
        if not _tecla_x(_XK_MONEDA):
            return _err("no se pudo enviar la tecla a la pantalla")
    try:
        with open(os.path.join(ATTRACT, "juego_actual"), encoding="utf-8") as f:
            rom = f.read().split("\t", 1)[0].strip() or "?"
    except OSError:
        rom = "?"
    try:
        with open(F_MONEDAS, "a", encoding="utf-8") as f:
            f.write("%d\t%s\tpanel\t%d\n" % (int(time.time()), rom, n))
    except OSError:
        pass
    return _ok(nota="en Dragon's Lair (Hypseus)")


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
    if _hypseus_corriendo():
        ks = _XK_HYPSEUS.get(control)
        if ks is None:
            return _ok(nota="Dragon's Lair no usa ese control")
        if _tecla_x(ks):
            return _ok(nota="en el juego")
        return _err("no se pudo enviar la tecla a la pantalla")
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


def monedero_reiniciar():
    """Reinicia el monedero: corta y restaura su alimentacion con el solenoide
    ACTIVADO para que CALIBRE al encender (si se enciende con el solenoide apagado
    no calibra bien). Lo hace moneyBank.py (unico dueno del puerto) al ver el
    fichero centinela, asi el panel no se bloquea."""
    auditar("monedero_reiniciar")
    try:
        open(F_MONEDERO_RESET, "w").close()
    except OSError as e:
        return _err("no pude pedir el reinicio del monedero (demonio parado?): %s" % e)
    return _ok()


def arduino_reiniciar():
    """Reinicia la placa Arduino entera: moneyBank.py cierra y reabre el puerto
    (reset por DTR) y re-sincroniza todo el estado. Util si la placa se cuelga."""
    auditar("arduino_reiniciar")
    try:
        open(F_ARDUINO_RESET, "w").close()
    except OSError as e:
        return _err("no pude pedir el reinicio del Arduino (demonio parado?): %s" % e)
    return _ok()


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
# Tarifa global y brillo de los LEDs (ficheros que leen creditos.lua y moneyBank.py)
# ---------------------------------------------------------------------------


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


# ---------------------------------------------------------------------------
# Pantalla remota (solo ver): el CRT :0 en H.264 por ffmpeg
# ---------------------------------------------------------------------------

def _xauth():
    """El X de GroovyArcade arranca con '-auth /tmp/serverauth.XXX'; ese fichero es
    mas fiable que ~/.Xauthority para abrir :0 (verificado capturando la cabina)."""
    cands = sorted(glob.glob("/tmp/serverauth.*"), key=os.path.getmtime, reverse=True)
    return cands[0] if cands else os.path.expanduser("~/.Xauthority")


def stream_pantalla_h264(fps=30, ancho=640, kbps=1500):
    """Generador de MP4 fragmentado (H.264) de la pantalla :0, para reproducir en
    el navegador con MSE (<video>). H.264 comprime ENTRE cuadros, asi que gasta
    ~10-30x menos que el MJPEG -> fluido en 4G con calidad mucho mejor. Baseline +
    yuv420p = maxima compatibilidad con MediaSource; ultrafast/zerolatency para que
    el i3 encode en vivo y con poco retardo. Al cerrar el cliente, Flask cierra el
    generador y el 'finally' mata ffmpeg."""
    env = dict(os.environ, DISPLAY=":0", XAUTHORITY=_xauth())
    br = "%dk" % int(kbps)
    g = str(int(fps))                       # keyframe cada ~1 s: arranque y fragmentos
    cmd = ["ffmpeg", "-loglevel", "error",
           "-fflags", "nobuffer", "-flags", "low_delay",
           "-f", "x11grab", "-framerate", str(int(fps)), "-i", ":0",
           "-vf", "scale=%d:-2" % int(ancho),
           "-c:v", "libx264", "-preset", "ultrafast", "-tune", "zerolatency",
           "-profile:v", "baseline", "-level", "3.1", "-pix_fmt", "yuv420p",
           "-g", g, "-keyint_min", g,
           "-b:v", br, "-maxrate", br, "-bufsize", "%dk" % (int(kbps) * 2),
           # Fragmentos de 50 ms (~3 cuadros): cada trozo sale casi al capturarse.
           # Con 250 ms cada imagen esperaba hasta un cuarto de segundo en la cabina.
           "-movflags", "+empty_moov+default_base_moof+frag_keyframe",
           "-frag_duration", "50000", "-flush_packets", "1",
           "-f", "mp4", "pipe:1"]
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE,
                            stderr=subprocess.DEVNULL, env=env, bufsize=0)
    try:
        while True:
            trozo = proc.stdout.read(16384)
            if not trozo:
                break
            yield trozo
    finally:
        try:
            proc.kill()
        except Exception:
            pass


def stream_pantalla_crudo(fps=60, ancho=480, kbps=800):
    """H.264 CRUDO (Annex-B) de la pantalla :0, para decodificarlo en el navegador
    con WebCodecs y pintarlo al llegar (sin el colchon de <video>): el camino de
    menor retardo. Un AUD por fotograma (aud=1) para que el cliente sepa donde
    acaba cada uno. VBV corto (bufsize = 1/4 s): el cuadro clave no puede ser un
    pico enorme que tarde cientos de ms en cruzar el 4G; sale algo mas borroso un
    instante. Clave cada 2 s: solo hace falta para arrancar y para recuperarse si
    el movil tira cuadros."""
    env = dict(os.environ, DISPLAY=":0", XAUTHORITY=_xauth())
    br = "%dk" % int(kbps)
    g = str(int(fps) * 2)
    cmd = ["ffmpeg", "-loglevel", "error",
           "-fflags", "nobuffer", "-flags", "low_delay",
           "-f", "x11grab", "-framerate", str(int(fps)), "-i", ":0",
           "-vf", "scale=%d:-2" % int(ancho),
           "-c:v", "libx264", "-preset", "ultrafast", "-tune", "zerolatency",
           "-profile:v", "baseline", "-level", "3.1", "-pix_fmt", "yuv420p",
           "-x264-params", "aud=1",
           "-g", g, "-keyint_min", g,
           "-b:v", br, "-maxrate", br, "-bufsize", "%dk" % max(1, int(kbps) // 4),
           "-flush_packets", "1", "-f", "h264", "pipe:1"]
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE,
                            stderr=subprocess.DEVNULL, env=env, bufsize=0)
    try:
        yield from enmarcar_h264(lambda: proc.stdout.read(16384))
    finally:
        try:
            proc.kill()
        except Exception:
            pass


def enmarcar_h264(leer, max_cola=6):
    """Parte el H.264 Annex-B en fotogramas (cada uno empieza con su AUD) y los
    manda como [1 B clave][8 B hora ms, float BE][4 B largo][datos].

    Un hilo lee del encoder SIN PARAR y apunta la hora de cada fotograma al salir
    de el. Si la conexion no da abasto y se juntan mas de 'max_cola' esperando, se
    tiran hasta el siguiente cuadro clave (desde ahi se puede decodificar): asi la
    cola nunca se queda atras ("salto de fotogramas" en origen). Lo que la red
    retrase despues lo mide el navegador con la hora y reconecta si hace falta."""
    cola = queue.Queue()

    def lector():
        aud = b"\x00\x00\x00\x01\x09"
        pend = b""
        try:
            while True:
                trozo = leer()
                if not trozo:
                    return
                pend += trozo
                partes = pend.split(aud)
                pend = aud + partes[-1] if len(partes) > 1 else pend
                for au in partes[:-1]:
                    if au:                # lo de antes del primer AUD se ignora
                        au = aud + au
                        cola.put((_es_clave(au), time.time() * 1000, au))
        finally:
            cola.put(None)

    threading.Thread(target=lector, daemon=True).start()
    tirando = False
    while True:
        item = cola.get()
        if item is None:
            return
        clave, hora, au = item
        if cola.qsize() > max_cola:
            tirando = True
        if tirando and not clave:
            continue
        tirando = False
        yield struct.pack(">Bdi", clave, hora, len(au)) + au


def _es_clave(au):
    """True si el fotograma trae un NAL IDR (tipo 5)."""
    i = au.find(b"\x00\x00\x01")
    while i >= 0 and i + 3 < len(au):
        if au[i + 3] & 0x1f == 5:
            return True
        i = au.find(b"\x00\x00\x01", i + 3)
    return False


