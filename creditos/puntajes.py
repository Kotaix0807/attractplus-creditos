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

    OJO con 'rompath': puede traer VARIAS rutas separadas por ';' (aqui son
    tres). Se devuelve la cadena entera y se le pasa asi a MAME, que ya sabe
    recorrerlas. Quedarse con la primera que exista deja fuera casi todas las
    roms.
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
    juegos, pendientes, en_bloques = {}, [], False
    for linea in open(ruta, encoding="utf-8", errors="replace"):
        linea = linea.strip()
        if not linea or linea.startswith(";"):
            continue
        # Hay nombres con comentario detras: "pacmini:  ; missing". Sin quitarlo
        # la linea no acaba en ":" y el parser la tomaba por desconocida,
        # reiniciando el grupo y dejando a pacman sin bloques.
        linea = linea.split(";")[0].strip()
        if not linea:
            continue
        if linea.endswith(":"):
            # Un nombre DESPUES de los @ empieza una entrada nueva. Sin este
            # corte los nombres se acumulaban y cada juego heredaba los bloques
            # de todos los anteriores: dkong salia con 32 KB en vez de 179
            # bytes. Las lineas en blanco tambien separan, pero saltarselas era
            # justo lo que ocultaba el fallo.
            if en_bloques:
                pendientes, en_bloques = [], False
            pendientes.append(linea[:-1].split(",")[0].lower())
        elif linea.startswith("@"):
            en_bloques = True
            p = linea[1:].split(",")
            if len(p) >= 4:
                try:
                    bloque = (p[0], p[1], int(p[2], 16), int(p[3], 16))
                except ValueError:
                    continue
                for j in pendientes:
                    juegos.setdefault(j, []).append(bloque)
        else:
            pendientes, en_bloques = [], False
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
    try:
        if modo == "bcd":            # 0x00 0x30 0x00 -> 3000
            return int(datos.hex())
        if modo == "texto":      # los digitos van escritos en ASCII: "007000"
            t = datos.decode("ascii", "ignore").strip()
            if not t.isdigit():
                raise RecetaNoEncaja(f"{datos.hex()} no son digitos ASCII")
            return int(t)
        if modo == "digitos":        # un digito decimal por byte
            return int("".join(str(b) for b in datos) or "0")
        if modo == "bcdle":          # BCD pero con el byte bajo primero
            return int(datos[::-1].hex())
    except ValueError:
        raise RecetaNoEncaja(f"{datos.hex()} no es un {modo} valido")
    if modo == "le":
        return int.from_bytes(datos, "little")
    if modo == "be":
        return int.from_bytes(datos, "big")
    raise ValueError(f"formato de puntuacion desconocido: {modo}")


def campo(spec):
    """'0,3,bcd' -> (0, 3, 'bcd')"""
    p = spec.split(",")
    return int(p[0]), int(p[1]), (p[2] if len(p) > 2 else "")


class RecetaNoEncaja(Exception):
    """La receta no sabe leer estos bytes.

    Pasa con las propuestas automaticas: el detector las dedujo de una tabla y
    al aplicarlas a otra aparecen bytes que ese formato no admite (un BCD con
    nibbles A-F, por ejemplo). No debe tumbar la herramienta: se marca ese
    juego como no descifrable y se sigue con los demas.
    """


def descifrar(datos, cfg):
    """Trocea el bloque en entradas y devuelve una lista de dicts."""
    n = int(cfg["entradas"])
    ancho = int(cfg["bytes"])
    op, lp, fp = campo(cfg["puntos"])
    on, ln, fn = campo(cfg["nombre"]) if "nombre" in cfg else (0, 0, "")
    # Algunas placas no intercalan los campos: guardan TODAS las puntuaciones
    # seguidas y luego todos los nombres (Atari Tetris). 'nombres=' da el
    # desplazamiento absoluto de ese segundo bloque.
    par = campo(cfg["nombres"]) if "nombres" in cfg else None
    mult = int(cfg.get("multiplica", 1))

    salida = []
    orden = range(n)
    if cfg.get("orden") == "asc":
        # Kung-Fu Master guarda sus 20 posiciones de MENOR a MAYOR: la ultima
        # es el record. Se le da la vuelta para que 'puesto 1' sea siempre el
        # mejor, como en todos los demas.
        orden = range(n - 1, -1, -1)
    for puesto, i in enumerate(orden):
        e = datos[i * ancho:(i + 1) * ancho]
        if len(e) < ancho:
            break
        fila = {"puesto": puesto + 1, "puntos": numero(e[op:op + lp], fp) * mult,
                # Una receta 'confirmada' se comparo con lo que el juego ensena
                # en pantalla. Las que no, las propuso el detector y pueden
                # estar mal -- a dkong le sobraba un x10 y solo se vio mirando
                # su tabla de atraccion. El programa que lea el JSON deberia
                # tratarlas con cuidado.
                "confirmado": cfg.get("confirmado", "no") == "si"}
        if par:
            base, largo, alf = par
            fila["nombre"] = texto(datos[base + i * largo:base + (i + 1) * largo],
                                   alf or "ascii")
        elif ln:
            fila["nombre"] = texto(e[on:on + ln], fn)
        if "nivel" in cfg:
            oL, lL, _ = campo(cfg["nivel"] + ",,")
            fila["nivel"] = int.from_bytes(e[oL:oL + lL], "big")
        fila["crudo"] = e.hex()
        salida.append(fila)
    return salida


