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

**Puedes empezar HOY, con la cabina apagada.** Hay un simulador que no necesita
instalar nada (solo Python):

```bash
python3 panel/simulador.py          # levanta un backend de mentira en el 8808
```

Abre `http://localhost:8808/` y verás la página de `panel/static/`. El simulador
responde a **todas** las rutas de abajo con datos inventados que cambian solos,
así que puedes construir y probar la GUI entera sin la cabina. Cuando tu página
esté lista, el backend real usa las **mismas rutas**: no cambias ni una línea.

**Dónde van tus archivos.** Pon tu `index.html`, tu CSS y tu JS en
`panel/static/`. El backend sirve esa carpeta tal cual. Claude deja ahí un
`index.html` mínimo de ejemplo; reemplázalo por el tuyo cuando quieras.

**Recursos:** javascript.info (el mejor para JS), freeCodeCamp ("Responsive Web
Design"), MDN (para consultar).

---

## Autenticación

Dos capas: **Cloudflare Access** delante (login por correo/Google antes de llegar
a la cabina) y una **sesión con contraseña** en el propio panel.

- `POST /api/login` — body `{"clave": "..."}`. Si acierta: pone cookie de sesión
  y devuelve `{"ok": true, "csrf": "<token>"}`. Si falla: `401`.
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
  "mantenimiento": false,
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

### `GET /api/eventos` (SSE)
Flujo de métricas en vivo (Server-Sent Events). Cada ~2 s manda un `data:` con un
subconjunto de `/api/estado` (cpu, temperatura, juego actual). Para un principiante
es opcional: se puede lograr lo mismo llamando a `/api/estado` con `setInterval`.

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

### `GET /api/monedas?desde=YYYY-MM-DD&hasta=YYYY-MM-DD`
Monedas e ingresos (de `~/.attract/monedas.log`). Ingresos = monedas × valor de la
moneda (`$100 CLP` por defecto, en `panel.conf`).
```json
{ "valor_moneda": 100, "total_monedas": 318, "ingresos": 31800,
  "por_juego": [ { "rom": "pacman", "titulo": "Pac-Man", "monedas": 92, "ingresos": 9200 } ],
  "por_dia":  [ { "fecha": "2026-10-12", "monedas": 40, "ingresos": 4000 } ] }
```

### `GET /api/juegos`
Lista de juegos para gestionar.
```json
[ { "rom": "pacman", "titulo": "Pac-Man", "visible": true,
    "partidas": 142, "tarifa": { "pesos": 100, "texto": "1 moneda / 1 crédito" } } ]
```
`tarifa` es `null` si la placa no tiene DIP de tarifa.

### `GET /api/logs?fuente=panel|monedero|attract|auditoria&lineas=200`
```json
{ "fuente": "monedero", "lineas": ["...", "..."] }
```

### `GET /api/captura.png`
Captura de lo que hay AHORA en la pantalla de la cabina (imagen PNG). Fase 4.

---

## Acciones (POST, exigen `X-CSRF-Token`)

Todas devuelven `{"ok": true}` o `{"ok": false, "error": "..."}`, y quedan
registradas en `~/.attract/panel_auditoria.log`.

| Ruta | Body | Qué hace |
|---|---|---|
| `POST /api/accion/reiniciar` | — | `sudo systemctl reboot` |
| `POST /api/accion/apagar` | — | `sudo systemctl poweroff` |
| `POST /api/accion/mantenimiento` | `{"activo": true}` | entra/sale de modo mantención (para el frontend, relé off, banner) |
| `POST /api/frontend/reiniciar` | — | `pkill -x attractplus` (el wrapper lo relanza) |
| `POST /api/monedero/reiniciar` | — | `systemctl --user restart monedero.service` (resetea serie + relé) |
| `POST /api/juego/salir` | — | sale limpio del juego en curso (orden a `creditos.lua`) |
| `POST /api/creditos` | `{"n": 1}` | inyecta N créditos en la partida en curso |
| `POST /api/pantalla` | `{"destino": "crt"}` | `"crt"` o `"panel"` (`pantalla-auto.sh`) |
| `POST /api/volumen` | `{"nivel": 80}` | 0-100 (`amixer`) |
| `POST /api/puntajes/actualizar` | — | re-ejecuta `puntajes.py` |
| `POST /api/juegos/<rom>/visible` | `{"visible": false}` | oculta/muestra el juego (`global_filter`) |
| `POST /api/juegos/<rom>/tarifa` | `{"pesos": 200}` | fija la tarifa; pasos de $100 (una moneda) |
| `POST /api/juegos/subir` | multipart `archivo` (.zip/.7z) | añade un juego y reconstruye la lista |
| `POST /api/juegos/<rom>/eliminar` | — | quita el ROM y reconstruye la lista |
| `POST /api/juegos/<rom>/reset-nvram` | — | borra la NVRAM del juego |
| `POST /api/juegos/<rom>/reset-puntajes` | — | borra el `.hi` del juego |
| `POST /api/actualizar` | — | actualiza el repo (guardando `arranque.dat`) |

Las acciones que necesitan el frontend parado (ocultar/mostrar, subir/eliminar,
tarifa, actualizar) solo deben lanzarse en **modo mantención**; el backend las
rechaza con un error claro si el frontend está vivo.

---

## Notas de implementación (lado backend)

- El panel escucha **solo en `127.0.0.1`**; quien lo expone es `cloudflared`.
- Las órdenes a MAME (créditos, salir) no se ejecutan directo: se dejan en
  `~/.attract/panel_cmd` y `creditos.lua` las aplica en su bucle por-frame, porque
  solo el Lua dentro de MAME puede tocar el ioport o cerrar la máquina.
- El resto de acciones las ejecuta el panel como `arcade` (sudo NOPASSWD) o con
  `systemctl --user`.
- Ver `panel/servidor.py` (real) y `panel/simulador.py` (de mentira, para la GUI).
