# El panel web de control remoto

El panel deja administrar la cabina **desde el navegador del teléfono o del PC,
desde cualquier lado y sin abrir puertos**. Corre como un servicio en la propia
cabina y sale al mundo por un túnel saliente de Cloudflare.

Este documento es, sobre todo, **el contrato de API**: la lista exacta de
mensajes que la página web (la GUI) le manda al backend. La GUI la escribe Eloy;
el backend (esta carpeta y `panel/`) lo escribe Claude. Mientras no cambie este
contrato, los dos lados avanzan por separado.

```
Teléfono/PC ──HTTPS──> Cloudflare (login) ──túnel──> cloudflared ──> panel (127.0.0.1:8808)
                                                                         │
                         GUI (HTML+CSS+JS)  ←── sirve ──┘               ├─ lee /proc, /sys, ~/.attract
                         llama a /api/... con fetch()                    └─ ejecuta acciones (sudo, systemctl)
```

**Con Raspberry Pi de puerta (ver `pi/README.md`).** El backend NO se mueve al Pi:
se queda en la cabina, pegado a sus datos (latencia 0). El Pi es solo la puerta
siempre encendida — reenvía a la cabina y, si está apagada, lo dice y la puede
encender por Wake-on-LAN:

```
Cloudflare ──túnel──> cloudflared (Pi) ──> portero (Pi) ──cable LAN──> panel (cabina, escucha=IP-del-cable)
                                             │                           lee/ejecuta en LOCAL (0 latencia)
                                             └─ cabina apagada: 503 + POST /api/accion/encender = Wake-on-LAN
```

La GUI no cambia entre los dos montajes: habla con las mismas rutas. Lo único que
el Pi añade al contrato es `GET /api/puerta` y `POST /api/accion/encender`.

---

## Para Eloy: cómo construir la GUI (lo más simple posible)

**La idea en una frase.** Tu página y mi backend son dos programas que se hablan
por mensajes HTTP en formato JSON. Tú haces la **cara** (lo que se ve y los
botones); yo hago el **cerebro** (los datos y las acciones). El idioma entre los
dos es la lista de `/api/...` de más abajo.

**Qué aprender, y en qué orden:**

1. **HTML** — el esqueleto (botones, textos, recuadros). 1-2 días.
2. **CSS** — cómo se ve. Atajo: enlaza **Pico.css** (CSS "sin clases") y tu HTML
   se ve bien y responsivo casi sin escribir CSS. 2-4 días.
3. **JavaScript** — la parte que importa: `fetch()` para llamar a la API y poner
   la respuesta en pantalla, y reaccionar a los clics. ~1 semana del 20% útil.

Python **no** está en tu lista: ese es el backend, lo hago yo.

**El único patrón que de verdad necesitas** (todo lo demás es repetir esto):

```javascript
// 1) Pedir datos y mostrarlos
async function refrescar() {
  const r = await fetch('/api/estado');
  const d = await r.json();
  document.getElementById('temp').textContent = d.temperatura_c + ' °C';
  document.getElementById('juego').textContent =
    d.juego_actual ? d.juego_actual.titulo : 'en el menú';
}
setInterval(refrescar, 2000);   // cada 2 segundos
refrescar();

// 2) Un botón que ejecuta una acción
document.getElementById('btn-reiniciar').addEventListener('click', async () => {
  if (!confirm('¿Reiniciar la cabina?')) return;
  await fetch('/api/accion/reiniciar', {
    method: 'POST',
    headers: { 'X-CSRF-Token': TOKEN },   // TOKEN te lo da /api/login
  });
});
```

**Dónde van tus archivos.** La GUI vive en `pi/web/` (index, tester, puntajes,
pantalla, compilación) y la sirve la Raspberry Pi con `pi/portero.py`, que reenvía
cada `/api/*` a la cabina. Para cambiarla se edita ahí y se copia a `~/web` de la
Pi. (El simulador y la copia vieja de `panel/static/` se quitaron el 2026-11-22:
la GUI se prueba contra la cabina de verdad.)

