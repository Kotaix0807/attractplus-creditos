#!/usr/bin/env python3
"""Exporta las puntuaciones de cada juego a un fichero legible.

    ./puntajes.py                      todos los juegos que tengan datos
    ./puntajes.py pacman 1943          solo esos
    ./puntajes.py --listar             que se sabe decodificar y que no
    ./puntajes.py --capturar defecto   apunta la tabla ACTUAL como la de fabrica

POR QUE ESTO Y NO OTRA COSA
---------------------------
Las puntuaciones ya se guardan solas: el plugin 'hiscore' de MAME lee la tabla
de la RAM del juego y la escribe en <hi_path>/<juego>.hi. Eso es lo que permite
conservar los puntajes SIN conservar los creditos, que es justo lo que se
buscaba: los creditos viven en la NVRAM y las puntuaciones no tienen por que.

Lo que falta es que ese .hi sea LEGIBLE: es un volcado crudo de memoria. Este
script lo traduce a un JSON que otro programa pueda consumir.

Se hace FUERA de MAME a proposito:
  - no toca creditos.lua ni depende de su ciclo de vida;
  - no corre dentro del emulador, asi que no depende de la version de Lua
    (la cabina tiene dos binarios, uno con 5.4 y otro con 5.5);
  - se puede lanzar cuando se quiera, incluso con la cabina apagada.

DE DONDE SALE CADA COSA
-----------------------
  hiscore.dat   (de MAME, 5856 juegos) dice DONDE vive la tabla de cada juego
                y cuanto ocupa. Es lo que trocea el .hi en bloques.
  puntajes.dat  (nuestro, al lado) dice COMO se lee ese bloque: cuantas
                entradas, cuantos bytes cada una, donde esta el nombre y donde
                la puntuacion. Eso hiscore.dat no lo sabe.

Anadir un juego nuevo = anadir una linea a puntajes.dat. No se toca este
fichero.
"""

import argparse
import json
import os
import re
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))


# ---------------------------------------------------------------- rutas
def mame_opcion(clave, mame=None):
    """Le pregunta la ruta al propio MAME, en vez de suponerla.

    Es la misma leccion que en instalar.sh y videos.sh: en esta maquina las
    rutas de MAME son unas y en la cabina otras, y -showconfig es quien sabe
    cual de sus mame.ini manda. Devuelve el valor con $HOME ya expandido.
    """
    import subprocess
    for cand in ([mame] if mame else []) + [
            os.path.expanduser("~/.local/share/groovymame-cabina/mame"),
            "groovymame", "mame"]:
        if not cand:
            continue
        try:
            salida = subprocess.run([cand, "-showconfig"], capture_output=True,
                                    text=True, timeout=30).stdout
        except (OSError, subprocess.SubprocessError):
            continue
        m = re.search(rf"^{clave}\s+(.*)$", salida, re.M)
        if m:
            v = m.group(1).strip()
            # -showconfig devuelve el valor CRUDO del ini, con el $HOME sin
            # expandir (en GroovyArcade el hi_path es "$HOME/shared/...").
            return os.path.expandvars(os.path.expanduser(v))
    return None


def ruta_hi():
    """Donde deja el plugin hiscore sus .hi.

    Ojo: hiscore.ini declara un hi_path, pero el plugin no siempre lo respeta
    y acaba escribiendo junto a si mismo. Se prueban los dos sitios y gana el
    que tenga ficheros de verdad.
    """
    candidatos = []
    ini = os.path.expanduser("~/.mame/hiscore.ini")
    if os.path.exists(ini):
        for linea in open(ini):
            if linea.startswith("hi_path"):
                candidatos.append(os.path.expandvars(linea.split(None, 1)[1].strip()))
    candidatos += [os.path.expanduser("~/.mame/hiscore"),
                   os.path.expanduser("~/.mame/hi")]
    for c in candidatos:
        if os.path.isdir(c) and any(f.endswith(".hi") for f in os.listdir(c)):
            return c
    return next((c for c in candidatos if os.path.isdir(c)), None)


def ruta_hiscore_dat():
    for c in (os.path.join(AQUI, "hiscore.dat"),
              "/usr/lib/mame/plugins/hiscore/hiscore.dat",
              os.path.expanduser("~/.mame/plugins/hiscore/hiscore.dat"),
              "/usr/share/games/mame/plugins/hiscore/hiscore.dat"):
        if os.path.exists(c):
            return c
    return None


# ------------------------------------------------- hiscore.dat: los bloques
def leer_hiscore_dat(ruta):
    """{juego: [(cpu, espacio, direccion, longitud), ...]}

    Formato, documentado en la cabecera del propio fichero:
        <juego>:            (varios seguidos: son alias del mismo bloque)
        @<cpu>,<espacio>,<dir>,<long>,<espera1>,<espera2>[,<relleno>]
    """
    juegos, pendientes = {}, []
    for linea in open(ruta, encoding="utf-8", errors="replace"):
        linea = linea.strip()
        if not linea or linea.startswith(";"):
            continue
        if linea.endswith(":"):
            # Varios nombres seguidos comparten los @ que vienen despues.
            pendientes.append(linea[:-1].split(",")[0].lower())
        elif linea.startswith("@"):
            p = linea[1:].split(",")
            if len(p) >= 4:
                try:
                    bloque = (p[0], p[1], int(p[2], 16), int(p[3], 16))
                except ValueError:
                    continue
                for j in pendientes:
                    juegos.setdefault(j, []).append(bloque)
        else:
            pendientes = []
    return juegos


