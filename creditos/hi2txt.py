#!/usr/bin/env python3
"""Lee las descripciones XML de hi2txt para descifrar los .hi y las NVRAM.

hi2txt-xml (de GreatStoneEx) es una base comunitaria con la ESTRUCTURA INTERNA
de la tabla de puntuaciones de unos 3.100 juegos. Es la pieza que faltaba: el
hiscore.dat de MAME dice DONDE vive la tabla, y esto dice COMO se lee por
dentro, que es justo lo que yo estaba deduciendo a mano juego a juego.

    https://github.com/GreatStoneEx/hi2txt-xml       (GPL-2)

NO se copia al repo a proposito: es GPL-2 y ademas se actualiza sola. Se baja
igual que la coleccion de cheats, y esta funcion lee los XML de donde esten:

    ./puntajes.py --hi2txt ~/hi2txt-xml/src/main/db

DE LO QUE SE OCUPA
------------------
Un subconjunto del formato, el que usan los juegos de esta cabina (medido sobre
los 58 que tienen decodificador):

  <structure file=".hi"|"nvram">   de que fichero se lee
    <check><size>N</size>          para elegir entre varias estructuras
    <elt size type id .../>        un campo
    <loop count="N"> ... </loop>   una tabla

  type="int"   base=10|16, endianness, decoding-profile=bcd|bcd-le|base-40,
               nibble-skip=odd|even, byte-skip=0xNN
  type="text"  charset + ascii-offset
  type="raw"   se salta

Lo que NO se implementa, porque es presentacion y no hace falta: <format>,
<case>, <column display=...> y las etiquetas de salida.
"""

import os
import re
import xml.etree.ElementTree as ET


class NoSeSabe(Exception):
    """Ese XML usa algo que este lector no implementa."""


# --------------------------------------------------------------- utilidades
def _entero(txt, defecto=0):
    if txt is None:
        return defecto
    txt = txt.strip()
    try:
        return int(txt, 16) if txt.lower().startswith("0x") else int(txt)
    except ValueError:
        return defecto


def _quitar_nibbles(datos, modo):
    """nibble-skip: la mitad de cada byte es relleno.

    Lo usan las placas que guardan un digito por byte desperdiciando medio
    (Q*bert, los Williams). Sin esto sus tablas salen como numeros enormes sin
    sentido, que es donde se me atasco la busqueda a mano.
    """
    fuera = []
    for b in datos:
        fuera.append((b & 0x0F) if modo == "odd" else (b >> 4))
    return fuera


def _quitar_bytes(datos, valor):
    return bytes(b for b in datos if b != valor)


BASE40 = " ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.,-"


def _leer_int(trozo, elt):
    perfil = elt.get("decoding-profile", "")
    base = _entero(elt.get("base"), 10)
    little = elt.get("endianness", "") == "little_endian"

    if elt.get("byte-skip"):
        trozo = _quitar_bytes(trozo, _entero(elt.get("byte-skip")))
    if elt.get("nibble-skip"):
        digitos = _quitar_nibbles(trozo, elt.get("nibble-skip"))
        if little:
            digitos = digitos[::-1]
        return int("".join(f"{d:x}" for d in digitos) or "0", 16 if base == 16 else 10)

    if perfil in ("bcd", "bcd-le"):
        t = trozo[::-1] if (perfil == "bcd-le" or little) else trozo
        # Ojo: en estos XML "bcd" no siempre es BCD empaquetado. Cuando TODOS
        # los bytes valen 0-9 la placa esta guardando un digito por byte, y
        # leerlo como empaquetado multiplica el resultado por diez mil (1943
        # daba 200000000 en vez de 20000). Se distingue mirando los datos, que
        # es lo unico que no miente.
        if all(b <= 9 for b in t):
            return int("".join(str(b) for b in t) or "0")
        try:
            return int(t.hex())
        except ValueError:
            raise NoSeSabe(f"{trozo.hex()} no es BCD valido")
    if perfil:
        raise NoSeSabe(f"decoding-profile={perfil}")

    t = trozo[::-1] if little else trozo
    if base == 16:
        # base=16 aqui significa "cada byte son dos digitos decimales", que es
        # como lo entiende hi2txt: 0x12 -> 12, no 18.
        try:
            return int(t.hex())
        except ValueError:
            return int.from_bytes(t, "big")
    return int.from_bytes(t, "big")


def _leer_text(trozo, elt, charsets):
    tabla = charsets.get(elt.get("charset", ""), {})
    off = _entero(elt.get("ascii-offset"), 0)
    if elt.get("nibble-skip"):
        trozo = bytes(_quitar_nibbles(trozo, elt.get("nibble-skip")))
    fuera = []
    for b in trozo:
        if b in tabla:
            fuera.append(tabla[b])
        else:
            c = b + off
            fuera.append(chr(c) if 32 <= c < 127 else " ")
    return "".join(fuera).strip()