# ----------------------------------------------------- deteccion automatica
#
# Escribir una receta a mano por juego no escala: hay 94 instalados y la idea es
# que se puedan anadir mas. Pero una tabla de puntuaciones tiene una propiedad
# que la delata y que casi ninguna otra estructura cumple: **esta ordenada de
# mayor a menor**. Con eso y con que el bloque se divida en partes iguales se
# puede buscar el formato a base de probar.
#
# El detector NO escribe nada en puntajes.dat: propone la linea y la persona
# decide. Una receta equivocada es peor que ninguna, y eso ya costo un error de
# 10x en dkong.

FORMATOS = (("bcd", 2, 4), ("bcdle", 2, 4), ("digitos", 4, 8),
            ("be", 2, 4), ("le", 2, 4))


def _descendente(v):
    """Ordenada, en cualquiera de los dos sentidos.

    Casi todos los juegos guardan el record primero, pero no todos: Kung-Fu
    Master guarda sus 20 posiciones de menor a mayor. Buscar solo descendente
    dejaba fuera ese caso y proponia una lectura equivocada.
    """
    return (all(v[i] >= v[i + 1] for i in range(len(v) - 1))
            or all(v[i] <= v[i + 1] for i in range(len(v) - 1)))


def _valido(trozo, fmt):
    """Descarta lecturas imposibles ANTES de mirar si la tabla ordena.

    Son dos comprobaciones baratas y muy selectivas:
      - 'digitos' guarda un digito decimal por byte, asi que ningun byte
        puede pasar de 9;
      - 'bcd' guarda dos por byte, asi que ningun nibble puede ser A-F.
    Sin esto el detector proponia leer como BCD campos que no lo son y salian
    puntuaciones parecidas pero mal (15000 leido como 10500).
    """
    if fmt == "digitos":
        return all(b <= 9 for b in trozo)
    if fmt in ("bcd", "bcdle"):
        return all((b >> 4) <= 9 and (b & 15) <= 9 for b in trozo)
    return True


def _plausible(puntos):
    """Descarta lo que no puede ser una tabla de puntuaciones."""
    if max(puntos) <= 0:
        return False                      # alguna posicion tiene que puntuar
    if puntos[0] > 99999999:
        return False                      # ninguna recreativa llega ahi
    if len(set(puntos)) == 1 and puntos[0] > 0:
        return True                       # todas iguales: tipico de fabrica
    return _descendente(puntos)


