#!/usr/bin/env python3
"""Lectura de estado de la cabina para el panel (todo de solo lectura).

Cada funcion es defensiva: si algo no se puede leer, devuelve un valor neutro
('desconocido', None, 0) en vez de reventar.  El panel tiene que seguir
respondiendo aunque falte un sensor o un servicio.

Fuentes: /proc, /sys, systemctl, pgrep, git, y los ficheros de ~/.attract que
escriben creditos.lua y moneyBank.py (ver docs/panel.md).
"""

import glob
import json
import os
import shutil
import time

from comun import (ATTRACT, DIR_STATS, F_CREDITOS_JUEGO, F_JUEGO_ACTUAL,
                   F_MANTENIMIENTO, F_MONEDERO_SWITCH, F_PUNTAJES, RAIZ_REPO,
                   ejecutar)

HZ = os.sysconf("SC_CLK_TCK") if hasattr(os, "sysconf") else 100


def _leer(ruta):
    try:
        with open(ruta, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return ""


# ---------------------------------------------------------------------------
# CPU: se calcula por diferencia entre dos lecturas de /proc/stat.  Se guarda la
# ultima para no tener que dormir dentro de la peticion.
# ---------------------------------------------------------------------------

_cpu_previo = {"idle": 0, "total": 0}


def cpu():
    nucleos = os.cpu_count() or 1
    try:
        carga = list(os.getloadavg())
    except (OSError, AttributeError):
        carga = [0.0, 0.0, 0.0]
    uso = 0
    try:
        campos = _leer("/proc/stat").splitlines()[0].split()[1:]
        nums = [int(x) for x in campos]
        idle = nums[3] + (nums[4] if len(nums) > 4 else 0)
        total = sum(nums)
        d_total = total - _cpu_previo["total"]
        d_idle = idle - _cpu_previo["idle"]
        if _cpu_previo["total"] and d_total > 0:
            uso = round(100 * (d_total - d_idle) / d_total)
        _cpu_previo["idle"], _cpu_previo["total"] = idle, total
    except (ValueError, IndexError):
        pass
    return {"uso_pct": max(0, min(100, uso)), "nucleos": nucleos,
            "carga": [round(c, 2) for c in carga]}


def temperatura():
    """El maximo de las temperaturas plausibles que publica el kernel."""
    temps = []
    for ruta in (glob.glob("/sys/class/thermal/thermal_zone*/temp")
                 + glob.glob("/sys/class/hwmon/hwmon*/temp*_input")):
        try:
            v = int(_leer(ruta).strip()) / 1000.0
            if 20 <= v <= 120:
                temps.append(v)
        except (ValueError, TypeError):
            pass
    return round(max(temps)) if temps else None


def ram():
    datos = {}
    for linea in _leer("/proc/meminfo").splitlines():
        if ":" in linea:
            k, v = linea.split(":", 1)
            datos[k.strip()] = v.strip()
    try:
        total_kb = int(datos.get("MemTotal", "0").split()[0])
        disp_kb = int(datos.get("MemAvailable", "0").split()[0])
        usada_mb = (total_kb - disp_kb) // 1024
        total_mb = total_kb // 1024
        pct = round(100 * (total_kb - disp_kb) / total_kb) if total_kb else 0
        return {"usada_mb": usada_mb, "total_mb": total_mb, "pct": pct}
    except (ValueError, IndexError, ZeroDivisionError):
        return {"usada_mb": 0, "total_mb": 0, "pct": 0}


def disco():
    destino = "/home" if os.path.isdir("/home") else "/"
    try:
        s = os.statvfs(destino)
        total = s.f_blocks * s.f_frsize
        libre = s.f_bavail * s.f_frsize
        usado = total - libre
        gb = 1024 ** 3
        return {"usado_gb": round(usado / gb), "total_gb": round(total / gb),
                "libre_gb": round(libre / gb),
                "pct": round(100 * usado / total) if total else 0}
    except OSError:
        return {"usado_gb": 0, "total_gb": 0, "libre_gb": 0, "pct": 0}


def uptime():
    try:
        return int(float(_leer("/proc/uptime").split()[0]))
    except (ValueError, IndexError):
        return 0


# ---------------------------------------------------------------------------
# Juego en marcha
# ---------------------------------------------------------------------------

def _pid_de(nombre):
    """PID del primer proceso cuyo 'comm' sea exactamente 'nombre', o None."""
    for d in glob.glob("/proc/[0-9]*"):
        try:
            if _leer(os.path.join(d, "comm")).strip() == nombre:
                return int(os.path.basename(d))
        except (OSError, ValueError):
            pass
    return None


def _segundos_proceso(pid):
    """Segundos que lleva vivo un proceso, de su starttime en /proc/pid/stat."""
    try:
        campos = _leer("/proc/%d/stat" % pid).rsplit(")", 1)[1].split()
        starttime = int(campos[19])  # campo 22 (1-based), tras "comm) "
        btime = 0
        for linea in _leer("/proc/stat").splitlines():
            if linea.startswith("btime"):
                btime = int(linea.split()[1])
                break
        arranque = btime + starttime / HZ
        return max(0, int(time.time() - arranque))
    except (ValueError, IndexError):
        return 0


def proceso_vivo(*nombres):
    for n in nombres:
        if _pid_de(n) is not None:
            return True
    return False


def juego_actual():
    pid = _pid_de("mame")
    if pid is None:
        return None
    # El rom y el titulo los deja creditos.lua en juego_actual (rom<TAB>titulo).
    rom, titulo = None, None
    txt = _leer(F_JUEGO_ACTUAL).strip()
    if txt:
        partes = txt.split("\t")
        rom = partes[0].strip() or None
        titulo = partes[1].strip() if len(partes) > 1 else None
    if not rom:
        # Respaldo: sacar el set del cmdline de mame (primer arg sin '-').
        args = _leer("/proc/%d/cmdline" % pid).split("\0")
        for a in args[1:]:
            if a and not a.startswith("-"):
                rom = a
                break
    creditos = None
    try:
        v = _leer(F_CREDITOS_JUEGO).strip()
        if v:
            creditos = int(v)
    except ValueError:
        pass
    return {"rom": rom, "titulo": titulo or rom, "corriendo": True,
            "segundos": _segundos_proceso(pid), "creditos_dentro": creditos}


# ---------------------------------------------------------------------------
# Servicios, red, Arduino, versiones
# ---------------------------------------------------------------------------

def _is_active(unidad, usuario=False):
    cmd = ["systemctl"] + (["--user"] if usuario else []) + ["is-active", unidad]
    rc, out, _ = ejecutar(cmd, timeout=5)
    estado = out.strip()
    if estado == "active":
        return "activo"
    if estado in ("inactive", "failed", "deactivating", "activating"):
        return "inactivo"
    return "desconocido"


def servicios():
    return {
        "panel": _is_active("panel.service", usuario=True),
        "monedero": _is_active("monedero.service", usuario=True),
        "pantalla-auto": _is_active("pantalla-auto.service"),
        "cloudflared": _is_active("cloudflared.service"),
        "frontend": "activo" if proceso_vivo(
            "attractplus", "attractplus-x11", "attractplus-kms") else "inactivo",
        "x": "activo" if proceso_vivo("Xorg", "X") else "inactivo",
    }


def _puerto_arduino():
    for patron in ("/dev/serial/by-id/*1a86*", "/dev/ttyUSB*"):
        hallados = sorted(glob.glob(patron))
        if hallados:
            return hallados[0]
    return None


def arduino():
    puerto = _puerto_arduino()
    hay_mame = _pid_de("mame") is not None
    switch = _leer(F_MONEDERO_SWITCH).strip()
    if not hay_mame:
        rele = "off"
    elif switch == "1":
        rele = "on"
    else:
        rele = "off"
    # Ultimo error del demonio: ultima linea con 'Errno'/'error' del log reciente.
    ultimo_error = None
    logs = sorted(glob.glob(os.path.join(RAIZ_REPO, "arduino", "log*.txt")))
    if logs:
        for linea in reversed(_leer(logs[-1]).splitlines()):
            if "Errno" in linea or "error" in linea.lower():
                ultimo_error = linea.strip()
                break
    return {"conectado": puerto is not None, "puerto": puerto,
            "rele": rele if puerto else "desconocido", "ultimo_error": ultimo_error}


def red():
    # IP publica: se intenta leer sin salir a internet (no bloquear la peticion).
    # Si hay cloudflared, el tunel es "activo"/"caido" segun el servicio.
    tunel = "activo" if _is_active("cloudflared.service") == "activo" else "caido"
    ip = None
    rc, out, _ = ejecutar(["ip", "-4", "route", "get", "1.1.1.1"], timeout=3)
    if rc == 0:
        for parte in out.split():
            if parte.count(".") == 3:
                ip = parte
    return {"ip_publica": ip, "tunel": tunel}


_versiones_cache = None


def versiones():
    global _versiones_cache
    if _versiones_cache is not None:
        return _versiones_cache
    mame_v, am_v = "?", "?"
    mame_bin = shutil.which("mame") or shutil.which("groovymame")
    if mame_bin:
        rc, out, _ = ejecutar([mame_bin, "-version"], timeout=8)
        if rc == 0 and out.strip():
            mame_v = out.strip().split("\n")[0].split()[0]
    am_bin = (shutil.which("attractplus") or shutil.which("attractplus-x11")
              or os.path.join(RAIZ_REPO, "attractplus"))
    if am_bin and os.path.exists(am_bin):
        rc, out, _ = ejecutar([am_bin, "--version"], timeout=8)
        if rc == 0 and out.strip():
            import re
            # "Attract-Mode Plus v3.2.3 (Linux, ...)" -> "3.2.3"
            m = re.search(r"v?(\d+\.\d+\.\d+)", out)
            am_v = m.group(1) if m else out.strip().split("\n")[0]
    _versiones_cache = {"mame": mame_v, "attractplus": am_v}
    return _versiones_cache


_sistema_cache = None


def sistema():
    """Hardware + software para la tarjeta 'Informacion del sistema'.  Se cachea:
    nada de esto cambia mientras la cabina esta encendida."""
    global _sistema_cache
    if _sistema_cache is not None:
        return _sistema_cache
    equipo = (_leer("/sys/class/dmi/id/product_name").strip()
              or _leer("/sys/class/dmi/id/board_name").strip() or "?")
    cpu_modelo = "?"
    for l in _leer("/proc/cpuinfo").splitlines():
        if l.lower().startswith("model name"):
            cpu_modelo = l.split(":", 1)[1].strip()
            break
    so = "?"
    for l in _leer("/etc/os-release").splitlines():
        if l.startswith("PRETTY_NAME="):
            so = l.split("=", 1)[1].strip().strip('"')
            break
    v = versiones()
    _sistema_cache = {
        "equipo": equipo, "cpu_modelo": cpu_modelo,
        "ram_total_mb": ram()["total_mb"], "disco_total_gb": disco()["total_gb"],
        "so": so, "mame": v["mame"], "attractplus": v["attractplus"],
    }
    return _sistema_cache


def juegos_total():
    ruta = os.path.join(ATTRACT, "romlists", "groovymame.txt")
    n = 0
    for linea in _leer(ruta).splitlines():
        if linea and not linea.startswith("#"):
            n += 1
    return n


def commit():
    rc, out, _ = ejecutar(["git", "-C", RAIZ_REPO, "log", "-1",
                           "--format=%h\t%cd\t%s", "--date=short"], timeout=5)
    if rc == 0 and out.strip():
        partes = out.strip().split("\t")
        return {"hash": partes[0],
                "fecha": partes[1] if len(partes) > 1 else "",
                "mensaje": partes[2] if len(partes) > 2 else ""}
    return {"hash": "?", "fecha": "", "mensaje": ""}


def mantenimiento():
    return os.path.exists(F_MANTENIMIENTO)


# ---------------------------------------------------------------------------
# El estado completo (lo que pide GET /api/estado)
# ---------------------------------------------------------------------------

def completo():
    from comun import entero
    return {
        "hora": int(time.time()),
        "uptime_seg": uptime(),
        "mantenimiento": mantenimiento(),
        "cpu": cpu(),
        "temperatura_c": temperatura(),
        "temperatura_max_c": entero("temp_aviso", 80),
        "ram": ram(),
        "disco": disco(),
        "juego_actual": juego_actual(),
        "red": red(),
        "servicios": servicios(),
        "arduino": arduino(),
        "versiones": versiones(),
        "juegos_total": juegos_total(),
        "commit": commit(),
    }


# ---------------------------------------------------------------------------
# Puntajes y mas-jugados (leen ficheros, no tocan el sistema)
# ---------------------------------------------------------------------------

def puntajes():
    """El puntajes.json, quitando las filas de fabrica (defecto==true)."""
    try:
        with open(F_PUNTAJES, encoding="utf-8") as f:
            crudo = json.load(f)
    except (OSError, ValueError):
        return {"generado": 0, "juegos": {}}
    juegos = {}
    for rom, info in crudo.items():
        if not isinstance(info, dict) or not info.get("descifrado"):
            continue
        puestos = []
        for p in info.get("puestos", []):
            if p.get("defecto") is True:
                continue
            puestos.append({"puesto": p.get("puesto"), "puntos": p.get("puntos"),
                            "nombre": p.get("nombre"),
                            "confirmado": bool(p.get("confirmado"))})
        if puestos:
            juegos[rom] = {"titulo": info.get("titulo", rom), "puestos": puestos}
    gen = int(os.path.getmtime(F_PUNTAJES)) if os.path.exists(F_PUNTAJES) else 0
    return {"generado": gen, "juegos": juegos}


def _titulo_rom(rom):
    """Titulo legible del set, del romlist si esta; si no, el propio rom."""
    cache = _titulo_rom
    if not hasattr(cache, "mapa"):
        cache.mapa = {}
        ruta = os.path.join(ATTRACT, "romlists", "groovymame.txt")
        for linea in _leer(ruta).splitlines():
            if linea and not linea.startswith("#"):
                campos = linea.split(";")
                if len(campos) >= 2:
                    cache.mapa[campos[0]] = campos[1] or campos[0]
    return cache.mapa.get(rom, rom)


def masjugados(orden="partidas", limite=20):
    """Lee ~/.attract/stats/groovymame/*.stat (formato nativo de AM+):
    linea 1 PlayedCount, 2 PlayedTime, 3 PlayedLast."""
    filas = []
    for ruta in glob.glob(os.path.join(DIR_STATS, "*.stat")):
        rom = os.path.splitext(os.path.basename(ruta))[0]
        lineas = _leer(ruta).splitlines()
        try:
            partidas = int(lineas[0]) if len(lineas) > 0 else 0
            tiempo = int(lineas[1]) if len(lineas) > 1 else 0
            ultima = int(lineas[2]) if len(lineas) > 2 else 0
        except ValueError:
            continue
        if partidas <= 0:
            continue
        filas.append({"rom": rom, "titulo": _titulo_rom(rom),
                      "partidas": partidas, "tiempo_seg": tiempo, "ultima": ultima})
    clave = "tiempo_seg" if orden == "tiempo" else "partidas"
    filas.sort(key=lambda f: f[clave], reverse=True)
    return filas[:limite]


if __name__ == "__main__":
    # Util para probar a mano:  python3 panel/estado.py
    print(json.dumps(completo(), indent=2, ensure_ascii=False))
