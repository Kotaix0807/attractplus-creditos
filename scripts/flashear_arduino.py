#!/usr/bin/env python3
"""Flashea el Arduino de la cabina DESDE AQUI, por el salto SSH, sin tocar la placa.

Compila arduino/Arcade.ino en ESTE equipo (hp-envy ya tiene arduino-cli + el core
AVR) y sube solo el .hex (~40 KB). En la cabina no hace falta el toolchain entero:
basta 'avrdude' (instalalo una vez con:  pacman -S avrdude).

Clave: el puerto /dev/ttyUSB0 lo tiene abierto el demonio del monedero, y flashear
resetea la placa, asi que se PARA monedero.service, se flashea, y se REARRANCA
siempre (incluso si avrdude falla). La cuenta de creditos no depende del demonio.

Uso:   python3 scripts/flashear_arduino.py            # flashea arduino/Arcade.ino
       python3 scripts/flashear_arduino.py otro.ino   # flashea otro sketch
"""
import os
import subprocess
import sys
import tempfile

from cabina_conn import AQUI, scp, correr

FQBN = "arduino:avr:uno"            # placa de la cabina (clon CH340)
PUERTO = "/dev/ttyUSB0"            # donde la ve la cabina (root:uucp, arcade esta en uucp)
BAUD = "115200"                    # bootloader del Uno (optiboot). Clon viejo: 57600
UID = "1000"                       # uid de 'arcade' en la cabina, para systemctl --user

ino = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.path.join(AQUI, "arduino", "Arcade.ino")
if not os.path.isfile(ino):
    sys.exit("No existe el sketch: %s" % ino)

# arduino-cli exige que el .ino este en una carpeta con su mismo nombre; lo montamos.
tmp = tempfile.mkdtemp(prefix="flash_arduino_")
nombre = os.path.splitext(os.path.basename(ino))[0]
sketch = os.path.join(tmp, nombre)
os.mkdir(sketch)
subprocess.check_call(["cp", ino, os.path.join(sketch, nombre + ".ino")])

print("Compilando %s (%s) ..." % (os.path.basename(ino), FQBN))
salida = os.path.join(tmp, "hex")
r = subprocess.run(["arduino-cli", "compile", "--fqbn", FQBN, "--output-dir", salida, sketch])
if r.returncode != 0:
    sys.exit("Fallo la compilacion local (arduino-cli).")
hex_local = os.path.join(salida, nombre + ".ino.hex")
if not os.path.isfile(hex_local):
    sys.exit("No se genero el .hex: %s" % hex_local)

print("Subiendo el .hex a la cabina ...")
scp(hex_local, "/tmp/flash_arduino.hex")

# Para el demonio, flashea, y REARRANCA pase lo que pase. El ultimo comando ([ rc ])
# fija el codigo de salida segun avrdude, y el demonio ya volvio a arrancar antes.
print("Parando monedero, flasheando y rearrancando ...")
codigo, out = correr(
    "export XDG_RUNTIME_DIR=/run/user/%s; "
    "systemctl --user stop monedero.service; sleep 1; "
    "avrdude -q -patmega328p -carduino -P%s -b%s -D -Uflash:w:/tmp/flash_arduino.hex:i 2>&1; "
    "rc=$?; "
    "systemctl --user start monedero.service; "
    "rm -f /tmp/flash_arduino.hex; "
    "[ $rc -eq 0 ]" % (UID, PUERTO, BAUD))
print(out.strip())
if codigo == 0:
    print("OK: Arduino flasheado y monedero.service de nuevo en marcha.")
else:
    sys.exit("avrdude fallo (codigo %d). El demonio se rearranco igualmente. "
             "Si son errores de sincronizacion, prueba BAUD=57600 en este script." % codigo)