# ------------------------------------------------------------- el interprete
def _charsets(raiz):
    r = {}
    for cs in raiz.findall("charset"):
        tabla = {}
        for ch in cs.findall("char"):
            tabla[_entero(ch.get("src"))] = ch.get("dst", " ")
        r[cs.get("id", "")] = tabla
    return r


def _recorrer(nodo, datos, pos, charsets, filas, sueltos, dentro_bucle=None):
    """Recorre la estructura consumiendo bytes. Devuelve la posicion nueva."""
    for hijo in nodo:
        if hijo.tag == "loop":
            n = _entero(hijo.get("count"), 0)
            for i in range(n):
                fila = {}
                pos = _recorrer(hijo, datos, pos, charsets, filas, sueltos, fila)
                if fila:
                    filas.append(fila)
        elif hijo.tag == "elt":
            tam = _entero(hijo.get("size"), 0)
            trozo = datos[pos:pos + tam]
            pos += tam
            if len(trozo) < tam:
                raise NoSeSabe("los datos se acaban antes que la estructura")
            tipo = hijo.get("type", "raw")
            ident = hijo.get("id", "")
            if tipo == "raw":
                continue
            valor = (_leer_int(trozo, hijo) if tipo == "int"
                     else _leer_text(trozo, hijo, charsets) if tipo == "text"
                     else None)
            if valor is None:
                raise NoSeSabe(f"type={tipo}")
            destino = dentro_bucle if dentro_bucle is not None else sueltos
            destino[ident] = valor
    return pos


def _elegir_estructura(raiz, datos, fuente):
    """Un juego puede traer varias estructuras (versiones de MAME distintas).

    Se elige por el tamano declarado en <check><size>, que es como lo hace la
    propia herramienta cuando no se le pasa el hiscore.dat.
    """
    candidatas = []
    for st in raiz.findall("structure"):
        f = st.get("file", ".hi")
        if fuente and f not in (fuente, ".hi" if fuente == "hi" else fuente):
            continue
        chk = st.find("check")
        tam = None
        if chk is not None and chk.find("size") is not None:
            tam = _entero(chk.find("size").text)
        candidatas.append((st, tam))
    exactas = [st for st, t in candidatas if t == len(datos)]
    if exactas:
        return exactas[0]
    sin_tam = [st for st, t in candidatas if t is None]
    if sin_tam:
        return sin_tam[0]
    return candidatas[0][0] if candidatas else None


def resolver(ruta_xml, saltos=8):
    """Sigue las redirecciones <sameas id="otro"/> hasta el XML de verdad.

    NO es un caso raro: 2322 de los 3102 XML son redirecciones. Los clones y
    las variantes de un mismo juego comparten estructura y se apuntan al
    original (rbtapper -> tapper -> journey). Sin seguirlas se pierde la mayor
    parte de la base, y encima en silencio: el fichero existe y parece vacio.
    """
    visto = set()
    while saltos > 0:
        if not os.path.exists(ruta_xml):
            raise NoSeSabe(f"no existe {os.path.basename(ruta_xml)}")
        try:
            raiz = ET.parse(ruta_xml).getroot()
        except ET.ParseError as e:
            raise NoSeSabe(f"XML ilegible: {e}")
        sa = raiz.find("sameas")
        if sa is None or not sa.get("id"):
            return ruta_xml, raiz
        destino = sa.get("id")
        if destino in visto:
            raise NoSeSabe(f"redirecciones en bucle en {destino}")
        visto.add(destino)
        ruta_xml = os.path.join(os.path.dirname(ruta_xml), destino + ".xml")
        saltos -= 1
    raise NoSeSabe("demasiadas redirecciones seguidas")


def descifrar_con_xml(ruta_xml, datos, fuente=None):
    """Devuelve (filas, sueltos). Lanza NoSeSabe si el XML pide algo no cubierto."""
    ruta_xml, raiz = resolver(ruta_xml)
    if raiz.find("structure") is None:
        raise NoSeSabe("ese juego aun no tiene estructura descrita")

    st = _elegir_estructura(raiz, datos, fuente)
    if st is None:
        raise NoSeSabe(f"no hay estructura para la fuente {fuente}")
    filas, sueltos = [], {}
    _recorrer(st, datos, 0, _charsets(raiz), filas, sueltos)
    return filas, sueltos


