#!/usr/bin/env python3
"""Cuenta de monedas e ingresos, a partir del log que escribe creditos.lua.

El log ~/.attract/monedas.log es de solo-anadir (append).  Cada linea:

    <epoch>\t<rom>\t<evento>\t<cantidad>

Eventos:
  moneda     -> moneda de verdad metida por el jugador  (CUENTA como ingreso)
  panel      -> credito inyectado desde el panel (gratis) (NO cuenta como ingreso)
  consumido  -> el juego gasto un credito (informativo)   (NO cuenta como ingreso)

Los ingresos = (monedas de verdad) * valor_moneda  (por defecto $100 CLP).
"""

import os
import time

from comun import F_MONEDAS, entero

VALOR = entero("valor_moneda", 100)


def _lineas():
    try:
        with open(F_MONEDAS, encoding="utf-8", errors="replace") as f:
            for linea in f:
                campos = linea.split()
                if len(campos) >= 4:
                    try:
                        yield int(campos[0]), campos[1], campos[2], int(campos[3])
                    except ValueError:
                        continue
    except OSError:
        return


def _epoch_de_fecha(s, fin=False):
    """'YYYY-MM-DD' -> epoch del inicio (o del final) de ese dia local."""
    if not s:
        return None
    try:
        t = time.strptime(s, "%Y-%m-%d")
        base = time.mktime(t)
        return base + 86400 if fin else base
    except ValueError:
        return None


def _resumen(evento, desde, hasta):
    """Agrega un tipo de evento del log por juego, por dia y por hora, dentro de
    un rango de fechas opcional ('YYYY-MM-DD', inclusive)."""
    e_desde = _epoch_de_fecha(desde)
    e_hasta = _epoch_de_fecha(hasta, fin=True)
    por_juego = {}
    por_dia = {}
    por_hora = {}
    total = 0
    for epoch, rom, ev, cant in _lineas():
        if ev != evento:
            continue
        if e_desde is not None and epoch < e_desde:
            continue
        if e_hasta is not None and epoch >= e_hasta:
            continue
        total += cant
        por_juego[rom] = por_juego.get(rom, 0) + cant
        loc = time.localtime(epoch)
        por_dia[time.strftime("%Y-%m-%d", loc)] = \
            por_dia.get(time.strftime("%Y-%m-%d", loc), 0) + cant
        por_hora[time.strftime("%Y-%m-%d %H:00", loc)] = \
            por_hora.get(time.strftime("%Y-%m-%d %H:00", loc), 0) + cant
    return total, por_juego, por_dia, por_hora


def agregar(desde=None, hasta=None):
    """Resumen de monedas e ingresos (evento 'moneda'), opcionalmente filtrado
    por rango de fechas.  Ingresos = monedas * valor_moneda."""
    from estado import _titulo_rom
    total, por_juego, por_dia, por_hora = _resumen("moneda", desde, hasta)
    return {
        "valor_moneda": VALOR, "total_monedas": total, "ingresos": total * VALOR,
        "por_juego": [{"rom": r, "titulo": _titulo_rom(r), "monedas": m,
                       "ingresos": m * VALOR}
                      for r, m in sorted(por_juego.items(),
                                         key=lambda x: x[1], reverse=True)],
        "por_dia": [{"fecha": d, "monedas": m, "ingresos": m * VALOR}
                    for d, m in sorted(por_dia.items())],
        "por_hora": [{"hora": h, "monedas": m, "ingresos": m * VALOR}
                     for h, m in sorted(por_hora.items())],
    }


def tiradas(desde=None, hasta=None):
    """Partidas jugadas (evento 'consumido': creditos que el juego se llevo), por
    juego/dia/hora.  No es dinero: una partida pagada con comp del panel cuenta
    como tirada pero no como ingreso."""
    from estado import _titulo_rom
    total, por_juego, por_dia, por_hora = _resumen("consumido", desde, hasta)
    return {
        "total": total,
        "por_juego": [{"rom": r, "titulo": _titulo_rom(r), "tiradas": n}
                      for r, n in sorted(por_juego.items(),
                                         key=lambda x: x[1], reverse=True)],
        "por_dia": [{"fecha": d, "tiradas": n} for d, n in sorted(por_dia.items())],
        "por_hora": [{"hora": h, "tiradas": n} for h, n in sorted(por_hora.items())],
    }


def poner_a_cero():
    """Vacia el log de monedas (guardando una copia con fecha, por si acaso)."""
    if os.path.exists(F_MONEDAS):
        respaldo = F_MONEDAS + time.strftime(".%Y%m%d_%H%M%S")
        try:
            os.rename(F_MONEDAS, respaldo)
        except OSError:
            pass


if __name__ == "__main__":
    import json
    print(json.dumps(agregar(), indent=2, ensure_ascii=False))
