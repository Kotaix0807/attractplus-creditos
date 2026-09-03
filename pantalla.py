#!/usr/bin/env python3
"""Deja el CRT como unica pantalla, o restaura el escritorio de siempre.

Bajo GNOME Wayland xrandr no manda: la disposicion la decide mutter y se
cambia por D-Bus (org.gnome.Mutter.DisplayConfig).  Los cambios se aplican
en modo TEMPORAL, asi que un reinicio de sesion los deshace solos.

    ./pantalla.py cabina    -> solo el CRT
    ./pantalla.py escritorio -> todas las pantallas
    ./pantalla.py estado    -> que hay ahora
"""

import json
import os
import sys
import gi
gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib

RUTA = "/org/gnome/Mutter/DisplayConfig"
NOMBRE = "org.gnome.Mutter.DisplayConfig"
TEMPORAL = 1  # 0 verificar, 1 temporal, 2 permanente
PREVIA = os.path.expanduser("~/.attract/pantalla_previa.json")


def proxy():
    return Gio.DBusProxy.new_for_bus_sync(
        Gio.BusType.SESSION, Gio.DBusProxyFlags.NONE, None,
        NOMBRE, RUTA, NOMBRE, None)


def estado(p):
    serial, monitores, logicos, _props = p.call_sync(
        "GetCurrentState", None, Gio.DBusCallFlags.NONE, -1, None).unpack()
    return serial, monitores, logicos


def modo_actual(monitor):
    """Modo en uso de un monitor, o el preferido si ninguno lo esta."""
    preferido = None
    for m in monitor[1]:
        if m[6].get("is-current"):
            return m[0]
        if m[6].get("is-preferred"):
            preferido = m[0]
    return preferido or monitor[1][0][0]


def conector(monitor):
    return monitor[0][0]


def aplicar(p, serial, logicos):
    """Aplica una disposicion, y si mutter se niega por la tapa cerrada la
    reintenta sin el panel del portatil.

    Con el portatil cerrado, ApplyMonitorsConfig responde
    'Refusing to activate a closed laptop panel' y no cambia nada: sin este
    reintento, cabina.sh dejaria la pantalla como estuviera al salir.
    """
    try:
        _aplicar(p, serial, logicos)
        return logicos
    except GLib.GError as e:
        if "closed laptop panel" not in e.message:
            raise

    sin_panel = [l for l in logicos if not any(
        c.startswith("eDP") or c.startswith("LVDS") for c, *_ in l[5])]
    if not sin_panel:
        sys.exit("El portatil esta cerrado y no hay otra pantalla que encender.")

    print("(el portatil esta cerrado: lo dejo apagado)")
    # El primero pasa a ser el primario y arranca en el origen
    x, colocados = 0, []
    for i, (_x, _y, esc, t, _prim, asig, *_) in enumerate(sin_panel):
        colocados.append((x, 0, esc, t, i == 0, asig))
        x += 1  # el ancho real da igual con una sola pantalla
    _aplicar(p, serial, colocados)
    return colocados


def _aplicar(p, serial, logicos):
    p.call_sync(
        "ApplyMonitorsConfig",
        GLib.Variant("(uua(iiduba(ssa{sv}))a{sv})",
                     (serial, TEMPORAL, logicos, {})),
        Gio.DBusCallFlags.NONE, -1, None)


def externo(monitores):
    """El CRT: el primer monitor que no sea el panel del portatil."""
    for m in monitores:
        if not m[2].get("is-builtin"):
            return m
    return None


def guardar(monitores, logicos):
    """Apunta la disposicion actual para poder devolverla tal cual.

    GetCurrentState identifica cada monitor por (conector, marca, modelo,
    serie); ApplyMonitorsConfig los quiere por (conector, modo).  Aqui se
    traduce de una forma a la otra.
    """
    porconector = {conector(m): m for m in monitores}
    try:
        with open(PREVIA, "w") as f:
            json.dump([[x, y, esc, t, prim,
                        [[a[0], modo_actual(porconector[a[0]])] for a in asig]]
                       for x, y, esc, t, prim, asig, _ in logicos], f)
    except (OSError, KeyError) as e:
        print(f"aviso: no pude guardar la disposicion previa ({e})")


def recuperar():
    try:
        with open(PREVIA) as f:
            return [(x, y, esc, t, prim, [(c, m, {}) for c, m in asig])
                    for x, y, esc, t, prim, asig in json.load(f)]
    except (OSError, ValueError):
        return None


def cabina(p):
    serial, monitores, logicos = estado(p)
    if len(logicos) > 1:
        guardar(monitores, logicos)
    crt = externo(monitores)
    if crt is None:
        sys.exit("No hay ninguna pantalla externa conectada.")
    con, modo = conector(crt), modo_actual(crt)
    aplicar(p, serial, [(0, 0, 1.0, 0, True, [(con, modo, {})])])
    print(f"Solo {con} a {modo}")


def escritorio(p):
    serial, monitores, _logicos = estado(p)

    previa = recuperar()
    if previa and set(c for l in previa for c, _, _ in l[5]) == set(
            conector(m) for m in monitores):
        puestos = aplicar(p, serial, previa)
        print(" + ".join(l[5][0][0] for l in puestos))
        return

    logicos, x = [], 0
    # El panel del portatil primero y primario, el CRT a su derecha
    orden = sorted(monitores, key=lambda m: not m[2].get("is-builtin"))
    for m in orden:
        con, modo = conector(m), modo_actual(m)
        ancho, escalas = next((d[1], list(d[5])) for d in m[1] if d[0] == modo)
        # Sin disposicion guardada: la escala que deja el ancho logico mas
        # cerca de 1920 (un 4K va al 200%, el CRT se queda al 100%)
        escala = min(escalas, key=lambda e: abs(ancho / e - 1920))
        logicos.append((x, 0, escala, 0, not logicos, [(con, modo, {})]))
        x += int(ancho / escala)
    puestos = aplicar(p, serial, logicos)
    print(" + ".join(l[5][0][0] for l in puestos))


def imprimir(p):
    _serial, monitores, logicos = estado(p)
    for x, y, escala, _t, primaria, asignados, _p in logicos:
        for con, *_ in asignados:
            m = next(m for m in monitores if conector(m) == con)
            print(f"{con:8} {modo_actual(m):20} en {x},{y} escala {escala}"
                  f"{'  (primaria)' if primaria else ''}"
                  f"{'  [portatil]' if m[2].get('is-builtin') else '  [CRT]'}")


if __name__ == "__main__":
    orden = sys.argv[1] if len(sys.argv) > 1 else "estado"
    p = proxy()
    {"cabina": cabina, "escritorio": escritorio, "estado": imprimir}.get(
        orden, lambda _p: sys.exit(__doc__))(p)