def _formatos(raiz):
    """<format id="*10"><multiply>10</multiply></format>

    Sin esto las puntuaciones salen divididas por diez en muchos juegos: la
    placa guarda el numero sin el ultimo cero y el XML lo repone al presentar.
    Es exactamente el mismo x10 que yo habia tenido que deducir a mano en
    arkanoid, commando, mappy y kungfum -- ellos ya lo tenian escrito.
    """
    r = {}
    # iter() y no findall(): en algunos XML los <format> cuelgan de <output> y
    # no de la raiz. Buscando solo en la raiz salian vacios y las puntuaciones
    # se quedaban sin su x10 sin dar ningun error.
    for f in raiz.iter("format"):
        mult, suma = 1, 0
        for op in f:
            if op.tag == "multiply":
                mult = _entero(op.text, 1)
            elif op.tag == "add":
                suma = _entero(op.text, 0)
        r[f.get("id", "")] = (mult, suma)
    return r


def _columnas(raiz):
    """Que campos son de verdad la tabla, y con que formato se presentan.

    Importa mas de lo que parece: muchos XML guardan el mismo dato dos veces
    (SCORE y SCORE LONG) y solo uno es el bueno. La seccion <output> es la que
    lo dice, y los marcados display="debug" son los que NO hay que usar.
    """
    cols = []
    out = raiz.find("output")
    if out is None:
        return cols
    for tabla in out.findall("table"):
        for c in tabla.findall("column"):
            if c.get("display") == "debug":
                continue
            cols.append((c.get("id", ""), c.get("format", "")))
    return cols


def puntuaciones(ruta_xml, datos, fuente=None):
    """Normaliza a la forma que usa puntajes.py: puesto, puntos, nombre."""
    filas, sueltos = descifrar_con_xml(ruta_xml, datos, fuente)
    ruta_xml, raiz = resolver(ruta_xml)   # los <format> viven en el XML final
    fmts = _formatos(raiz)
    cols = _columnas(raiz)

    def op_implicita(f):
        """'*10' y '+1' son operaciones implicitas: el id ES la operacion.

        706 de los 3102 XML referencian un formato que no definen en ninguna
        parte, asi que no es un descuido suyo sino parte del formato. Sin esto
        commando salia a 5000 en vez de 50000 y sin dar ningun error.
        """
        m = re.fullmatch(r"([*+/-])(\d+)", f or "")
        if not m:
            return None
        signo, n = m.group(1), int(m.group(2))
        return {"*": (n, 0), "+": (1, n), "-": (1, -n)}.get(signo)

    def aplica(ident, valor):
        for cid, f in cols:
            if cid != ident:
                continue
            par = fmts.get(f) or op_implicita(f)
            if par:
                mult, suma = par
                return valor * mult + suma
        return valor

    # El id de la puntuacion sale de <output>, no de adivinar: asi se descarta
    # el gemelo marcado como debug.
    ids_col = [c for c, _ in cols]
    id_punt = next((c for c in ids_col if "SCORE" in c.upper()), None)
    id_nom = next((c for c in ids_col
                   if "NAME" in c.upper() or "INITIAL" in c.upper()), None)

    salida = []
    for i, f in enumerate(filas, 1):
        if id_punt and id_punt in f:
            punt = f[id_punt]
        else:
            punt = next((v for k, v in f.items()
                         if "SCORE" in k.upper() and isinstance(v, int)
                         and "LONG" not in k.upper()), None)
        if not isinstance(punt, int):
            continue
        punt = aplica(id_punt or "", punt)
        nom = f.get(id_nom) if id_nom else None
        if nom is None:
            nom = next((v for k, v in f.items()
                        if ("NAME" in k.upper() or "INITIAL" in k.upper())
                        and isinstance(v, str)), None)
        fila = {"puesto": i, "puntos": punt}
        if nom is not None:
            fila["nombre"] = nom
        salida.append(fila)
    return salida, sueltos


def buscar_db(rutas=()):
    """Donde estan los XML. Se prueban los sitios habituales."""
    for c in list(rutas) + [
            os.environ.get("HI2TXT_DB", ""),
            os.path.expanduser("~/hi2txt-xml/src/main/db"),
            os.path.expanduser("~/.mame/hi2txt/db"),
            "/usr/share/hi2txt/db"]:
        if c and os.path.isdir(c):
            return c
    return None


def fuentes_declaradas(ruta_xml):
    """Que ficheros sabe leer ese XML: ".hi", "nvram", "saveram", "x2212"...

    Importa porque MAME no llama "nvram" a todo: los NeoGeo guardan en
    'saveram', Star Wars en 'x2212' y Gauntlet en 'eeprom', todos dentro de
    ~/.mame/nvram/<juego>/. Buscando solo un fichero llamado 'nvram' se
    quedaban fuera 10 juegos que si tenian sus datos escritos.
    """
    try:
        _, raiz = resolver(ruta_xml)
    except NoSeSabe:
        return []
    return [st.get("file", ".hi") for st in raiz.findall("structure")]
