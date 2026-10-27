# El Raspberry Pi como puerta del panel

El backend del panel (`panel/servidor.py`) **se queda en la cabina**, pegado a
sus datos (lee `/proc`, `/sys`, `~/.attract` y ejecuta `sudo`/`systemctl` en
local: latencia 0). El Pi **no** es el backend; es la **puerta**: un aparato
barato y siempre encendido que:

1. saca el panel a internet con `cloudflared` (sin abrir puertos);
2. reenvía cada petición a la cabina por un cable LAN directo (`portero.py`);
3. si la cabina está apagada, lo dice con un `503` claro y la puede **encender**
   por Wake-on-LAN (`POST /api/accion/encender`).

Por qué así y no "el backend en el Pi pidiéndole datos a la cabina": mover el
cerebro lejos de sus datos **sube** la latencia (cada dato y cada acción pasaría
a viajar por red) y obliga a mantener dos programas en vez de uno. El backend se
queda donde están los datos; el Pi solo hace de puerta.

```
Cloudflare ──túnel──> cloudflared (Pi) ──> portero.py (Pi, :8080) ──cable LAN──> panel (cabina, :8808)
```

---

## Las dos topologías de internet (elige una)

El beneficio de "siempre accesible aunque la cabina esté apagada" **solo existe
si el Pi tiene internet propio**. Las dos opciones:

**A) El Pi tiene su propia salida a internet** (wifi, o un segundo ethernet a un
router). Recomendada: el Pi queda accesible aunque la cabina esté apagada, así
que el botón "Encender" funciona de verdad. El cable a la cabina es solo para el
enlace privado entre los dos.

**B) El Pi solo se conecta a la cabina** (un cable, nada más). Entonces el Pi
saldría a internet a través del 4G de la cabina (hay que compartirle la conexión
con `iptables`/NAT). Aviso: si la cabina está apagada, el Pi también se queda sin
internet, así que **no** aporta el "siempre accesible" ni el "Encender" remoto —
para eso serviría solo si alguien ya está en la misma red local. En ese caso, el
Pi aporta poco frente a dejar `cloudflared` en la cabina directamente.

Si dudas, empieza por A.

---

## El enlace por cable (igual en A y en B)

Da IP fija a los dos extremos del cable (una red aparte, p.ej. `10.55.0.0/24`):

- Cabina (su interfaz del cable): `10.55.0.2/24`
- Pi (su interfaz del cable):     `10.55.0.1/24`

En la cabina, dile al panel que escuche en esa IP (no en `127.0.0.1`), en
`~/.config/panel.conf`:

```
escucha=10.55.0.2
```

y reinicia el panel: `systemctl --user restart panel.service`. **No** pongas
`0.0.0.0` ni una IP de una LAN compartida: el panel solo tiene la clave de la app
por delante (Cloudflare Access protege la entrada pública, no este cable).

---

## Montar el portero en el Pi

```bash
git clone <repo> ~/attractplus          # o solo copia la carpeta pi/
cp ~/attractplus/pi/portero.service ~/.config/systemd/user/
# edita el .service: CABINA, CABINA_MAC y BROADCAST (ver abajo)
systemctl --user daemon-reload
systemctl --user enable --now portero.service
loginctl enable-linger "$USER"          # para que viva sin login
```

Variables del `portero.service`:

- `CABINA=10.55.0.2:8808` — la cabina por el cable.
- `CABINA_MAC=aa:bb:cc:dd:ee:ff` — la MAC de la interfaz del cable **de la
  cabina** (la que recibe el Wake-on-LAN). Sácala en la cabina con `ip link`.
- `BROADCAST=10.55.0.255` — la difusión de la red del cable, para que el magic
  packet salga por ese cable y no por el internet del Pi. Debe cuadrar con la red
  que elegiste (`10.55.0.0/24` → `10.55.0.255`).

Comprueba sin cloudflared todavía:

```bash
python3 ~/attractplus/pi/portero.py --self-check      # valida el magic packet
curl -s localhost:8080/api/puerta                     # {"cabina_online": true/false, ...}
```

---

## cloudflared en el Pi

Apunta el túnel **al portero** (`127.0.0.1:8080`), no directo a la cabina, o el
caso "apagada" y el "Encender" no funcionarían.

**Cloudflare Access es obligatorio, no opcional.** El portero escucha solo en
`127.0.0.1` (nadie de la LAN del Pi lo alcanza, solo `cloudflared`), y **no tiene
clave propia**: `POST /api/accion/encender` y `GET /api/puerta` los sirve él
directamente (la cabina puede estar apagada, así que no hay sesión que validar).
Su única barrera es Access. Sin Access, cualquiera con la URL podría encender la
cabina por Wake-on-LAN (impacto bajo: solo la prende) y ver si está encendida.
Todo lo demás pasa a la cabina, que sí pide la clave de la app.

```bash
cloudflared tunnel login
cloudflared tunnel create cabina
cloudflared tunnel route dns cabina arcade.dsds.uk
# ~/.cloudflared/config.yml :
#   tunnel: cabina
#   ingress:
#     - hostname: arcade.dsds.uk
#       service: http://127.0.0.1:8080
#     - service: http_status:404
sudo cloudflared service install           # y protege la ruta con Cloudflare Access
```

---

## Wake-on-LAN: lo que hay que comprobar en la cabina

El "Encender" solo funciona si la cabina lo soporta. Dos cosas, las dos en la
cabina:

1. **La BIOS/UEFI** tiene que permitir "Power On by PCIE/LAN" (o "Wake on LAN").
2. **La tarjeta de red** del cable tiene que tener WoL activado y que sobreviva al
   apagado:
   ```bash
   sudo ethtool <iface>            # mira "Supports Wake-on: g" y "Wake-on: g"
   sudo ethtool -s <iface> wol g   # actívalo (hazlo persistente: udev/NetworkManager)
   ```

**Aviso honesto:** muchos portátiles y casi todos los adaptadores USB-ethernet
**no** despiertan por WoL. Si la cabina es un portátil (VAIO/HP) o usa un dongle
USB, es muy posible que el "Encender" no funcione por hardware, por mucho que el
software mande el paquete. Hay que probarlo con la cabina delante; si no va, el
botón quedará, pero sin efecto, y la alternativa es un enchufe inteligente con
"restore on AC = On".

---

## Probar el conjunto sin la cabina

El simulador hace de cabina de mentira; el portero le habla igual:

```bash
# en una terminal (hace de cabina):
PUERTO=8808 python3 panel/simulador.py
# en otra (el portero):
CABINA=127.0.0.1:8808 PUERTO=8080 python3 pi/portero.py
# ahora http://localhost:8080/ pasa por el portero hasta el simulador.
# Para el simulador (Ctrl-C) y verás el 503 "apagada" y el Encender por WoL.
```