# --------------------------------------------------- puntajes.dat: el formato
def leer_puntajes_dat(ruta):
    """{juego: {clave: valor}}, mismo espiritu que creditos.dat."""
    r = {}
    if not os.path.exists(ruta):
        return r
    for n, linea in enumerate(open(ruta, encoding="utf-8"), 1):
        linea = re.sub(r"#.*$", "", linea).strip()
        if not linea:
            continue
        partes = linea.split()
        nombre = partes[0]
        if "=" in nombre:
            # Mismo fallo mudo que ya mordio en arranque.dat: sin separador de
            # verdad, la linea se apunta como un juego que no existe y sus
            # ajustes no se aplican NUNCA, sin decir nada.
            print(f"  aviso: {ruta}:{n} linea sin separador: {linea}",
                  file=sys.stderr)
            continue
        r[nombre.lower()] = dict(p.split("=", 1) for p in partes[1:] if "=" in p)
    return r


# Juegos de silabas: el byte no es ASCII sino un indice en una tabla de
# caracteres propia de la placa. La mas comun con diferencia es esta.
ALFABETOS = {
    "capcom": "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ .,!?'\"-/",
    # Donkey Kong: el 0x10 es el espacio y las letras empiezan en 0x11. Se
    # dedujo de los sufijos ordinales que guarda junto al puesto (ST, ND, RD,
    # TH, TH), que solo encajan con ese desplazamiento.
    "dkong": "0123456789" + "\u00b7" * 6 + " ABCDEFGHIJKLMNOPQRSTUVWXYZ",
}


def texto(datos, modo):
    if modo == "ascii":
        return "".join(chr(b) if 32 <= b < 127 else " " for b in datos).strip()
    if modo.startswith("idx:"):
        tabla = ALFABETOS.get(modo[4:], modo[4:])
        return "".join(tabla[b] if b < len(tabla) else " " for b in datos).strip()
    raise ValueError(f"alfabeto desconocido: {modo}")


def numero(datos, modo):
    if modo == "bcd":            # 0x00 0x30 0x00 -> 3000
        return int(datos.hex())
    if modo == "digitos":        # un digito decimal por byte
        return int("".join(str(b) for b in datos) or "0")
    if modo == "bcdle":          # BCD pero con el byte bajo primero
        return int(datos[::-1].hex())
    if modo == "le":
        return int.from_bytes(datos, "little")
    if modo == "be":
        return int.from_bytes(datos, "big")
    raise ValueError(f"formato de puntuacion desconocido: {modo}")


def campo(spec):
    """'0,3,bcd' -> (0, 3, 'bcd')"""
    p = spec.split(",")
    return int(p[0]), int(p[1]), (p[2] if len(p) > 2 else "")


def descifrar(datos, cfg):
    """Trocea el bloque en entradas y devuelve una lista de dicts."""
    n = int(cfg["entradas"])
    ancho = int(cfg["bytes"])
    op, lp, fp = campo(cfg["puntos"])
    on, ln, fn = campo(cfg["nombre"]) if "nombre" in cfg else (0, 0, "")
    mult = int(cfg.get("multiplica", 1))

    salida = []
    for i in range(n):
        e = datos[i * ancho:(i + 1) * ancho]
        if len(e) < ancho:
            break
        fila = {"puesto": i + 1, "puntos": numero(e[op:op + lp], fp) * mult}
        if ln:
            fila["nombre"] = texto(e[on:on + ln], fn)
        if "nivel" in cfg:
            oL, lL, _ = campo(cfg["nivel"] + ",,")
            fila["nivel"] = int.from_bytes(e[oL:oL + lL], "big")
        fila["crudo"] = e.hex()
        salida.append(fila)
    return salida


# ------------------------------------------------------------------ el grueso
def puntajes_de(juego, bloques, cfg, dir_hi):
    """Lee el .hi del juego y lo descifra. Devuelve (lista, aviso)."""
    fichero = os.path.join(dir_hi, juego + ".hi")
    if not os.path.exists(fichero):
        return None, "sin datos guardados todavia"
    datos = open(fichero, "rb").read()
    if not datos:
        return None, "el fichero esta vacio"

    if not cfg:
        return None, f"sin receta en puntajes.dat ({len(datos)} bytes guardados)"

    # El .hi es la concatenacion de los bloques que declara hiscore.dat, en
    # orden. 'bloque=N' elige cual de ellos lleva la tabla.
    idx = int(cfg.get("bloque", 0))
    desde = sum(b[3] for b in bloques[:idx]) if bloques else 0
    largo = bloques[idx][3] if bloques and idx < len(bloques) else len(datos)
    trozo = datos[desde:desde + largo]
    if len(trozo) < int(cfg["entradas"]) * int(cfg["bytes"]):
        return None, (f"el bloque {idx} tiene {len(trozo)} bytes y la receta "
                      f"pide {int(cfg['entradas']) * int(cfg['bytes'])}")
    return descifrar(trozo, cfg), None


