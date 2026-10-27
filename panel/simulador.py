#!/usr/bin/env python3
"""Backend DE MENTIRA del panel, para construir la GUI con la cabina apagada.

No necesita instalar nada: solo Python 3. Levanta un servidor en el 8808 que
responde a TODAS las rutas /api/... del contrato (ver docs/panel.md) con datos
inventados que cambian solos, y sirve la pagina de panel/static/.

    python3 panel/simulador.py
    -> abre http://localhost:8808/

La GUI que escribas contra esto funcionara igual contra el backend real
(panel/servidor.py), porque las rutas y la forma del JSON son las mismas. Lo
unico que este simulador NO hace es tocar la cabina de verdad: las acciones POST
se aceptan, se registran por pantalla y devuelven {"ok": true}.

Clave de acceso por defecto: "arcade" (POST /api/login {"clave": "arcade"}).
"""

import json
import os
import random
import secrets
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

PUERTO = int(os.environ.get("PUERTO", "8808"))
CLAVE = os.environ.get("CLAVE", "arcade")
VALOR_MONEDA = 100  # $100 CLP por moneda

AQUI = os.path.dirname(os.path.abspath(__file__))
ESTATICO = os.path.join(AQUI, "static")

# Tokens CSRF validos (los que ha repartido /api/login en esta ejecucion).
TOKENS = set()

# ---------------------------------------------------------------------------
# Un mundo de mentira que evoluciona, para que la GUI se vea viva
# ---------------------------------------------------------------------------

JUEGOS = [
    ("pacman", "Pac-Man"), ("mspacman", "Ms. Pac-Man"), ("dkong", "Donkey Kong"),
    ("galaga", "Galaga"), ("frogger", "Frogger"), ("1943", "1943"),
    ("contra", "Contra"), ("kungfum", "Kung-Fu Master"), ("simpsons", "The Simpsons"),
    ("mslug", "Metal Slug"), ("sf2", "Street Fighter II"), ("qbert", "Q*bert"),
]

INICIO = time.time()

ESTADO = {
    "temp": 52.0,
    "cpu": 20.0,
    "juego_idx": None,          # None = en el menu
    "juego_desde": INICIO,
    "creditos_dentro": 0,
    "mantenimiento": False,
    "monedas_total": 0,
    "ocultos": set(),           # roms ocultadas desde la GUI
    "tarifas": {},              # rom -> pesos
    "volumen": 45,
    "detenido": False,
    "ultimo_cambio": INICIO,
}

RETENCION = {"cada": 12, "unidad": "horas"}

# Tiradas (partidas) de mentira, por juego.
TIRADAS_JUEGO = {rom: random.randint(1, 8) for rom, _ in JUEGOS}

# Un historico de monedas de mentira, por juego y por dia.
MONEDAS_JUEGO = {rom: random.randint(10, 120) for rom, _ in JUEGOS}
MONEDAS_DIA = {}
for i in range(7):
    dia = time.strftime("%Y-%m-%d", time.localtime(INICIO - i * 86400))
    MONEDAS_DIA[dia] = random.randint(15, 80)

PARTIDAS = {rom: random.randint(20, 400) for rom, _ in JUEGOS}
TIEMPO = {rom: PARTIDAS[rom] * random.randint(60, 240) for rom, _ in JUEGOS}
ULTIMA = {rom: int(INICIO - random.randint(0, 7 * 86400)) for rom, _ in JUEGOS}


def evolucionar():
    """Hace derivar el mundo de mentira cada vez que alguien pregunta el estado:
    la temperatura y la CPU oscilan, y de vez en cuando empieza o acaba un juego.
    """
    e = ESTADO
    ahora = time.time()
    e["temp"] = max(38.0, min(82.0, e["temp"] + random.uniform(-1.5, 1.5)))
    e["cpu"] = max(3.0, min(99.0, e["cpu"] + random.uniform(-8, 8)))
    # Cada ~20 s cambia de juego / vuelve al menu.
    if ahora - e["ultimo_cambio"] > 20:
        e["ultimo_cambio"] = ahora
        if e["juego_idx"] is None:
            e["juego_idx"] = random.randrange(len(JUEGOS))
            e["juego_desde"] = ahora
            e["creditos_dentro"] = random.randint(0, 3)
        else:
            # Al "salir", suma un par de monedas al historico.
            rom = JUEGOS[e["juego_idx"]][0]
            m = random.randint(1, 4)
            MONEDAS_JUEGO[rom] += m
            e["monedas_total"] += m
            hoy = time.strftime("%Y-%m-%d")
            MONEDAS_DIA[hoy] = MONEDAS_DIA.get(hoy, 0) + m
            PARTIDAS[rom] += 1
            e["juego_idx"] = None


