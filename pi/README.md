# El Raspberry Pi como puerta del panel

El backend del panel (`panel/servidor.py`) **se queda en la cabina**, pegado a
sus datos (lee `/proc`, `/sys`, `~/.attract` y ejecuta `sudo`/`systemctl` en
local: latencia 0). El Pi **no** es el backend; es la **puerta**: un aparato
barato y siempre encendido que:

1. es la **única entrada** al panel: nginx en el puerto 80, abierto **solo a
   Tailscale** (la red de casa recibe un 403);
2. **sirve la GUI él mismo** (desde `~/web`), así carga aunque la cabina esté
   apagada (para poder pulsar "Encender"); y reenvía solo las `/api/*` a la cabina;
3. si la cabina está apagada, lo dice con un `503` claro y la puede **encender**
   por Wake-on-LAN (`POST /api/accion/encender`).

Por qué así y no "el backend en el Pi pidiéndole datos a la cabina": mover el
cerebro lejos de sus datos **sube** la latencia (cada dato y cada acción pasaría
a viajar por red) y obliga a mantener dos programas en vez de uno. El backend se
queda donde están los datos; el Pi solo hace de puerta.

```
teléfono (Tailscale) ──> nginx (Pi, :80 y :8080, solo 100.64.0.0/10) ──> portero.py (Pi, 127.0.0.1:8081) ──cable LAN──> panel (cabina, 10.55.0.2:8808)
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
para eso serviría solo si alguien ya está en la misma red local.

Hoy es la A: el Pi sale por el wifi de casa (`192.168.1.120`).

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
`0.0.0.0` ni la IP del wifi: la cabina también está en el wifi de casa
(`192.168.1.117`) y con eso cualquiera de esa red llegaría al panel sin pasar
por Tailscale. Con el cable, solo el Pi la alcanza.

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

Comprueba el portero (en el propio Pi):

```bash
python3 ~/attractplus/pi/portero.py --self-check      # valida el magic packet
curl -s localhost:8081/api/puerta                     # {"cabina_online": true/false, ...}
```

---

## Tailscale + nginx en el Pi

Decidido por Eloy el 2026-11-22: **solo Tailscale**, sin Cloudflare. Al panel
se entra desde un aparato con la app de Tailscale y la sesión iniciada:
`http://arcade-pi/` (MagicDNS) o `http://100.92.202.44/`. Tailscale cifra el
tráfico (WireGuard), así que `http://` está bien. Cruza el CGNAT sin abrir
puertos.

La regla es que **no se pueda entrar desde ninguna otra IP**, y la cumplen dos
piezas:

- **El portero escucha en `127.0.0.1:8081`** (`ESCUCHA` y `PUERTO` en
  `portero.service`). Nadie de fuera llega a él.
- **nginx es la única puerta**, y solo deja pasar el rango de Tailscale
  (`100.64.0.0/10` y `fd7a:115c:a1e0::/48`); el resto recibe un 403. La
  configuración está en [`nginx-panel.conf`](nginx-panel.conf). Se filtra en
  nginx y no atando el puerto a la IP de Tailscale, porque esa IP no existe
  hasta que arranca `tailscaled` y un `bind` a ella fallaría en el arranque.
  nginx atiende el **80 y el 8080**: el 8080 es la dirección que el teléfono ya
  tenía guardada, y cerrarlo dejó a Eloy sin entrar («no se pudo conectar»).

Verificado el 2026-11-22 desde el portátil, que está en las dos redes:

| | resultado |
|---|---|
| `http://192.168.1.120/` (wifi de casa) | 403 |
| `http://192.168.1.120:8080/` | 403 |
| `http://192.168.1.120:8081/` (el portero) | no responde |
| `http://100.92.202.44:8080/` (Tailscale) | 200 |
| `http://192.168.1.117:8808/` (la cabina por el wifi) | no responde |
| `http://100.92.202.44/` (Tailscale) | 200 |

**El portero no tiene clave propia**: `GET /api/puerta` y
`POST /api/accion/encender` los sirve él (la cabina puede estar apagada). Su
barrera es Tailscale. Todo lo demás pasa a la cabina, que pide la clave de la app.

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

## Probar el portero sin la cabina

Basta con lanzarlo apuntando a una cabina que no responde: sirve `~/web` y para
`/api/*` contesta el 503 "apagada", con el botón Encender por WoL. (El simulador
de cabina se quitó el 2026-11-22; las páginas se prueban contra la cabina real.)

```bash
CABINA=127.0.0.1:9 PUERTO=8081 python3 pi/portero.py
```
