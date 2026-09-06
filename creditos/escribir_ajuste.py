#!/usr/bin/env python3
"""Pone o cambia una clave de un juego en arranque.dat, sin tocar nada mas.

Se hace con un programa y no con sed porque el fichero lleva mucho comentario
util y una linea 'defecto' que no hay que confundir con un juego. Escribe a un
temporal y renombra, que en POSIX es atomico: si esto se corta a medias, el
fichero no queda a la mitad.
"""

import io
import os
import sys


def escribir(ruta, juego, clave, valor):
    lineas = io.open(ruta, encoding="utf-8").read().splitlines(True) \
        if os.path.exists(ruta) else []
    par = "%s=%s" % (clave, valor)
    salida, hecho = [], False
    for linea in lineas:
        pelada = linea.strip()
        # Los comentarios y los huecos se copian tal cual.
        if not pelada or pelada.startswith("#"):
            salida.append(linea)
            continue
        campos = pelada.split()
        if campos[0].lower() != juego.lower():
            salida.append(linea)
            continue
        # Es la linea del juego: se cambia la clave si estaba, o se anade.
        nuevos, visto = [], False
        for c in campos[1:]:
            if c.split("=")[0] == clave:
                nuevos.append(par)
                visto = True
            else:
                nuevos.append(c)
        if not visto:
            nuevos.append(par)
        salida.append("%s %s\n" % (campos[0], " ".join(nuevos)))
        hecho = True
    if not hecho:
        if salida and not salida[-1].endswith("\n"):
            salida[-1] += "\n"
        salida.append("%s %s\n" % (juego, par))

    tmp = ruta + ".tmp.%d" % os.getpid()
    with io.open(tmp, "w", encoding="utf-8") as fh:
        fh.write("".join(salida))
    os.replace(tmp, ruta)


if __name__ == "__main__":
    if len(sys.argv) != 5:
        sys.exit("uso: escribir_ajuste.py <arranque.dat> <juego> <clave> <valor>")
    escribir(*sys.argv[1:])