def tarifa_de(rom):
    pesos = ESTADO["tarifas"].get(rom, 100)
    monedas = pesos // VALOR_MONEDA
    texto = "%d moneda%s / 1 crédito" % (monedas, "" if monedas == 1 else "s")
    return {"pesos": pesos, "texto": texto}


def juego_actual():
    e = ESTADO
    if e["juego_idx"] is None:
        return None
    rom, titulo = JUEGOS[e["juego_idx"]]
    return {
        "rom": rom, "titulo": titulo, "corriendo": True,
        "segundos": int(time.time() - e["juego_desde"]),
        "creditos_dentro": e["creditos_dentro"],
    }


def dato_estado():
    evolucionar()
    e = ESTADO
    return {
        "hora": int(time.time()),
        "uptime_seg": int(time.time() - INICIO) + 48000,
        "mantenimiento": e["mantenimiento"],
        "cpu": {"uso_pct": round(e["cpu"]), "nucleos": 4,
                "carga": [round(e["cpu"] / 100 * 4, 2)] * 3},
        "temperatura_c": round(e["temp"]), "temperatura_max_c": 90,
        "ram": {"usada_mb": 1800 + random.randint(-100, 100),
                "total_mb": 3800, "pct": 47},
        "disco": {"usado_gb": 61, "total_gb": 1800, "libre_gb": 1739, "pct": 3},
        "juego_actual": juego_actual(),
        "red": {"ip_publica": "190.11.22.33", "tunel": "activo"},
        "servicios": {k: "activo" for k in
                      ("panel", "monedero", "pantalla-auto",
                       "cloudflared", "frontend", "x")},
        "arduino": {"conectado": True, "puerto": "/dev/ttyUSB0",
                    "rele": "on" if juego_actual() else "off", "ultimo_error": None},
        "versiones": {"mame": "0.264", "attractplus": "3.2.3"},
        "juegos_total": len(JUEGOS),
        "commit": {"hash": "cdf0107", "fecha": "2026-10-02",
                   "mensaje": "simulador: datos de mentira"},
    }


def dato_puntajes():
    juegos = {}
    for rom, titulo in JUEGOS:
        base = random.randint(20000, 90000)
        puestos = []
        for i in range(5):
            puestos.append({
                "puesto": i + 1, "puntos": base - i * random.randint(1000, 4000),
                "nombre": random.choice(["ELO", "ABC", "JJ", None]),
                "confirmado": random.random() > 0.5,
            })
        juegos[rom] = {"titulo": titulo, "puestos": puestos}
    return {"generado": int(time.time()), "juegos": juegos}


def dato_masjugados(orden, limite):
    filas = [{"rom": rom, "titulo": titulo, "partidas": PARTIDAS[rom],
              "tiempo_seg": TIEMPO[rom], "ultima": ULTIMA[rom]}
             for rom, titulo in JUEGOS]
    clave = "tiempo_seg" if orden == "tiempo" else "partidas"
    filas.sort(key=lambda f: f[clave], reverse=True)
    return filas[:limite]


def dato_monedas():
    titulos = dict(JUEGOS)
    por_juego = [{"rom": r, "titulo": titulos[r], "monedas": m,
                  "ingresos": m * VALOR_MONEDA}
                 for r, m in sorted(MONEDAS_JUEGO.items(),
                                    key=lambda x: x[1], reverse=True)]
    por_dia = [{"fecha": d, "monedas": m, "ingresos": m * VALOR_MONEDA}
               for d, m in sorted(MONEDAS_DIA.items())]
    total = sum(MONEDAS_JUEGO.values())
    hoy_total = MONEDAS_DIA.get(time.strftime("%Y-%m-%d"), 0)
    por_hora = [{"hora": h, "monedas": m, "ingresos": m * VALOR_MONEDA}
                for h, m in _por_hora(hoy_total)]
    return {"valor_moneda": VALOR_MONEDA, "total_monedas": total,
            "ingresos": total * VALOR_MONEDA,
            "por_juego": por_juego, "por_dia": por_dia, "por_hora": por_hora}


def dato_juegos():
    return [{"rom": rom, "titulo": titulo,
             "visible": rom not in ESTADO["ocultos"],
             "partidas": PARTIDAS[rom], "tarifa": tarifa_de(rom)}
            for rom, titulo in JUEGOS]