def _nombre_posible(datos, w, n, prohibido):
    """Busca un campo de 3 caracteres que parezca iniciales."""
    mejor = None
    for off in range(0, w - 2):
        if any(off < p[1] and p[0] < off + 3 for p in prohibido):
            continue
        for alf in ("ascii", "idx:capcom"):
            vistos = []
            for i in range(n):
                trozo = datos[i * w + off:i * w + off + 3]
                try:
                    t = texto(trozo, alf)
                except Exception:
                    t = ""
                vistos.append(t)
            # Iniciales de verdad: casi todo letras/digitos y no todo vacio.
            utiles = [t for t in vistos if t and all(
                c.isalnum() or c in " .-" for c in t)]
            if len(utiles) >= max(2, n // 2):
                nota = len(utiles) + (2 if any(t.strip() for t in vistos) else 0)
                if not mejor or nota > mejor[0]:
                    mejor = (nota, off, alf)
    return mejor


def detectar(datos):
    """Devuelve una lista de recetas candidatas, la mejor primero."""
    salida, L = [], len(datos)
    for n in range(3, 21):
        if L % n or L // n < 4 or L // n > 64:
            continue
        w = L // n
        for fmt, lmin, lmax in FORMATOS:
            for lp in range(lmin, min(lmax, w) + 1):
                for op in range(0, w - lp + 1):
                    trozos = [datos[i * w + op:i * w + op + lp] for i in range(n)]
                    if not all(_valido(t, fmt) for t in trozos):
                        continue
                    try:
                        puntos = [numero(t, fmt) for t in trozos]
                    except ValueError:
                        continue
                    if not _plausible(puntos):
                        continue
                    nom = _nombre_posible(datos, w, n, [(op, op + lp)])
                    # La nota premia lo que distingue a una tabla de verdad:
                    #   - casi todas las recreativas puntuan de 10 en 10;
                    #   - un campo de puntuacion LARGO es mejor que uno corto
                    #     que da un numero parecido leyendo media cifra;
                    #   - valores distintos entre si, no todo el mismo relleno.
                    # Los pesos salen de mirar en que se equivocaba: proponia
                    # leer 4 bytes como entero (numeros enormes y no redondos) y
                    # trocear un bloque en el doble de entradas leyendo el
                    # relleno (todas iguales). De ahi los dos correctivos
                    # fuertes: casi toda recreativa puntua de 10 en 10, y una
                    # tabla de verdad tiene valores DISTINTOS.
                    redondas = all(v % 10 == 0 for v in puntos)
                    # Un millon como techo NO es arbitrario: leer 4 bytes
                    # como entero grande da siempre numeros de siete cifras, y
                    # es el error tipico del detector. Las tablas de fabrica de
                    # los clasicos se quedan muy por debajo. Es una penalizacion,
                    # no un rechazo, porque hay juegos que si llegan.
                    enorme = max(puntos) > 1000000
                    nota = (n * 2 + lp
                            + (12 if redondas else 0)
                            + (-12 if enorme else 0)
                            # Y por abajo: la PRIMERA posicion de una tabla no
                            # baja de 1000 en ningun clasico. Sin esto el
                            # detector confundia la tabla con el campo de la
                            # ronda alcanzada, que tambien va ordenado de mayor
                            # a menor y por eso colaba (31, 27, 23, 19, 15).
                            + (-10 if max(puntos) < 1000 else 0)
                            + len(set(puntos)) * 3
                            + (4 if _descendente(puntos) and len(set(puntos)) > 1 else 0)
                            + (nom[0] if nom else 0))
                    salida.append({
                        "nota": nota, "entradas": n, "bytes": w,
                        "puntos": f"{op},{lp},{fmt}",
                        "nombre": f"{nom[1]},3,{nom[2]}" if nom else None,
                        "valores": puntos,
                    })
    salida.sort(key=lambda c: -c["nota"])
    # Quitar duplicados que solo cambian el formato pero dan lo mismo
    vistos, unicos = set(), []
    for c in salida:
        clave = (c["entradas"], c["bytes"], tuple(c["valores"]))
        if clave in vistos:
            continue
        vistos.add(clave)
        unicos.append(c)
    return unicos


def region_util(datos, margen=16):
    """Acota la zona con contenido de un fichero de NVRAM.

    Una NVRAM son kilobytes casi todos a 00 o a ff, con la tabla en un rincon.
    Buscar la tabla por todo el fichero es carisimo y ademas encuentra basura,
    asi que primero se acota a donde hay algo escrito.
    """
    vivos = [i for i, b in enumerate(datos) if b not in (0, 0xff)]
    if not vivos:
        return None
    ini = max(0, vivos[0] - margen)
    fin = min(len(datos), vivos[-1] + 1 + margen)
    return ini, fin


def detectar_en_ventana(datos, tope=2048):
    """Como detectar(), pero buscando la tabla DENTRO de un bloque grande.

    Es lo que hace falta para la NVRAM: alli la tabla no ocupa el fichero
    entero, asi que no vale exigir que el bloque se divida en partes iguales.

    El primer intento fue deslizar una ventana llamando a detectar() en cada
    posicion, y era inviable: minutos por fichero. Aqui se le da la vuelta --
    para cada formato posible se leen de una pasada TODAS las posiciones
    separadas por el mismo paso, y se buscan tramos seguidos que vayan de mayor
    a menor. Es un barrido por formato en vez de una busqueda por posicion.
    """
    r = region_util(datos)
    if not r:
        return []
    ini, fin = r
    if fin - ini > tope:
        fin = ini + tope
    zona = datos[ini:fin]
    L = len(zona)
    salida = []

    for w in range(4, 33):
        for fmt, lmin, lmax in FORMATOS:
            for lp in range(lmin, min(lmax, w) + 1):
                for op in range(0, w - lp + 1):
                    # Todas las posiciones de esta rejilla, de una pasada.
                    val, pos = [], []
                    k = op
                    while k + lp <= L:
                        t = zona[k:k + lp]
                        val.append(numero(t, fmt) if _valido(t, fmt) else None)
                        pos.append(k)
                        k += w
                    # Tramos seguidos que no suben y que son creibles.
                    i = 0
                    while i < len(val):
                        if val[i] is None:
                            i += 1
                            continue
                        j = i
                        while (j + 1 < len(val) and val[j + 1] is not None
                               and val[j + 1] <= val[j]):
                            j += 1
                        n = j - i + 1
                        if 4 <= n <= 12:
                            puntos = val[i:j + 1]
                            # En un fichero grande hay rachas larguisimas de
                            # ceros y de 0xffff (relleno de la memoria borrada)
                            # que cumplen "no sube" sin significar nada. Una
                            # tabla de verdad tiene varios valores DISTINTOS y
                            # positivos, y casi ningun cero.
                            distintos = {v for v in puntos if v}
                            basura = (0xffff in puntos or 0xffffff in puntos
                                      or puntos.count(0) > 1)
                            if (_plausible(puntos) and max(puntos) >= 1000
                                    and len(distintos) >= 3 and not basura):
                                trozo = zona[pos[i]:pos[i] + n * w]
                                nom = _nombre_posible(trozo, w, n, [(op, op + lp)])
                                redondas = all(v % 10 == 0 for v in puntos)
                                nota = (n * 2 + lp
                                        + (12 if redondas else 0)
                                        + (-12 if max(puntos) > 1000000 else 0)
                                        + len(set(puntos)) * 3
                                        + (nom[0] if nom else 0))
                                salida.append({
                                    "nota": nota, "entradas": n, "bytes": w,
                                    "puntos": f"{op},{lp},{fmt}",
                                    "nombre": (f"{nom[1]},3,{nom[2]}"
                                               if nom else None),
                                    "valores": puntos,
                                    "desde": ini + pos[i] - op,
                                })
                        i = j + 1

    salida.sort(key=lambda c: -c["nota"])
    vistos, unicos = set(), []
    for c in salida:
        clave = tuple(c["valores"])
        if clave in vistos:
            continue
        vistos.add(clave)
        unicos.append(c)
    return unicos[:6]


# ------------------------------------------------------------------ el grueso
# Los unicos comparados con lo que el juego ensena en su marcador. El resto se
# lee bien hasta donde se sabe, pero nadie lo ha mirado en pantalla.
VERIFICADOS = {"1943", "arkanoid", "bublbobl", "commando", "contra", "ddragon",
               "dkong", "dkong3", "gradius", "kungfum", "mappy", "mspacman",
               "pacman", "robocop", "sf2", "zaxxon"}

DB_HI2TXT = None          # lo fija main() con --hi2txt o buscandolo
FABRICA = {}              # tablas leidas de la RAM con --fabrica


def _recortar(filas):
    """Quita las posiciones vacias del final: son relleno, no puntuaciones."""
    while filas and not filas[-1].get("puntos"):
        filas.pop()
    return filas


def _cortar_donde_deja_de_ordenar(filas):
    """Se queda con el tramo ordenado del principio.

    Cuando el XML declara mas posiciones de las que la tabla tiene de verdad,
    detras vienen bytes que no son puntuaciones. Lo real va ordenado y el
    relleno rompe el orden, asi que ahi esta el corte: avsp declaraba 49
    posiciones y las buenas son las primeras.
    """
    if len(filas) < 3:
        return filas
    p = [f["puntos"] for f in filas]
    baja = p[0] >= p[1]
    fin = 1
    while fin < len(p) and ((p[fin - 1] >= p[fin]) if baja else (p[fin - 1] <= p[fin])):
        fin += 1
    return filas[:fin]


def _parece_tabla(filas):
    """Ultimo filtro antes de dar un descifrado por bueno.

    Hace falta porque descifrar "lo que quepa" cuando los datos son mas cortos
    que la estructura tambien deja pasar basura: tmnt salia con CIEN posiciones
    de 312, 257, 206... Numeros que bajan, pero que no son puntuaciones de
    nadie. Es preferible decir "no se descifra" que publicar eso.
    """
    # 64 y no 40: Alien vs Predator tiene una tabla DE VERDAD de 49 posiciones
    # (300000, 250000, 200000, 150000, 100000, 90000...), asi que un tope bajo
    # tiraba un descifrado correcto. Lo que separa a tmnt, que salia con cien,
    # no es la longitud sino que sus valores no son puntuaciones de nadie.
    if not filas or len(filas) > 64:
        return False
    p = [f["puntos"] for f in filas]
    # Nada de exigir un minimo alto. Lo probe con 1000 y se llevaba por delante
    # tres casos buenos para cazar uno malo: asteroid con una unica puntuacion
    # de 590 (real, de una partida), y kof99/kof2000 con su escalera
    # 100/90/80/70/60. El tope de posiciones ya basta para tirar la basura.
    if max(p) <= 0:
        return False
    # Una tabla va ordenada, en un sentido o en el otro.
    baja = all(p[i] >= p[i + 1] for i in range(len(p) - 1))
    sube = all(p[i] <= p[i + 1] for i in range(len(p) - 1))
    return baja or sube


def datos_de(juego, cfg, dir_hi, fabrica=None):
    """De donde salen los bytes de ese juego. Devuelve (datos, origen, aviso).

    Hay TRES sitios, y el orden lo decide el XML de hi2txt, no una lista fija:

      .hi      lo escribe el plugin hiscore, para los juegos de hiscore.dat.
      fabrica  la tabla que leimos nosotros de la RAM con --fabrica. Sirve como
               .hi mientras nadie haya jugado, que es el caso de casi todos.
      memoria  nvram, saveram, eeprom, x2212... MAME no los llama a todos
               igual, asi que se prueba lo que el XML pida.

    Preguntar al XML es lo que arregla el caso que mas fallaba: juegos como
    simpsons2p tienen un fichero 'eeprom' escrito Y una estructura que describe
    el .hi. Cogiendo el eeprom por estar ahi, el descifrado fallaba con "no hay
    estructura para la fuente eeprom" teniendo el dato bueno al lado.
    """
    fuente = (cfg or {}).get("fuente", "auto")
    hi = os.path.join(dir_hi, juego + ".hi")
    carpeta = os.path.expanduser(f"~/.mame/nvram/{juego}")

    def leer(ruta):
        if os.path.exists(ruta) and os.path.getsize(ruta):
            return open(ruta, "rb").read()
        return None

    quiere = []
    if DB_HI2TXT:
        try:
            import hi2txt
            quiere = hi2txt.fuentes_declaradas(
                os.path.join(DB_HI2TXT, juego + ".xml"))
        except Exception:
            quiere = []

    # El orden de preferencia sale del XML; si no dice nada, .hi primero. Y de
    # ultimo recurso, CUALQUIER fichero que MAME haya dejado en la carpeta del
    # juego: los nombres son del chip, no un juego de tres o cuatro conocidos
    # (ncv2 guarda en 'at28c16', que es una EEPROM de Atmel).
    # Los ficheros sueltos SOLO se prueban cuando el XML no dice nada. Si el
    # XML pide el .hi y no lo hay, leer el nvram en su lugar da datos
    # garantizadamente equivocados -- y encima sin fallar: arkanoid pasaba a
    # marcar 0 en vez de 50000 y parecia un descifrado valido.
    sueltos = (sorted(os.listdir(carpeta))
               if not quiere and os.path.isdir(carpeta) else [])
    orden = quiere or [".hi"]
    for nombre in orden + ([".hi"] if not quiere else []) + sueltos:
        if fuente not in ("auto", "hi", "nvram", nombre):
            continue
        if nombre == ".hi":
            d = leer(hi)
            if d:
                return d, "hi", None
            if fabrica and juego in fabrica:
                return bytes.fromhex(fabrica[juego]), "fabrica", None
        else:
            d = leer(os.path.join(carpeta, nombre))
            if d:
                return d, nombre, None
    return None, None, "sin datos guardados todavia"


def puntajes_de(juego, bloques, cfg, dir_hi):
    """Lee los datos del juego y los descifra. Devuelve (lista, origen, aviso).

    Se intenta PRIMERO con hi2txt-xml, que es una base comunitaria con la
    estructura de unos 3.100 juegos, y solo si ese juego no esta descrito se
    cae a las recetas propias de puntajes.dat. Validado: de los 13 juegos que
    yo habia comprobado contra el marcador en pantalla, hi2txt acierta los 12
    que tiene descritos, al numero exacto.
    """
    datos, origen, aviso = datos_de(juego, cfg, dir_hi, FABRICA)
    if datos is None:
        return None, None, aviso

    if DB_HI2TXT:
        xml = os.path.join(DB_HI2TXT, juego + ".xml")
        if os.path.exists(xml):
            try:
                import hi2txt
                filas, _ = hi2txt.puntuaciones(
                    xml, datos, ".hi" if origen in ("hi", "fabrica") else origen)
                filas = _cortar_donde_deja_de_ordenar(_recortar(filas))
                if filas and _parece_tabla(filas):
                    for f in filas:
                        f["receta"] = "hi2txt"
                        # 'confirmado' significa comparado con el marcador del
                        # propio juego, y eso solo se ha hecho con 15. Que
                        # hi2txt acierte esos 15 da confianza en los demas,
                        # pero no es lo mismo y no hay que decir que si lo es:
                        # kof99 da 100/90/80 donde kof97 da 100000/80000, y una
                        # de las dos lecturas esta mal.
                        f["confirmado"] = juego in VERIFICADOS
                    return filas, origen, None
            except Exception as e:
                aviso = f"hi2txt no pudo: {e}"

    if not cfg:
        return None, origen, aviso or f"sin receta ({len(datos)} bytes en {origen})"

    # El .hi es la concatenacion de los bloques que declara hiscore.dat, en
    # orden. 'bloque=N' elige cual de ellos lleva la tabla.
    # swap=2: los bytes van intercambiados por parejas (placas de 16 bits).
    # Es lo mismo que el byte-swap de los XML de hi2txt, pero para las recetas
    # propias, que tambien lo necesitan al leer un saveram de NeoGeo.
    paso = int(cfg.get("swap", 0))
    if paso > 1:
        b = bytearray(datos)
        for i in range(0, len(b) - paso + 1, paso):
            b[i:i + paso] = b[i:i + paso][::-1]
        datos = bytes(b)

    idx = int(cfg.get("bloque", 0))
    if origen in ("nvram", "saveram", "eeprom", "earom", "x2212", "at28c16"):
        # En la NVRAM no hay bloques de hiscore.dat: la receta dice el
        # desplazamiento a pelo con 'desde='.
        desde = int(cfg.get("desde", "0"), 0)
        largo = len(datos) - desde
    else:
        desde = sum(b[3] for b in bloques[:idx]) if bloques else 0
        largo = bloques[idx][3] if bloques and idx < len(bloques) else len(datos)
    trozo = datos[desde:desde + largo]
    if len(trozo) < int(cfg["entradas"]) * int(cfg["bytes"]):
        return None, origen, (f"el bloque tiene {len(trozo)} bytes y la receta "
                              f"pide {int(cfg['entradas']) * int(cfg['bytes'])}")
    try:
        return descifrar(trozo, cfg), origen, None
    except RecetaNoEncaja as e:
        return None, origen, f"la receta no encaja con estos datos ({e})"


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


def capturar_fabrica(juegos, bloques, mame, rompath):
    """Arranca cada juego y lee de la RAM su tabla DE FABRICA.

    Hace falta porque el plugin hiscore solo escribe su .hi cuando la tabla
    CAMBIA respecto a como estaba al arrancar (init.lua: comprueba
    'checksum ~= default_checksum'). O sea que un juego que nadie ha jugado no
    deja ningun fichero, y sin datos no hay ni receta ni base de fabrica.

    Leyendola nosotros se consigue las dos cosas de golpe, y para TODOS los
    juegos que esten en hiscore.dat, no solo para los seis que alguien jugo.
    """
    import subprocess
    lua = os.path.join(AQUI, "volcar.lua")
    if not os.path.exists(lua):
        print(f"falta {lua}", file=sys.stderr)
        return {}

    salida = {}
    for n, j in enumerate(juegos, 1):
        b = bloques.get(j)
        if not b:
            print(f"  {n:>3}/{len(juegos)}  {j:<12} no esta en hiscore.dat")
            continue
        espec = ";".join(f"{c.lstrip(':')},{e},{a:x},{l:x}" for c, e, a, l in b)
        entorno = dict(os.environ, GA_D_BLOQUES=espec, GA_D_FRAME="1800")
        try:
            r = subprocess.run(
                [mame, j, "-rompath", rompath, "-video", "none",
                 "-sound", "none", "-noswitchres", "-str", "45", "-nothrottle",
                 "-skip_gameinfo", "-autoboot_script", lua, "-autoboot_delay", "0"],
                capture_output=True, text=True, timeout=180, env=entorno,
                cwd=os.path.dirname(mame))
        except (OSError, subprocess.SubprocessError) as e:
            print(f"  {n:>3}/{len(juegos)}  {j:<12} no arranco ({e})")
            continue
        m = re.search(r"^\[volcado\] ([0-9a-f]*)$", r.stdout, re.M)
        if not m or not m.group(1):
            motivo = "sin volcado"
            if re.search(r"NOT FOUND|missing|Fatal error", r.stdout + r.stderr):
                motivo = "faltan roms"
            print(f"  {n:>3}/{len(juegos)}  {j:<12} {motivo}")
            continue
        salida[j] = m.group(1)
        print(f"  {n:>3}/{len(juegos)}  {j:<12} {len(m.group(1)) // 2} bytes")
    return salida


def main():
    ap = argparse.ArgumentParser(add_help=False)
    ap.add_argument("juegos", nargs="*")
    ap.add_argument("--listar", action="store_true")
    ap.add_argument("--detectar", action="store_true",
                    help="propone recetas mirando los datos guardados")
    ap.add_argument("--proponer", action="store_true",
                    help="anade a puntajes.dat la mejor receta de cada juego")
    ap.add_argument("--fabrica", action="store_true",
                    help="arranca cada juego y lee de la RAM su tabla de fabrica")
    ap.add_argument("--mame", default=None)
    ap.add_argument("--roms", default=None)
    ap.add_argument("--capturar", action="store_true",
                    help="apunta la tabla actual como la de fabrica")
    ap.add_argument("--salida", default=os.environ.get(
        "SALIDA", os.path.expanduser("~/.attract/puntajes.json")))
    ap.add_argument("--hi", default=os.environ.get("HI_PATH"))
    ap.add_argument("--hi2txt", default=None,
                    help="carpeta db/ de hi2txt-xml (estructuras de ~3100 juegos)")
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

    global DB_HI2TXT
    try:
        import hi2txt as _h
        DB_HI2TXT = _h.buscar_db([a.hi2txt] if a.hi2txt else [])
    except ImportError:
        DB_HI2TXT = None

    bloques = leer_hiscore_dat(hd)
    recetas = leer_puntajes_dat(os.path.join(AQUI, "puntajes.dat"))
    f_def = os.path.join(AQUI, "puntajes_defecto.json")
    defectos = json.load(open(f_def)) if os.path.exists(f_def) else {}

    print(f"# hiscore.dat: {hd} ({len(bloques)} juegos)")
    if DB_HI2TXT:
        n_xml = len([f for f in os.listdir(DB_HI2TXT) if f.endswith(".xml")])
        print(f"# hi2txt:     {DB_HI2TXT} ({n_xml} estructuras)")
    else:
        print("# hi2txt:     no encontrado (usa --hi2txt <carpeta db>)")
    print(f"# .hi:         {dir_hi}")
    print(f"# recetas:     {len(recetas)} en puntajes.dat")

    disponibles = sorted(f[:-3] for f in os.listdir(dir_hi) if f.endswith(".hi"))
    juegos = a.juegos or disponibles

    f_fab = os.path.join(AQUI, "puntajes_fabrica.json")
    fabrica = json.load(open(f_fab)) if os.path.exists(f_fab) else {}
    global FABRICA
    FABRICA = fabrica

    if a.fabrica:
        mame = a.mame or os.path.expanduser(
            "~/.local/share/groovymame-cabina/mame")
        roms = a.roms or mame_opcion("rompath", mame) or ""
        if not os.path.exists(mame):
            print(f"no encuentro el emulador en {mame} (usa --mame)", file=sys.stderr)
            return 1
        lista = a.juegos or [l.split(";")[0] for l in
                             open(os.path.expanduser(
                                 "~/.attract/romlists/groovymame.txt"))][1:]
        print(f"# emulador: {mame}\n# roms: {roms}\n")
        nuevos = capturar_fabrica(lista, bloques, mame, roms)
        fabrica.update(nuevos)
        json.dump(fabrica, open(f_fab, "w"), indent=1)
        print(f"\n# {len(nuevos)} tablas de fabrica nuevas, "
              f"{len(fabrica)} en total -> {f_fab}")
        return 0

    if a.proponer:
        dat = os.path.join(AQUI, "puntajes.dat")
        ya = set(recetas)
        nuevas = []
        for j in sorted(set(list(fabrica) + disponibles)):
            if j in ya:
                continue
            datos, origen, _ = datos_de(j, recetas.get(j), dir_hi)
            if datos is None and j in fabrica:
                datos, origen = bytes.fromhex(fabrica[j]), "fabrica"
            if datos is None:
                continue
            b = bloques.get(j, [])
            trozo = datos[:b[0][3]] if b else datos
            c = detectar(trozo)
            if not c:
                continue
            mejor = c[0]
            nuevas.append((j, mejor,
                           f"{j} entradas={mejor['entradas']} bytes={mejor['bytes']} "
                           f"puntos={mejor['puntos']}"
                           + (f" nombre={mejor['nombre']}" if mejor["nombre"] else "")
                           + " confirmado=no"))
        if not nuevas:
            print("\nno hay nada nuevo que proponer")
            return 0
        with open(dat, "a", encoding="utf-8") as f:
            f.write("\n# --- propuestas automaticas del detector "
                    "-------------------------------\n#\n"
                    "# Las escribio ./puntajes.py --proponer mirando la tabla de\n"
                    "# fabrica de cada juego. Llevan 'confirmado=no' porque NADIE\n"
                    "# las ha comparado con lo que el juego ensena en pantalla, y\n"
                    "# esa comparacion es la unica prueba: a dkong le sobraba un\n"
                    "# x10 y solo se vio mirando su modo de atraccion.\n"
                    "#\n# Para confirmar una: mira su tabla en el juego, corrige la\n"
                    "# linea si hace falta y cambia a 'confirmado=si'.\n#\n")
            for j, mejor, linea in nuevas:
                f.write(f"# {j}: {mejor['valores'][:6]}\n{linea}\n")
        print(f"\n# {len(nuevas)} propuestas anadidas a {dat}")
        for j, mejor, _ in nuevas[:15]:
            print(f"   {j:<12} {mejor['valores'][:5]}")
        if len(nuevas) > 15:
            print(f"   ... y {len(nuevas) - 15} mas")
        return 0

    if a.detectar:
        for j in juegos:
            datos, origen, aviso = datos_de(j, recetas.get(j), dir_hi, fabrica)
            if datos is None and j in fabrica:
                datos, origen = bytes.fromhex(fabrica[j]), "fabrica"
            if datos is None:
                print(f"\n{j}: {aviso} (prueba --fabrica)")
                continue
            b = bloques.get(j, [])
            trozo = datos[:b[0][3]] if (b and origen == "hi") else datos
            print(f"\n=== {j} ({origen}, {len(trozo)} bytes) ===")
            cands = detectar(trozo)
            if not cands:
                print("  nada que parezca una tabla ordenada de puntuaciones.")
                print("  Puede que el bloque mezcle tabla y estado (le pasa a")
                print("  asteroid), o que el juego guarde una sola puntuacion.")
                continue
            for k, c in enumerate(cands[:4], 1):
                linea = (f"{j} entradas={c['entradas']} bytes={c['bytes']} "
                         f"puntos={c['puntos']}"
                         + (f" nombre={c['nombre']}" if c["nombre"] else "")
                         + (" fuente=nvram" if origen == "nvram" else ""))
                print(f"  {k}) {c['valores'][:8]}")
                print(f"     {linea}")
            print("  Elige la que tenga pinta de puntuaciones y pegala en "
                  "puntajes.dat.")
        return 0

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
        filas, origen, aviso = puntajes_de(j, bloques.get(j, []),
                                           recetas.get(j), dir_hi)
        if filas is None:
            # Aun sin receta se exporta lo que hay: asi el fichero cubre TODOS
            # los juegos desde el primer dia y el programa que lo lea no se
            # queda sin nada. Cuando aparezca la receta, la misma entrada pasa a
            # traer los puntajes descifrados.
            datos, org, _ = datos_de(j, recetas.get(j), dir_hi, fabrica)
            if datos is not None:
                resultado[j] = {"descifrado": False, "origen": org,
                                "motivo": aviso, "crudo": datos.hex()}
            sin_receta.append((j, aviso))
            continue
        resultado[j] = {"descifrado": True, "origen": origen,
                        "puestos": marcar_defectos(j, filas, defectos)}

    if a.capturar:
        # La base sale de las tablas que --fabrica leyo de la RAM: son las que
        # trae la ROM antes de que nadie juegue, que es justo la definicion de
        # "nombre ficticio". Asi se cubren TODOS los juegos capturados, no solo
        # los pocos que alguien ha jugado ya.
        for j, crudo in sorted(fabrica.items()):
            cfg = recetas.get(j)
            if not cfg:
                continue
            datos = bytes.fromhex(crudo)
            b = bloques.get(j, [])
            idx = int(cfg.get("bloque", 0))
            desde = sum(x[3] for x in b[:idx]) if b else 0
            largo = b[idx][3] if b and idx < len(b) else len(datos)
            trozo = datos[desde:desde + largo]
            if len(trozo) < int(cfg["entradas"]) * int(cfg["bytes"]):
                continue
            try:
                filas = descifrar(trozo, cfg)
            except RecetaNoEncaja as e:
                print(f"  {j:<12} la receta no encaja: {e}")
                continue
            defectos[j] = [[f.get("nombre", ""), f["puntos"]] for f in filas]
            print(f"  {j:<12} {len(filas)} entradas de fabrica  "
                  f"{[f['puntos'] for f in filas[:4]]}")
        json.dump(defectos, open(f_def, "w"), indent=1, ensure_ascii=False)
        print(f"\nBase de fabrica en {f_def}")
        return 0

    os.makedirs(os.path.dirname(a.salida), exist_ok=True)
    tmp = a.salida + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(resultado, f, indent=1, ensure_ascii=False)
    os.replace(tmp, a.salida)      # atomico: nadie lee un JSON a medias

    print()
    descifrados = {j: r for j, r in resultado.items() if r.get("descifrado")}
    for j, r in sorted(descifrados.items()):
        filas = r["puestos"]
        reales = [f for f in filas if f.get("defecto") is False]
        print(f"  {j:<12} [{r['origen']}] {len(filas)} entradas, "
              f"{len(reales) if defectos.get(j) else '?'} de jugadores")
        for f in filas[:3]:
            marca = {True: " (de fabrica)", False: "", None: " (?)"}[f.get("defecto")]
            print(f"       {f['puesto']}. {f.get('nombre', ''):<6} "
                  f"{f['puntos']:>10}{marca}")
    if sin_receta:
        con_datos = [x for x in sin_receta if x[0] in resultado]
        print(f"\n  con datos pero SIN descifrar ({len(con_datos)}): "
              "van al JSON en crudo")
        for j, aviso in con_datos[:12]:
            print(f"       {j:<12} {aviso}")
        if len(con_datos) > 12:
            print(f"       ... y {len(con_datos) - 12} mas")
        print("  Para sacarles la receta:  ./puntajes.py --detectar <juego>")
    print(f"\n# {len(resultado)} juegos ({len(descifrados)} descifrados) -> {a.salida}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
