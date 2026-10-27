#!/usr/bin/env python3
"""Lectura en vivo de los mandos/teclado para 'Test botones' del panel.

Lee los eventos crudos de /dev/input/event* -- sin dependencias: la estructura
input_event del kernel se desempaqueta con struct -- y entrega cada pulsacion
segun ocurre.  El servidor las transmite por SSE a la GUI.

El usuario 'arcade' tiene que poder leer /dev/input (estar en el grupo 'input';
instalar.sh, tarea panel, lo hace).
"""

import glob
import os
import select
import struct

# struct input_event = { struct timeval time; __u16 type, code; __s32 value; }.
# En 64 bits timeval son dos 'long' (16 bytes); luego H H i.  Total 24 bytes.
_FMT = "llHHi"
_TAM = struct.calcsize(_FMT)
EV_KEY = 0x01


def _nombre(ev):
    """Nombre legible del dispositivo (de /sys), o el propio 'eventN'."""
    base = os.path.basename(ev)
    try:
        with open("/sys/class/input/%s/device/name" % base) as f:
            return f.read().strip() or base
    except OSError:
        return base


def _abrir_todos():
    fds = {}
    for ev in sorted(glob.glob("/dev/input/event*")):
        try:
            fds[os.open(ev, os.O_RDONLY | os.O_NONBLOCK)] = _nombre(ev)
        except OSError:
            pass            # sin permiso o se desconecto: se salta
    return fds


def eventos_botones():
    """Generador: cede un dict por cada tecla/boton pulsado o soltado:
        { 'dispositivo': str, 'codigo': int, 'pulsado': bool }
    Cede { 'latido': True } cada 30 s de silencio (mantiene viva la conexion), y
    { 'error': ... } y termina si no hay ningun dispositivo legible."""
    fds = _abrir_todos()
    if not fds:
        yield {"error": "no puedo leer /dev/input (falta permiso: grupo 'input')"}
        return
    try:
        while True:
            listos, _, _ = select.select(list(fds), [], [], 30)
            if not listos:
                yield {"latido": True}
                continue
            for fd in listos:
                try:
                    datos = os.read(fd, _TAM * 64)
                except OSError:
                    continue
                for i in range(0, len(datos) - _TAM + 1, _TAM):
                    _, _, tipo, codigo, valor = struct.unpack(_FMT, datos[i:i + _TAM])
                    if tipo == EV_KEY and valor in (0, 1):
                        yield {"dispositivo": fds[fd], "codigo": codigo,
                               "pulsado": valor == 1}
    finally:
        for fd in fds:
            try:
                os.close(fd)
            except OSError:
                pass


if __name__ == "__main__":
    # Self-check del desempaquetado (el parser es lo unico con logica).
    crudo = struct.pack(_FMT, 1, 2, EV_KEY, 304, 1)   # 304 = BTN_SOUTH (boton A)
    _, _, t, c, v = struct.unpack(_FMT, crudo)
    assert (t, c, v) == (EV_KEY, 304, 1), "desempaquetado mal"
    print("self-check OK (_TAM=%d). Escuchando mandos; Ctrl-C para salir." % _TAM)
    for ev in eventos_botones():
        print(ev)
