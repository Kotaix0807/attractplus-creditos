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

from comun import (ATTRACT, F_MANTENIMIENTO, F_PANEL_CMD, RAIZ_REPO,
                   auditar, ejecutar)

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


def _matar_frontend():
    for nombre in ("attractplus", "attractplus-x11", "attractplus-kms"):
        ejecutar(["pkill", "-x", nombre], timeout=5)


def frontend_reiniciar():
    """Mata el frontend; el wrapper de ~/.xinitrc lo relanza solo."""
    auditar("frontend_reiniciar")
    if _en_mantenimiento():
        return _err("hay modo mantenimiento activo: el frontend esta parado a proposito")
    _matar_frontend()
    return _ok()


def monedero_reiniciar():
    """Reinicia el demonio del monedero: reabre el puerto serie y resetea la
    placa (y con ella el rele)."""
    auditar("monedero_reiniciar")
    rc, _, err = ejecutar(["systemctl", "--user", "restart", "monedero.service"],
                         timeout=15)
    return _ok() if rc == 0 else _err(err or "fallo al reiniciar monedero.service")


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
    script = os.path.join(RAIZ_REPO, "creditos", "fijar_tarifa.sh")
    if not os.path.exists(script):
        return _err("no encuentro creditos/fijar_tarifa.sh")
    auditar("juego_tarifa", "%s=%d" % (rom, pesos))
    rc, out, err = ejecutar(["bash", script, rom, str(pesos)], timeout=60)
    return _ok(salida=out[-1500:]) if rc == 0 else _err((err or out)[-1500:])


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