**Recursos:** javascript.info (el mejor para JS), freeCodeCamp ("Responsive Web
Design"), MDN (para consultar).

---

## Autenticación

Dos capas: **Cloudflare Access** delante (login por correo/Google antes de llegar
a la cabina) y una **sesión con contraseña** en el propio panel.

- `POST /api/login` — body `{"usuario": "...", "clave": "...", "recordar": true}`.
  Si acierta: pone cookie de sesión y devuelve `{"ok": true, "csrf": "<token>"}`.
  Si falla: `401`.
  - `usuario` es opcional: si en `panel.conf` no hay `usuario`, no se exige (basta
    la clave; la primera barrera es Cloudflare Access). Si lo hay, tiene que coincidir.
  - `recordar` = "mantener sesión iniciada": `true` deja la sesión viva ~30 días
    aunque se cierre el navegador; `false`/ausente, la sesión caduca al cerrarlo.
- `POST /api/logout` — cierra la sesión.
- `GET /api/sesion` — `{"autenticado": true|false}`.

**Todas las rutas `POST` que cambian estado exigen** la cookie de sesión y la
cabecera `X-CSRF-Token` con el token que dio el login. Sin eso: `403`.
Las rutas `GET` de solo lectura solo exigen la sesión.

---

## Lectura de estado (GET)

### `GET /api/estado`
El panel entero de un vistazo.
```json
{
  "hora": 1760000000,
  "uptime_seg": 48213,
  "cpu": { "uso_pct": 23, "nucleos": 4, "carga": [0.4, 0.5, 0.6] },
  "temperatura_c": 54, "temperatura_max_c": 90,
  "ram": { "usada_mb": 1800, "total_mb": 3800, "pct": 47 },
  "disco": { "usado_gb": 61, "total_gb": 1800, "libre_gb": 1739, "pct": 3 },
  "juego_actual": {
    "rom": "pacman", "titulo": "Pac-Man", "corriendo": true,
    "segundos": 312, "creditos_dentro": 2
  },
  "red": { "ip_publica": "190.x.x.x", "tunel": "activo" },
  "servicios": {
    "panel": "activo", "monedero": "activo", "pantalla-auto": "activo",
    "cloudflared": "activo", "frontend": "activo", "x": "activo"
  },
  "arduino": { "conectado": true, "puerto": "/dev/ttyUSB0",
               "rele": "on", "ultimo_error": null },
  "versiones": { "mame": "0.264", "attractplus": "3.2.3" },
  "juegos_total": 104,
  "commit": { "hash": "cdf0107", "fecha": "2026-10-02", "mensaje": "..." }
}
```
`juego_actual` es `null` si no hay partida. `creditos_dentro` es `null` si el
juego no tiene dirección de créditos conocida. Cada servicio es
`"activo" | "inactivo" | "desconocido"`.

### `GET /api/volumen`
Nivel actual (0-100) para arrancar el slider donde toca. `{"ok": true, "nivel": 45}`
(`nivel` es `null` si no se pudo leer).

### `GET /api/leds/brillo`
Brillo global de los LEDs del panel (0-255), para arrancar el slider donde toca:
`{"brillo": 255}`. Escala TODO lo que corra en el Arduino (animaciones, botones de
MAME, minijuego). Sin fichero = 255 (máximo). Lo aplica `moneyBank.py` mandando
`L<n>` a la placa.

### `GET /api/puerta` (solo con Pi)
Lo contesta el portero del Pi, no la cabina. Dice si la cabina está viva y si hay
Wake-on-LAN disponible: `{"cabina_online": true, "wol": true}`. Úsalo en la pantalla
de login para, si `cabina_online` es `false`, mostrar el botón "Encender". Sin Pi,
esta ruta no existe (la GUI debe tratar su ausencia como "cabina online").

Además, cuando hay Pi y la cabina está apagada, **cualquier** ruta de la cabina
responde `503` con `{"ok": false, "cabina_online": false, "error": "la cabina
esta apagada"}`. La GUI debe leer ese `503` como "apagada" y ofrecer Encender.

### `GET /api/botones` (SSE)
Para la pantalla "Test botones". Flujo de eventos: cada pulsación de un **mando**
(joystick/gamepad) llega como un `data:` con
`{"dispositivo": "Xinmotek Dual Controller", "codigo": 307, "pulsado": true}`
(`pulsado:false` al soltar). El **teclado se excluye a propósito** (leerlo sería
registrar lo que se teclea en la cabina), así que no se testea por aquí.
También puede mandar `{"latido": true}` (silencio, mantiene viva la conexión),
`{"fin": "..."}` (se acabó el límite de tiempo de la sesión; vuelve a abrir para
seguir) y `{"error": "..."}` si no hay mandos legibles (falta el grupo `input`).

### `GET /api/puntajes`
Puntajes más altos (de `~/.attract/puntajes.json`, sin las filas de fábrica).
```json
{ "generado": 1760000000,
  "juegos": {
    "pacman":  { "titulo": "Pac-Man",
      "puestos": [ { "puesto": 1, "puntos": 48800, "nombre": null, "confirmado": true } ] }
  } }
```

### `GET /api/masjugados?orden=partidas|tiempo&limite=20`
De las estadísticas nativas de AM+ (`~/.attract/stats/groovymame/*.stat`).
```json
[ { "rom": "pacman", "titulo": "Pac-Man",
    "partidas": 142, "tiempo_seg": 51230, "ultima": 1759900000 } ]
```

## Acciones (POST, exigen `X-CSRF-Token`)

Todas devuelven `{"ok": true}` o `{"ok": false, "error": "..."}`, y quedan
registradas en `~/.attract/panel_auditoria.log`.

| Ruta | Body | Qué hace |
|---|---|---|
| `POST /api/accion/reiniciar` | — | `sudo systemctl reboot` |
| `POST /api/accion/apagar` | — | `sudo systemctl poweroff` (apagado total; en el VAIO **no** se puede encender luego por WoL) |
| `POST /api/accion/suspender` | — | `sudo systemctl suspend` (S3); de aquí **sí** se enciende por WoL (con el cargador puesto) — es el "apagar" útil para remoto |
| `POST /api/frontend/reiniciar` | — | `pkill -x attractplus` (el wrapper lo relanza) |
| `POST /api/monedero/reiniciar` | — | `systemctl --user restart monedero.service` (resetea serie + relé) |
| `POST /api/juego/salir` | — | sale limpio del juego en curso (orden a `creditos.lua`) |
| `POST /api/juego/menu` | — | abre/cierra el menú de MAME (manda TAB por XTEST a `:0`); solo con un juego en marcha, se navega con los controles de la cabina |
| `POST /api/frontend/menu` | — | abre el menú de configuración de Attract-Mode (también TAB, pero gated a que NO haya juego: al frente está AM+); para configurar emuladores, controles, etc. |
| `POST /api/creditos` | `{"n": 1}` | inyecta N créditos en la partida en curso |
| `POST /api/volumen` | `{"nivel": 80}` | 0-100 (`amixer`) |
| `POST /api/leds/brillo` | `{"brillo": 128}` | 0-255; brillo global de los LEDs, escala cualquier animación/juego en marcha |
| `GET /api/tarifa-global` | — | tarifa global para TODOS los juegos: `{"modo":"freeplay"\|"pesos"\|"defecto","pesos":N?}` |
| `POST /api/tarifa-global` | `{"valor":"freeplay"\|200\|"defecto"}` | fija/quita la tarifa global (la aplica `creditos.lua` al lanzar: free play por DIP + créditos infinitos por RAM, o N monedas/crédito) |
| `POST /api/accion/encender` | — | (solo con Pi) enciende la cabina por Wake-on-LAN. Lo sirve el portero del Pi, **sin** CSRF de la app (la cabina puede estar apagada; la barrera es Cloudflare Access). Si ya está encendida, `{"ok": true, "nota": "..."}` |

Además, `POST /api/sonido/prueba` (`{"canal": "izquierda|derecha|ambos"}`) da un
tono de prueba, `POST /api/arduino/reiniciar` reinicia la placa y `POST /api/pulsar`
(`{"control": "..."}`) es el joystick virtual del tester.

**Rutas quitadas el 2026-11-22** (ninguna página las usaba; decisión de Eloy):
gestión de juegos (`/api/juegos/*`), modo mantenimiento, detener/iniciar el
frontend, actualizar el repo, restaurar de fábrica, logs y su retención, ingresos
(`/api/monedas`, `/api/tiradas`), `/api/sistema`, `/api/eventos`, `/api/arranque/*`,
`/api/puntajes/actualizar` (ahora `/api/puntajes` se regenera solo tras jugar) y la
pantalla en MJPEG/JPG (la sustituyó el H.264). Están en el historial de git.

---

## Notas de implementación (lado backend)

- El panel escucha **solo en `127.0.0.1`**; quien lo expone es `cloudflared`.
- Las órdenes a MAME (créditos, salir) no se ejecutan directo: se dejan en
  `~/.attract/panel_cmd` y `creditos.lua` las aplica en su bucle por-frame, porque
  solo el Lua dentro de MAME puede tocar el ioport o cerrar la máquina.
- El resto de acciones las ejecuta el panel como `arcade` (sudo NOPASSWD) o con
  `systemctl --user`.
- Ver `panel/servidor.py`: sólo tiene las rutas que usan las páginas de `pi/web/`.
- `GET /api/compilacion` es público a propósito (avance de compilar GroovyMAME,
  `pi/web/compilacion.html`); su respuesta se guarda 10 s para que no se pueda
  usar para cargar la cabina.
