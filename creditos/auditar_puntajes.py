#!/usr/bin/env python3
"""Compara lo que descifra puntajes.py con la tabla de fabrica que hi2txt
trae ya descifrada. Es una referencia INDEPENDIENTE: si coinciden, la receta
es correcta; si no, hay algo que mirar."""
import json, os, sys, re
import xml.etree.ElementTree as ET
# Las rutas salen de donde esta el script y del entorno, no de una copia
# concreta del repo: asi la auditoria corre igual en la cabina y sobre un
# volcado suyo traido a otra maquina.
#   HI2TXT_DB / --hi2txt   la base de estructuras (su hermana db_defaults es
#                          la referencia contra la que se compara)
#   NVRAM_PATH             carpeta con la memoria persistente
#   HI_PATH                carpeta de los .hi
AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
os.chdir(AQUI)
import importlib.util
spec = importlib.util.spec_from_file_location("pj", os.path.join(AQUI, "puntajes.py"))
pj = importlib.util.module_from_spec(spec); spec.loader.exec_module(pj)
import hi2txt
_db = None
if "--hi2txt" in sys.argv:
    _db = sys.argv[sys.argv.index("--hi2txt") + 1]
_db = _db or os.environ.get("HI2TXT_DB") or hi2txt.buscar_db()
pj.DB_HI2TXT = _db
DEF = os.path.join(os.path.dirname(_db), "db_defaults") if _db else ""
if os.environ.get("NVRAM_PATH"):
    pj.DIR_NVRAM = os.path.expanduser(os.environ["NVRAM_PATH"])
bloques = pj.leer_hiscore_dat(pj.ruta_hiscore_dat())
recetas = pj.leer_puntajes_dat("puntajes.dat")
fabrica = json.load(open("puntajes_fabrica.json")); pj.FABRICA = fabrica
dir_hi = os.environ.get("HI_PATH") or pj.ruta_hi()
# El universo son los juegos con datos en cualquiera de los tres sitios, la
# misma regla que usa puntajes.py --listar.
juegos = sorted({f[:-3] for f in os.listdir(dir_hi) if f.endswith(".hi")}
                | set(fabrica)
                | ({d for d in os.listdir(pj.DIR_NVRAM)
                    if os.path.isdir(os.path.join(pj.DIR_NVRAM, d))}
                   if os.path.isdir(pj.DIR_NVRAM) else set()))
# Jugados por Eloy o por mis pruebas: su tabla YA NO es la de fabrica.
TOCADOS = {"pacman","mspacman","asteroid","samsho3","fatfury1","samsho2",
           "btoads","gauntlet","gauntlet2p","samsho","strhoop","doubledr","1943"}

def referencia(j):
    f = f"{DEF}/{j}.xml"
    if not os.path.exists(f): return None
    try: raiz = ET.parse(f).getroot()
    except ET.ParseError: return None
    filas = []
    for fila in raiz.iter("row"):
        celdas = [c.text or "" for c in fila.findall("cell")]
        nums = [c for c in celdas if re.fullmatch(r"\d+", c or "")]
        if len(nums) >= 2: filas.append(int(nums[1]))
        elif nums: filas.append(int(nums[0]))
    return filas or None

ok = mal = sinref = 0
problemas = []
for j in juegos:
    filas, org, aviso = pj.puntajes_de(j, bloques.get(j, []), recetas.get(j), dir_hi)
    if not filas: continue
    mios = [f["puntos"] for f in filas]
    ref = referencia(j)
    if not ref:
        sinref += 1
        continue
    n = min(len(ref), len(mios), 5)
    coincide = mios[:n] == ref[:n]
    if coincide: ok += 1
    else:
        if j in TOCADOS:
            sinref += 1   # se jugo: su tabla ya no es la de fabrica
            continue
        mal += 1
        problemas.append((j, mios[:5], ref[:5]))
print(f"COMPARADOS CON LA REFERENCIA DE hi2txt")
print(f"  coinciden        {ok}")
print(f"  NO coinciden     {mal}")
print(f"  sin referencia   {sinref}  (o su tabla ya se jugo)")
if problemas:
    print("\nA REVISAR:")
    for j, m, r in problemas:
        print(f"  {j:<11} mio {m}")
        print(f"  {'':<11} ref {r}")