def marcar_defectos(juego, filas, defectos):
    """Marca las entradas que son las de fabrica.

    Un juego recien instalado trae una tabla puesta por la ROM -- las de Q*bert
    o las 'I.F / MTJ / NSO' de Bubble Bobble. Esas no son de nadie, asi que se
    marcan para que el programa que lea el JSON pueda descartarlas.

    La comparacion es por (nombre, puntos): si un jugador iguala exactamente una
    linea de fabrica se marcara tambien, pero es preferible a colar cinco
    puntuaciones fantasma en cada juego que nadie ha tocado.
    """
    base = defectos.get(juego)
    for f in filas:
        if base is None:
            f["defecto"] = None          # no se sabe: nadie ha capturado la base
        else:
            f["defecto"] = [f.get("nombre", ""), f["puntos"]] in base
    return filas


def main():
    ap = argparse.ArgumentParser(add_help=False)
    ap.add_argument("juegos", nargs="*")
    ap.add_argument("--listar", action="store_true")
    ap.add_argument("--capturar", action="store_true",
                    help="apunta la tabla actual como la de fabrica")
    ap.add_argument("--salida", default=os.environ.get(
        "SALIDA", os.path.expanduser("~/.attract/puntajes.json")))
    ap.add_argument("--hi", default=os.environ.get("HI_PATH"))
    ap.add_argument("-h", "--help", action="store_true")
    a = ap.parse_args()
    if a.help:
        print(__doc__)
        return 0

    hd = ruta_hiscore_dat()
    if not hd:
        print("no encuentro hiscore.dat (el de MAME, del plugin hiscore)",
              file=sys.stderr)
        return 1
    dir_hi = a.hi or ruta_hi()
    if not dir_hi:
        print("no encuentro el directorio donde el plugin hiscore guarda los .hi",
              file=sys.stderr)
        return 1

    bloques = leer_hiscore_dat(hd)
    recetas = leer_puntajes_dat(os.path.join(AQUI, "puntajes.dat"))
    f_def = os.path.join(AQUI, "puntajes_defecto.json")
    defectos = json.load(open(f_def)) if os.path.exists(f_def) else {}

    print(f"# hiscore.dat: {hd} ({len(bloques)} juegos)")
    print(f"# .hi:         {dir_hi}")
    print(f"# recetas:     {len(recetas)} en puntajes.dat")

    disponibles = sorted(f[:-3] for f in os.listdir(dir_hi) if f.endswith(".hi"))
    juegos = a.juegos or disponibles

    if a.listar:
        print(f"\n{'juego':<14} {'receta':<8} datos")
        for j in disponibles:
            print(f"  {j:<12} {'SI' if j in recetas else '--':<8} "
                  f"{os.path.getsize(os.path.join(dir_hi, j + '.hi'))} bytes")
        faltan = [j for j in disponibles if j not in recetas]
        if faltan:
            print(f"\nSin receta ({len(faltan)}): {' '.join(faltan)}")
            print("Anade una linea a puntajes.dat para cada uno.")
        return 0

    resultado, sin_receta = {}, []
    for j in juegos:
        filas, aviso = puntajes_de(j, bloques.get(j, []), recetas.get(j), dir_hi)
        if filas is None:
            sin_receta.append((j, aviso))
            continue
        resultado[j] = marcar_defectos(j, filas, defectos)

    if a.capturar:
        for j, filas in resultado.items():
            defectos[j] = [[f.get("nombre", ""), f["puntos"]] for f in filas]
            print(f"  {j}: {len(filas)} entradas apuntadas como de fabrica")
        json.dump(defectos, open(f_def, "w"), indent=1, ensure_ascii=False)
        print(f"\nBase de fabrica en {f_def}")
        return 0

    os.makedirs(os.path.dirname(a.salida), exist_ok=True)
    tmp = a.salida + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(resultado, f, indent=1, ensure_ascii=False)
    os.replace(tmp, a.salida)      # atomico: nadie lee un JSON a medias

    print()
    for j, filas in sorted(resultado.items()):
        reales = [f for f in filas if f.get("defecto") is False]
        print(f"  {j:<12} {len(filas)} entradas, "
              f"{len(reales) if defectos.get(j) else '?'} de jugadores")
        for f in filas[:3]:
            marca = {True: " (de fabrica)", False: "", None: " (?)"}[f.get("defecto")]
            print(f"       {f['puesto']}. {f.get('nombre', ''):<6} "
                  f"{f['puntos']:>10}{marca}")
    if sin_receta:
        print(f"\n  sin descifrar ({len(sin_receta)}):")
        for j, aviso in sin_receta:
            print(f"       {j:<12} {aviso}")
    print(f"\n# {len(resultado)} juegos -> {a.salida}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