def _por_hora(total):
    """Reparte 'total' en unas horas de hoy, para las pestanas 'Hoy'."""
    hoy = time.strftime("%Y-%m-%d")
    horas = []
    restante = total
    for h in (13, 14, 15, 16):
        v = random.randint(0, max(0, restante))
        restante -= v
        horas.append((("%s %02d:00") % (hoy, h), v))
    return horas


def dato_tiradas():
    titulos = dict(JUEGOS)
    por_juego = [{"rom": r, "titulo": titulos[r], "tiradas": n}
                 for r, n in sorted(TIRADAS_JUEGO.items(),
                                    key=lambda x: x[1], reverse=True)]
    total = sum(TIRADAS_JUEGO.values())
    return {"total": total, "por_juego": por_juego,
            "por_dia": [{"fecha": time.strftime("%Y-%m-%d"), "tiradas": total}],
            "por_hora": [{"hora": h, "tiradas": n} for h, n in _por_hora(total)]}


def dato_sistema():
    return {"equipo": "Sony VAIO", "cpu_modelo": "Intel(R) Core(TM) i5-2430M",
            "ram_total_mb": 8192, "disco_total_gb": 250, "so": "GroovyArcade 2.0",
            "mame": "0.264", "attractplus": "3.2.3"}


# ---------------------------------------------------------------------------
# El servidor
# ---------------------------------------------------------------------------

