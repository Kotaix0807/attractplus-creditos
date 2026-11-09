#!/usr/bin/env python3
"""Sube la carpeta minijuegos/ ENTERA a la cabina (por el salto SSH) y la
recompila alli.

La conexion (salto SSH, contrasenas, scp) vive en scripts/cabina_conn.py; las
credenciales se leen de ~/.cabina_deploy.env (ver ese modulo).

Uso:   python3 scripts/subir_cabina.py
"""
import os
import subprocess
import tempfile

from cabina_conn import AQUI, CAB_HOST, REPO, scp, correr

print("Empaquetando minijuegos/ ...")
tar = tempfile.mktemp(suffix=".tgz")
subprocess.check_call(["tar", "czf", tar, "-C", AQUI,
                       "--exclude=minijuegos/minijuegos", "--exclude=minijuegos/*.o",
                       "minijuegos"])

print("Subiendo a %s ..." % CAB_HOST)
scp(tar, "/tmp/minijuegos_subir.tgz")
os.remove(tar)

print("Desempaquetando y recompilando en la cabina ...")
codigo, salida = correr(
    "cd %s && tar xzf /tmp/minijuegos_subir.tgz && rm -f /tmp/minijuegos_subir.tgz "
    "&& make -C minijuegos 2>&1 | tail -2" % REPO)
print(salida.strip())
if codigo == 0:
    print("OK: minijuegos/ subida y recompilada.")
else:
    raise SystemExit("Fallo al recompilar en la cabina (codigo %d)." % codigo)
