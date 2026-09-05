#!/usr/bin/env python3
"""Saca direcciones de creditos de la coleccion de cheats de MAME.

La coleccion de Pugsy (mamecheat.co.uk) trae, para miles de juegos, un cheat
"Infinite Credits" que apunta justo a donde el juego guarda sus creditos:

    <cheat desc="Infinite Credits">
      <script state="run">
        <action>maincpu.pb@4E6E=09</action>

De ahi se saca "pacman @:maincpu,program,4e6e", que es lo que necesita
creditos.dat.

Uso:
    ./importar_cheats.py cheat.7z
    ./importar_cheats.py cheat.zip
    ./importar_cheats.py carpeta_con_xmls/
    ./importar_cheats.py cheat.zip --salida creditos.dat

Las lineas que ya existan en creditos.dat NO se tocan: las que encuentra
buscar_creditos.sh estan comprobadas ejecutando el juego, asi que mandan sobre
las importadas.

AVISO: no todos los "Infinite Credits" sirven. Algunos parchean el codigo del
juego en vez de escribir el contador, y esa direccion no vale para leer nada.
Por eso lo importado se marca como (cheat) en el fichero: si un juego se
comporta raro, borra su linea.
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
import zipfile

# maincpu.pb@4E6E=09   ->  cpu, ancho, direccion
ACCION = re.compile(r'^\s*([\w:.]+)\.(p[bwdq])@([0-9A-Fa-f]+)\s*=', re.M)

# Nos interesan los cheats de creditos, no los de vidas o monedas de la partida
INTERESA = re.compile(r'\bcredit', re.I)
DESCARTA = re.compile(r'\b(coin\s*counter|no\s*credit|credit\s*to\s*continue)\b', re.I)


def de_xml(texto, nombre_fichero):
    """Devuelve (juego, cpu, direccion) o None."""
    try:
        raiz = ET.fromstring(texto)
    except ET.ParseError:
        return None

    juego = os.path.splitext(os.path.basename(nombre_fichero))[0]

    for cheat in raiz.iter('cheat'):
        desc = cheat.get('desc') or ''
        if not INTERESA.search(desc) or DESCARTA.search(desc):
            continue

        # Solo el script que corre de continuo: el que mantiene el contador
        for script in cheat.iter('script'):
            if script.get('state') not in (None, 'run'):
                continue
            for accion in script.iter('action'):
                m = ACCION.match(accion.text or '')
                if not m:
                    continue
                cpu, _ancho, direccion = m.groups()
                cpu = cpu if cpu.startswith(':') else ':' + cpu
                return juego, cpu, direccion.lower().lstrip('0') or '0'

    return None


def recorrer(origen):
    """Va soltando pares (nombre, contenido) de xml."""
    if os.path.isdir(origen):
        for raiz, _dirs, ficheros in os.walk(origen):
            for f in sorted(ficheros):
                if f.lower().endswith('.xml'):
                    ruta = os.path.join(raiz, f)
                    with open(ruta, 'rb') as fh:
                        yield f, fh.read().decode('utf-8', 'replace')

    elif zipfile.is_zipfile(origen):
        with zipfile.ZipFile(origen) as z:
            for nombre in sorted(z.namelist()):
                if nombre.lower().endswith('.xml'):
                    yield os.path.basename(nombre), \
                        z.read(nombre).decode('utf-8', 'replace')

    elif origen.lower().endswith('.xml'):
        with open(origen, 'rb') as fh:
            yield os.path.basename(origen), fh.read().decode('utf-8', 'replace')

    elif origen.lower().endswith('.7z'):
        # La coleccion de Pugsy viene en 7z, con un xml por juego. Se saca a un
        # temporal y se recorre como una carpeta cualquiera.
        sietez = descompresor_7z()
        if not sietez:
            sys.exit('hace falta 7z para abrir %s.\n%s' % (origen, COMO_INSTALAR_7Z))

        tmp = tempfile.mkdtemp(prefix='cheats-')
        try:
            r = subprocess.run([sietez, 'x', '-y', '-o' + tmp, origen],
                               stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
            if r.returncode != 0:
                sys.exit('7z fallo: %s' % r.stderr.decode('utf-8', 'replace')[:200])
            yield from recorrer(tmp)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)

    else:
        sys.exit('no se que hacer con %s (espero .xml, .zip, .7z o una carpeta)' % origen)


# El binario de 7-Zip se llama distinto en cada distro: p7zip trae "7z" y
# "7za", y el 7zip oficial (el que empaqueta Arch y Fedora) trae "7zz". Se usa
# el que haya en vez de suponer uno.
SIETEZ = ('7z', '7za', '7zz', '7zr')

COMO_INSTALAR_7Z = (
    'Instalalo con lo que use tu distro:\n'
    '  Debian/Ubuntu   sudo apt install p7zip-full\n'
    '  Arch            sudo pacman -S 7zip\n'
    '  Fedora          sudo dnf install p7zip\n'
    '  openSUSE        sudo zypper install 7zip'
)


def descompresor_7z():
    """El primer binario de 7-Zip que exista, o None."""
    for nombre in SIETEZ:
        ruta = shutil.which(nombre)
        if ruta:
            return ruta
    return None


def leer_existentes(ruta):
    juegos = {}
    if not os.path.exists(ruta):
        return juegos
    with open(ruta) as fh:
        for linea in fh:
            m = re.match(r'^\s*([\w\-]+)\s+@', linea)
            if m:
                juegos[m.group(1)] = linea.rstrip('\n')
    return juegos


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('origen', help='cheat.zip, un .xml o una carpeta con xmls')
    aqui = os.path.dirname(os.path.abspath(__file__))
    p.add_argument('--salida', default=os.path.join(aqui, 'creditos.dat'))
    p.add_argument('--solo', nargs='*', metavar='JUEGO',
                   help='importar solo estos juegos')
    args = p.parse_args()

    ya = leer_existentes(args.salida)
    nuevas, saltados, mirados = {}, 0, 0

    for nombre, texto in recorrer(args.origen):
        mirados += 1
        r = de_xml(texto, nombre)
        if not r:
            continue

        juego, cpu, direccion = r
        if args.solo and juego not in args.solo:
            continue
        if juego in ya:
            saltados += 1          # la comprobada manda
            continue

        nuevas[juego] = '%s @%s,program,%s   # (cheat)' % (juego, cpu, direccion)

    if not nuevas:
        print('# nada nuevo que anadir (%d ficheros mirados, %d ya estaban)'
              % (mirados, saltados))
        return

    todas = dict(ya)
    todas.update(nuevas)

    with open(args.salida, 'w') as fh:
        fh.write('# creditos.dat - donde guarda cada juego su contador de creditos.\n')
        fh.write('# Las lineas sin marca las encontro buscar_creditos.sh ejecutando el\n')
        fh.write('# juego; las marcadas (cheat) vienen de la coleccion de cheats de MAME\n')
        fh.write('# y NO estan comprobadas: si un juego va raro, borra su linea.\n')
        for juego in sorted(todas):
            fh.write(todas[juego] + '\n')

    print('# %d ficheros mirados, %d anadidos, %d ya estaban -> %s'
          % (mirados, len(nuevas), saltados, args.salida))


if __name__ == '__main__':
    main()
