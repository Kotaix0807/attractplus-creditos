#!/usr/bin/env python3
"""Sube la carpeta minijuegos/ ENTERA a la cabina (por el salto SSH) y la
recompila alli.

Las contrasenas NO van en el repo: se leen del entorno o de ~/.cabina_deploy.env
(fichero fuera del repo, formato CLAVE=valor):

    PI_PW=...        contrasena del salto   (ubuntu@192.168.1.120 por defecto)
    CAB_PW=...       contrasena de la cabina (arcade@10.55.0.2 por defecto)
    # opcionales:
    PI_HOST=ubuntu@192.168.1.120
    CAB_HOST=arcade@10.55.0.2
    REPO_REMOTO=/home/arcade/attractplus-creditos

Uso:   python3 scripts/subir_cabina.py
Necesita pexpect (pip install --user pexpect). La IP de la cabina cambia (4G); si
no conecta, actualiza CAB_HOST en ~/.cabina_deploy.env.
"""
import os
import re
import sys
import subprocess
import tempfile

try:
    import pexpect
except ImportError:
    sys.exit("Falta pexpect:  pip install --user pexpect")

# --- config: entorno + ~/.cabina_deploy.env (sin pisar lo ya exportado) ---
conf = os.environ.get("CABINA_ENV", os.path.expanduser("~/.cabina_deploy.env"))
if os.path.isfile(conf):
    for linea in open(conf):
        linea = linea.strip()
        if linea and not linea.startswith("#") and "=" in linea:
            k, v = linea.split("=", 1)
            os.environ.setdefault(k.strip(), v.strip())

PI_HOST  = os.environ.get("PI_HOST", "ubuntu@192.168.1.120")
CAB_HOST = os.environ.get("CAB_HOST", "arcade@10.55.0.2")
REPO     = os.environ.get("REPO_REMOTO", "/home/arcade/attractplus-creditos")
PI_PW    = os.environ.get("PI_PW")
CAB_PW   = os.environ.get("CAB_PW")
if not PI_PW or not CAB_PW:
    sys.exit("Faltan PI_PW y/o CAB_PW. Ponlos en %s (o en el entorno)." % conf)

AQUI = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# accept-new (TOFU): acepta la clave de un host NUEVO la 1a vez, pero AVISA/falla si
# la clave de un host ya conocido cambia (deteccion de MITM). No se usa 'no' porque
# desactiva esa proteccion. La cabina va por 4G con IP cambiante y auth por
# contrasena; lo ideal a futuro seria clave SSH + HostKeyAlias para fijar la clave
# aunque cambie la IP.
SSH_OPTS = "-o StrictHostKeyChecking=accept-new -o ConnectTimeout=20 -J %s" % PI_HOST

# Contesta las dos contrasenas del salto (primero el Pi, luego la cabina) hasta
# ver el patron 'hasta' (o EOF). Devuelve el indice que corto el bucle.
def responder_contrasenas(child, hasta):
    pi = re.escape(PI_HOST.split("@", 1)[1])
    cab = re.escape(CAB_HOST)
    puesto = {"pi": False}
    while True:
        i = child.expect([pi + r"'s password:",
                          r"\(" + cab + r"\).*[Pp]assword:",
                          r"[Pp]assword:",
                          hasta, pexpect.EOF, pexpect.TIMEOUT])
        if i == 0:
            child.sendline(PI_PW); puesto["pi"] = True
        elif i in (1, 2):
            # el 1 es claramente la cabina; el 2 (generico) es el Pi si aun no se mando
            child.sendline(CAB_PW if (i == 1 or puesto["pi"]) else PI_PW)
            if i == 2 and not puesto["pi"]:
                puesto["pi"] = True
        else:
            return i   # 3 = hasta, 4 = EOF, 5 = TIMEOUT

def scp(local, remoto):
    c = pexpect.spawn("scp %s %s %s:%s" % (SSH_OPTS, local, CAB_HOST, remoto),
                      encoding="utf-8", timeout=600)
    # scp no da prompt de shell: tras las contrasenas termina en EOF. El 'hasta'
    # es un centinela que NO casa nunca (un patron casable, como \Z, cortaria el
    # bucle con el buffer vacio antes de mandar las contrasenas).
    responder_contrasenas(c, r"__sin_prompt_scp__")
    c.close()
    if c.exitstatus not in (0, None):
        sys.exit("scp fallo (codigo %s)" % c.exitstatus)

def correr(cmd):
    c = pexpect.spawn("ssh %s %s" % (SSH_OPTS, CAB_HOST), encoding="utf-8", timeout=300)
    if responder_contrasenas(c, r"[\$#] ?$") != 3:
        sys.exit("no pude entrar a la cabina (revisa CAB_HOST/credenciales)")
    c.sendline("stty -echo 2>/dev/null; true")
    c.sendline(cmd + "; echo __FIN__$?")
    c.expect(r"__FIN__(\d+)")
    codigo = int(c.match.group(1))
    salida = c.before
    c.sendline("exit"); c.close()
    return codigo, salida

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
    sys.exit("Fallo al recompilar en la cabina (codigo %d)." % codigo)