class Handler(BaseHTTPRequestHandler):
    # Silencia el log por defecto (una linea por peticion); dejamos solo las
    # acciones, que son las interesantes al desarrollar la GUI.
    def log_message(self, *a):
        pass

    # -- utilidades --------------------------------------------------------
    def _json(self, obj, codigo=200):
        cuerpo = json.dumps(obj).encode("utf-8")
        self.send_response(codigo)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(cuerpo)))
        self.end_headers()
        self.wfile.write(cuerpo)

    def _cuerpo(self):
        n = int(self.headers.get("Content-Length", 0) or 0)
        if not n:
            return {}
        datos = self.rfile.read(n)
        try:
            return json.loads(datos or b"{}")
        except ValueError:
            return {}

    def _csrf_ok(self):
        return self.headers.get("X-CSRF-Token", "") in TOKENS

    # -- GET ---------------------------------------------------------------
    def do_GET(self):
        ruta = urlparse(self.path)
        p = ruta.path
        q = parse_qs(ruta.query)

        if p == "/api/sesion":
            return self._json({"autenticado": True})
        if p == "/api/estado":
            return self._json(dato_estado())
        if p == "/api/sistema":
            return self._json(dato_sistema())
        if p == "/api/volumen":
            return self._json({"ok": True, "nivel": ESTADO["volumen"]})
        if p == "/api/tiradas":
            return self._json(dato_tiradas())
        if p == "/api/logs/retencion":
            return self._json(RETENCION)
        if p == "/api/puerta":
            # En produccion lo contesta el portero del Pi, no la cabina.
            return self._json({"cabina_online": True, "wol": True})
        if p == "/api/puntajes":
            return self._json(dato_puntajes())
        if p == "/api/masjugados":
            orden = (q.get("orden") or ["partidas"])[0]
            limite = int((q.get("limite") or ["20"])[0])
            return self._json(dato_masjugados(orden, limite))
        if p == "/api/monedas":
            return self._json(dato_monedas())
        if p == "/api/juegos":
            return self._json(dato_juegos())
        if p.startswith("/api/juegos/") and p.endswith("/tarifa"):
            rom = p.split("/")[3]
            t = tarifa_de(rom)
            return self._json({"rom": rom, "pesos": t["pesos"], "texto": t["texto"]})
        if p == "/api/botones":
            return self._sse_botones()
        if p == "/api/logs":
            fuente = (q.get("fuente") or ["panel"])[0]
            lineas = ["[%s] linea de ejemplo %d del log '%s'"
                      % (time.strftime("%H:%M:%S"), i, fuente) for i in range(30)]
            return self._json({"fuente": fuente, "lineas": lineas})
        if p == "/api/eventos":
            return self._sse()

        # Cualquier otra cosa: ficheros estaticos (la GUI).
        return self._estatico(p)

    # -- POST --------------------------------------------------------------
    def do_POST(self):
        p = urlparse(self.path).path

        if p == "/api/login":
            cuerpo = self._cuerpo()
            if cuerpo.get("clave") == CLAVE:
                token = secrets.token_hex(16)
                TOKENS.add(token)
                return self._json({"ok": True, "csrf": token})
            return self._json({"ok": False, "error": "clave incorrecta"}, 401)
        if p == "/api/logout":
            return self._json({"ok": True})
        if p == "/api/accion/encender":
            # Lo sirve el portero del Pi (la cabina puede estar apagada), asi que
            # NO exige la sesion/CSRF de la app: la barrera es Cloudflare Access.
            print("  [accion simulada] /api/accion/encender (Wake-on-LAN)")
            return self._json({"ok": True, "nota": "magic packet enviado (simulado)"})

        # El resto son acciones: exigen token CSRF.
        if not self._csrf_ok():
            return self._json({"ok": False, "error": "falta X-CSRF-Token"}, 403)

        cuerpo = self._cuerpo()
        print("  [accion simulada] %s %s" % (p, cuerpo or ""))

        if p == "/api/accion/mantenimiento":
            ESTADO["mantenimiento"] = bool(cuerpo.get("activo"))
        elif p == "/api/frontend/detener":
            ESTADO["detenido"] = True
        elif p == "/api/frontend/iniciar":
            ESTADO["detenido"] = False
        elif p == "/api/volumen":
            ESTADO["volumen"] = int(cuerpo.get("nivel", 45))
        elif p == "/api/logs/retencion":
            RETENCION["cada"] = int(cuerpo.get("cada", 12))
            RETENCION["unidad"] = cuerpo.get("unidad", "horas")
        elif p.startswith("/api/juegos/") and p.endswith("/visible"):
            rom = p.split("/")[3]
            if cuerpo.get("visible"):
                ESTADO["ocultos"].discard(rom)
            else:
                ESTADO["ocultos"].add(rom)
        elif p.startswith("/api/juegos/") and p.endswith("/tarifa"):
            rom = p.split("/")[3]
            ESTADO["tarifas"][rom] = int(cuerpo.get("pesos", 100))

        # Todas las acciones conocidas devuelven ok. (El simulador no distingue:
        # cualquier POST con token valido se acepta, que es lo que hace falta
        # para probar la GUI.)
        return self._json({"ok": True})

    # -- Server-Sent Events ------------------------------------------------
    def _sse(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "keep-alive")
        self.end_headers()
        try:
            while True:
                d = dato_estado()
                chico = {"cpu": d["cpu"]["uso_pct"],
                         "temperatura_c": d["temperatura_c"],
                         "juego_actual": d["juego_actual"]}
                self.wfile.write(b"data: " + json.dumps(chico).encode() + b"\n\n")
                self.wfile.flush()
                time.sleep(2)
        except (BrokenPipeError, ConnectionResetError):
            pass  # el navegador cerro la pestana; normal

    def _sse_botones(self):
        """Pulsaciones de mentira para probar la pantalla 'Test botones'."""
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        codigos = [304, 305, 307, 308, 310, 311]   # botones tipicos de mando
        try:
            while True:
                ev = {"dispositivo": "Xinmotek Dual Controller",
                      "codigo": random.choice(codigos), "pulsado": True}
                self.wfile.write(b"data: " + json.dumps(ev).encode() + b"\n\n")
                self.wfile.flush()
                time.sleep(1.2)
        except (BrokenPipeError, ConnectionResetError):
            pass

    # -- ficheros estaticos ------------------------------------------------
    def _estatico(self, p):
        if p == "/" or p == "":
            p = "/index.html"
        # Seguridad: nada de salirse de panel/static/ con "..".
        destino = os.path.normpath(os.path.join(ESTATICO, p.lstrip("/")))
        if not destino.startswith(ESTATICO) or not os.path.isfile(destino):
            cuerpo = (b"<h1>panel/static/ esta vacio</h1>"
                      b"<p>Pon aqui tu index.html. El simulador ya responde "
                      b"en <code>/api/...</code>.</p>")
            self.send_response(404)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(cuerpo)))
            self.end_headers()
            self.wfile.write(cuerpo)
            return
        tipos = {".html": "text/html; charset=utf-8", ".css": "text/css",
                 ".js": "application/javascript", ".png": "image/png",
                 ".jpg": "image/jpeg", ".svg": "image/svg+xml",
                 ".json": "application/json", ".ico": "image/x-icon"}
        ext = os.path.splitext(destino)[1].lower()
        with open(destino, "rb") as f:
            cuerpo = f.read()
        self.send_response(200)
        self.send_header("Content-Type", tipos.get(ext, "application/octet-stream"))
        self.send_header("Content-Length", str(len(cuerpo)))
        self.end_headers()
        self.wfile.write(cuerpo)


def main():
    srv = ThreadingHTTPServer(("127.0.0.1", PUERTO), Handler)
    print("Simulador del panel en http://localhost:%d/  (clave: %r)" % (PUERTO, CLAVE))
    print("Ctrl-C para parar.")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\nadios")


if __name__ == "__main__":
    main()
