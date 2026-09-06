#!/usr/bin/env python3
"""Busca una tabla de puntuaciones en un volcado, por las INICIALES.

Es el metodo que funciono a ojo con Double Dragon y que aqui se automatiza.
Buscar "numeros que bajan" en un binario de kilobytes da falsos positivos por
todas partes; buscar GRUPOS DE LETRAS A INTERVALOS REGULARES no, porque una
tabla de records es de las poquisimas cosas que tienen esa forma.

Una vez localizada la rejilla de nombres, la puntuacion se busca solo en los
bytes de esa misma entrada, que son un punado: ahi si se puede probar todo.
"""
import sys, os, json

def swap(d, paso=2):
    b = bytearray(d)
    for i in range(0, len(b) - paso + 1, paso):
        b[i:i+paso] = b[i:i+paso][::-1]
    return bytes(b)

LETRAS = set(range(0x41, 0x5B)) | {0x20, 0x2E, 0x2D} | set(range(0x30, 0x3A))

# Muchas placas NO guardan las iniciales en ASCII sino como INDICE de letra.
# Los desplazamientos que aparecen una y otra vez: 0x0a = 'A' (Capcom),
# 0x00 = 'A' (SNK) y 0x11 = 'A' (Donkey Kong). Sin probarlos, en esos juegos no
# hay ningun texto que encontrar y el buscador no ve absolutamente nada.
INDICES = {"capcom": 0x0a, "snk": 0x00, "dkong": 0x11}

def iniciales(d, i, n=3, modo="ascii"):
    """¿Hay n caracteres con pinta de iniciales en i?"""
    t = d[i:i+n]
    if len(t) < n or all(c == 0x20 for c in t) or all(c == 0 for c in t):
        return None
    if modo == "ascii":
        if not all(c in LETRAS for c in t):
            return None
        return t.decode("ascii")
    base = INDICES[modo]
    if not all(base <= c < base + 26 for c in t):
        return None
    return "".join(chr(ord("A") + c - base) for c in t)

def rejillas(d, minimo=4, modo="ascii"):
    """Posiciones + paso donde se repiten iniciales regularmente."""
    fuera = []
    marcas = [i for i in range(len(d) - 3) if iniciales(d, i, modo=modo)]
    juego = set(marcas)
    def texto_corrido(ini, paso, n):
        """¿Es una cadena de texto en vez de una tabla?

        El nombre del juego (' DOUBLE DRAGON ') tambien parece una rejilla si
        se mira de tres en tres. Lo que distingue a una tabla es que entre una
        inicial y la siguiente hay HUECO -- ceros, la puntuacion, lo que sea --
        y no mas letras.
        """
        huecos = 0
        for k in range(n):
            entre = d[ini + k * paso + 3: ini + (k + 1) * paso]
            if entre and not all(c in LETRAS for c in entre):
                huecos += 1
        return huecos < n - 1

    for ini in marcas:
        # paso 6 minimo: con 3 letras y menos de 3 de hueco es texto seguido.
        for paso in range(6, 65):
            n = 0
            while ini + n * paso in juego:
                n += 1
            if n >= minimo and not texto_corrido(ini, paso, n):
                fuera.append((n, paso, ini))
    fuera.sort(reverse=True)
    # quitar solapes: quedarse con la rejilla mas larga de cada zona
    limpio, usados = [], []
    for n, paso, ini in fuera:
        if any(abs(ini - u) < 64 and p == paso for u, p in usados):
            continue
        usados.append((ini, paso))
        limpio.append((n, paso, ini))
    return limpio[:6]

FORMATOS = (("bcd", 2, 4), ("bcdle", 2, 4), ("digitos", 4, 8),
            ("be", 2, 4), ("le", 2, 4))

def valor(t, fmt):
    try:
        if fmt == "bcd":   return int(t.hex())
        if fmt == "bcdle": return int(t[::-1].hex())
        if fmt == "digitos":
            if any(b > 9 for b in t): return None
            return int("".join(str(b) for b in t))
        if fmt == "be":    return int.from_bytes(t, "big")
        if fmt == "le":    return int.from_bytes(t, "little")
    except ValueError:
        return None

def puntuacion(d, ini, paso, n, ancho=24):
    """Con la rejilla de nombres localizada, busca el campo numerico."""
    mejor = None
    base = max(0, ini - ancho)
    for off in range(base, ini + 4):
        rel = off - ini
        for fmt, lo, hi in FORMATOS:
            for largo in range(lo, hi + 1):
                vals = []
                for k in range(n):
                    p = ini + k * paso + rel
                    if p < 0 or p + largo > len(d): break
                    v = valor(d[p:p+largo], fmt)
                    if v is None: break
                    vals.append(v)
                if len(vals) < n: continue
                if len({v for v in vals if v}) < 3: continue
                if max(vals) < 100 or max(vals) > 10_000_000: continue
                baja = all(vals[i] >= vals[i+1] for i in range(len(vals)-1))
                if not baja: continue
                nota = len(set(vals)) * 3 + (12 if all(v % 10 == 0 for v in vals) else 0) + largo
                if not mejor or nota > mejor[0]:
                    mejor = (nota, rel, largo, fmt, vals)
    return mejor

def analiza(nombre, datos):
    for etiqueta, d, modo in [(f"{e}/{m}", dd, m)
                              for e, dd in (("normal", datos), ("swap", swap(datos)))
                              for m in ("ascii", "capcom", "snk", "dkong")]:
        cands = []
        for n, paso, ini in rejillas(d, modo=modo):
            m = puntuacion(d, ini, paso, n)
            if m:
                cands.append((m[0], n, paso, ini, m))
        cands.sort(reverse=True)
        for _, n, paso, ini, m in cands[:1]:
            nota, rel, largo, fmt, vals = m
            noms = [iniciales(d, ini + k * paso, modo=modo) for k in range(n)]
            desde = ini + rel
            print(f"  {nombre:<10} [{etiqueta}] {n} entradas de {paso}B desde {desde:#x}")
            print(f"     puntos={-rel if rel<0 else 0},{largo},{fmt}  {vals[:6]}")
            print(f"     nombres en +{ini-desde}  {noms[:6]}")
            return True
    return False

if __name__ == "__main__":
    import glob
    aqui = os.path.expanduser("~/attractplus-creditos/creditos/puntajes_fabrica.json")
    fab = json.load(open(aqui)) if os.path.exists(aqui) else {}
    for j in sys.argv[1:]:
        vistos = False
        fuentes = []
        if j in fab: fuentes.append(bytes.fromhex(fab[j]))
        for f in sorted(glob.glob(os.path.expanduser(f"~/.mame/nvram/{j}/*"))):
            if 0 < os.path.getsize(f) < 200000:
                fuentes.append(open(f, "rb").read())
        for d in fuentes:
            if analiza(j, d): vistos = True; break
        if not vistos: print(f"  {j:<10} nada con forma de tabla")
