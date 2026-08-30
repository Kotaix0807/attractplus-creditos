#!/bin/bash
# Prueba del importador de la coleccion de cheats de MAME.
set -u
AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMP="$AQUI/../importar_cheats.py"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fallos=0

comprobar() { if [ "$2" = "1" ]; then echo "  ok    $1"; else echo "  FALLO $1  ($3)"; fallos=$((fallos+1)); fi; }

mkdir -p "$T/xml"
cat > "$T/xml/galaga.xml" <<'XML'
<?xml version="1.0"?>
<mamecheat version="1">
  <cheat desc="Infinite Lives"><script state="run"><action>maincpu.pb@8320=03</action></script></cheat>
  <cheat desc="Infinite Credits"><script state="run"><action>maincpu.pb@9A12=63</action></script></cheat>
</mamecheat>
XML
cat > "$T/xml/mrdo.xml" <<'XML'
<?xml version="1.0"?>
<mamecheat version="1">
  <cheat desc="Coin Counter Freeze"><script state="run"><action>maincpu.pb@E000=00</action></script></cheat>
  <cheat desc="Credits"><script state="run"><action>maincpu.pb@E015=09</action></script></cheat>
</mamecheat>
XML
cat > "$T/xml/roto.xml" <<'XML'
<mamecheat esto no es xml valido
XML

printf 'pacman @:maincpu,program,4e6e\n' > "$T/creditos.dat"
"$IMP" "$T/xml" --salida "$T/creditos.dat" > "$T/salida.txt" 2>&1

comprobar "saca la direccion de los creditos" \
	"$(grep -q 'galaga @:maincpu,program,9a12' "$T/creditos.dat" && echo 1 || echo 0)" "$(cat "$T/creditos.dat")"
comprobar "ignora los cheats de vidas" \
	"$(grep -q '8320' "$T/creditos.dat" && echo 0 || echo 1)" "colo un cheat de vidas"
comprobar "ignora el contador de monedas" \
	"$(grep -q 'e000' "$T/creditos.dat" && echo 0 || echo 1)" "colo el coin counter"
comprobar "coge el cheat llamado solo 'Credits'" \
	"$(grep -q 'mrdo @:maincpu,program,e015' "$T/creditos.dat" && echo 1 || echo 0)" "falta mrdo"
comprobar "no pisa lo ya comprobado" \
	"$(grep -q 'pacman @:maincpu,program,4e6e' "$T/creditos.dat" && echo 1 || echo 0)" "piso pacman"
comprobar "marca lo importado" \
	"$(grep -q 'galaga.*# (cheat)' "$T/creditos.dat" && echo 1 || echo 0)" "sin marca"
comprobar "un xml roto no lo tumba" \
	"$(grep -q 'ficheros mirados' "$T/salida.txt" && echo 1 || echo 0)" "$(cat "$T/salida.txt")"

echo "# fallos=$fallos"
exit $(( fallos > 0 ))
