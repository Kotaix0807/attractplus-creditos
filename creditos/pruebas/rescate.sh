#!/bin/bash
# Prueba de extremo a extremo: el juego cambia su tabla -> el plugin hiscore
# escribe el .hi -> puntajes.py lo lee y lo descifra.
S="$1"; shift
MAME=~/Dev/arcade/groovymame_src/mame
CRED=/home/eloy/Dev/arcade/attractplus/creditos
rm -rf "$S/e2e"; mkdir -p "$S/e2e/hi" "$S/e2e/cfg" "$S/e2e/nv"
for j in "$@"; do
  espec=$(python3 - "$j" <<'PY'
import sys, os
sys.path.insert(0,'/home/eloy/Dev/arcade/attractplus/creditos')
import puntajes as pj
b=pj.leer_hiscore_dat(pj.ruta_hiscore_dat()).get(sys.argv[1],[])
print(';'.join(f"{c},{e},{d:x},{l:x}" for c,e,d,l in b))
PY
)
  [ -z "$espec" ] && { echo "$j: sin bloque en hiscore.dat"; continue; }
  salida=$(cd ~/Dev/arcade/groovymame_src && GA_D_BLOQUES="$espec" GA_D_FRAME=1800 \
    ./mame "$j" -rompath /usr/share/games/mame/roms -video none -sound none \
    -nothrottle -noswitchres -seconds_to_run 45 -skip_gameinfo \
    -plugin hiscore -pluginspath ~/Dev/arcade/groovymame_src/plugins \
    -homepath "$S/e2e" -cfg_directory "$S/e2e/cfg" -nvram_directory "$S/e2e/nv" \
    -autoboot_script "$S/rescate.lua" -autoboot_delay 0 2>&1)
  despues=$(echo "$salida" | grep -o 'despues=[0-9a-f]*' | cut -d= -f2)
  hi="$S/e2e/hiscore/$j.hi"
  if [ -f "$hi" ]; then
     leido=$(xxd -p "$hi" | tr -d '\n')
     if [ "$leido" = "$despues" ]; then est="OK"; else est="DIFIERE"; fi
  else est="SIN .hi"; fi
  echo "$j|$est|${despues:0:24}|$(basename "$hi")"
done
