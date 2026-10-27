#!/usr/bin/env python3
"""Portero del panel, para el Raspberry Pi (la PUERTA, siempre encendida).

Se pone entre Cloudflare y la cabina.  El backend de verdad (panel/servidor.py)
sigue corriendo EN LA CABINA, pegado a sus datos (latencia 0); el Pi solo:

  - reenvia cada peticion a la cabina por el cable LAN (incluido SSE y subidas);
  - si la cabina esta apagada, contesta que lo esta (503) en vez de un error feo;
  - sirve POST /api/accion/encender -> Wake-on-LAN por el cable (la unica accion
    que tiene sentido con la cabina apagada, y que el backend no puede hacer).

Solo stdlib: en el Pi no hace falta instalar Flask ni nada.  cloudflared apunta
a ESTE portero (127.0.0.1:PUERTO), no directo a la cabina, para que el caso
"apagada" y el "encender" funcionen.

Config por entorno (o por pi/portero.service):
  CABINA      host:puerto de la cabina por el cable LAN   (def 10.55.0.2:8808)
  CABINA_MAC  MAC de la cabina para Wake-on-LAN           (def '' -> sin WoL)
  BROADCAST   difusion del enlace LAN, para que el WoL salga por el cable
              correcto y no por el internet del Pi        (def 10.55.0.255)
  PUERTO      puerto en que escucha el portero            (def 8080)
"""

import os
import socket
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

CABINA = os.environ.get("CABINA", "10.55.0.2:8808")
CABINA_MAC = os.environ.get("CABINA_MAC", "")
BROADCAST = os.environ.get("BROADCAST", "10.55.0.255")
PUERTO = int(os.environ.get("PUERTO", "8080"))
# IP en que escucha el portero.  127.0.0.1 = solo cloudflared local (lo normal
# con tunel).  Para acceso LOCAL por la red (sin tunel), ponlo a 0.0.0.0.
ESCUCHA = os.environ.get("ESCUCHA", "127.0.0.1")
# La GUI la sirve el PROPIO Pi (siempre encendido), para que la pagina cargue
# aunque la cabina este apagada y se pueda pulsar "Encender".  Solo las llamadas
# /api/* se reenvian a la cabina.
WEB = os.environ.get("WEB", os.path.expanduser("~/web"))
BASE = "http://" + CABINA

TIPOS = {".html": "text/html; charset=utf-8", ".css": "text/css",
         ".js": "application/javascript", ".png": "image/png",
         ".jpg": "image/jpeg", ".svg": "image/svg+xml",
         ".json": "application/json", ".ico": "image/x-icon"}

# Cabeceras salto-a-salto: no se reenvian (RFC 7230).  Content-Length SI se copia.
HOP = {"connection", "keep-alive", "proxy-authenticate", "proxy-authorization",
       "te", "trailers", "transfer-encoding", "upgrade"}


def cabina_viva(timeout=1.0):
    host, _, puerto = CABINA.partition(":")
    try:
        with socket.create_connection((host, int(puerto or 80)), timeout):
            return True
    except OSError:
        return False


def paquete_wol(mac):
    """Magic packet: 6 bytes 0xFF + la MAC repetida 16 veces (102 bytes)."""
    limpia = mac.replace(":", "").replace("-", "").strip()
    if len(limpia) != 12:
        raise ValueError("MAC invalida: %r" % mac)
    return bytes.fromhex("ff" * 6 + limpia * 16)


def despertar():
    if not CABINA_MAC:
        return False, "falta CABINA_MAC"
    try:
        datos = paquete_wol(CABINA_MAC)
    except ValueError as ex:
        return False, str(ex)
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        s.sendto(datos, (BROADCAST, 9))   # puerto 9 (discard), el habitual de WoL
        s.close()
        return True, "magic packet enviado a %s por %s" % (CABINA_MAC, BROADCAST)
    except OSError as ex:
        return False, str(ex)


class Portero(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def _json(self, obj, codigo=200):
        import json
        c = json.dumps(obj).encode("utf-8")
        self.close_connection = True
        self.send_response(codigo)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(c)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(c)

    def _manejar(self):
        # "Encender" lo resuelve el portero: la cabina puede estar apagada.
        if self.path == "/api/accion/encender" and self.command == "POST":
            if cabina_viva():
                return self._json({"ok": True, "nota": "la cabina ya esta encendida"})
            ok, msg = despertar()
            return self._json({"ok": ok, "nota": msg} if ok
                              else {"ok": False, "error": msg}, 200 if ok else 500)
        if self.path == "/api/puerta":
            return self._json({"cabina_online": cabina_viva(),
                               "wol": bool(CABINA_MAC)})
        # Las llamadas a la API van a la cabina; si esta apagada, 503 claro.
        if self.path.startswith("/api/"):
            if not cabina_viva():
                return self._json({"ok": False, "cabina_online": False,
                                   "error": "la cabina esta apagada"}, 503)
            return self._proxy()
        # Todo lo demas es la GUI: la sirve el propio Pi (haya cabina o no).
        return self._static(self.path)

    def _static(self, ruta):
        ruta = ruta.split("?", 1)[0]          # fuera la query
        if ruta in ("/", ""):
            ruta = "/index.html"
        # realpath + commonpath: cierra el path traversal (y los symlinks que
        # salgan de WEB), que un startswith a secas no pilla (p.ej. 'web2').
        base = os.path.realpath(WEB)
        destino = os.path.realpath(os.path.join(base, ruta.lstrip("/")))
        if os.path.commonpath([base, destino]) != base or not os.path.isfile(destino):
            return self._json({"error": "no encontrado (pon la GUI en %s)" % WEB}, 404)
        datos = open(destino, "rb").read()
        self.close_connection = True
        self.send_response(200)
        self.send_header("Content-Type",
                         TIPOS.get(os.path.splitext(destino)[1].lower(),
                                   "application/octet-stream"))
        self.send_header("Content-Length", str(len(datos)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(datos)

    def _proxy(self):
        """Reenvia la peticion a la cabina y devuelve su respuesta, en streaming
        (sirve igual para JSON, para SSE y para las subidas con Content-Length).
        shortcut: lee el cuerpo por Content-Length; una subida con
        Transfer-Encoding: chunked no se reenviaria entera -> si hiciera falta,
        poner un proxy de verdad (nginx/caddy) en el Pi."""
        largo = int(self.headers.get("Content-Length") or 0)
        cuerpo = self.rfile.read(largo) if largo else None
        req = urllib.request.Request(BASE + self.path, data=cuerpo,
                                     method=self.command)
        for k, v in self.headers.items():
            if k.lower() not in HOP and k.lower() != "host":
                req.add_header(k, v)
        try:
            resp = urllib.request.urlopen(req, timeout=600)
        except urllib.error.HTTPError as e:
            resp = e                      # reenvia tambien los 4xx/5xx del backend
        except OSError as ex:
            return self._json({"ok": False, "error": "cabina: %s" % ex}, 502)

        self.close_connection = True      # una conexion por peticion: simple y correcto
        self.send_response(resp.status)
        for k, v in resp.getheaders():
            if k.lower() in HOP or k.lower() == "content-length":
                continue
            self.send_header(k, v)
        self.send_header("Connection", "close")   # el cuerpo acaba al cerrar
        self.end_headers()
        # SSE (flujo infinito): hay que mandar CADA linea segun llega, no esperar
        # a llenar un buffer, o las metricas y los botones en vivo se atascarian.
        es_sse = "text/event-stream" in (resp.getheader("Content-Type") or "").lower()
        try:
            if es_sse:
                for linea in resp:          # readline: cede cada linea al instante
                    self.wfile.write(linea)
                    self.wfile.flush()
            else:
                while True:
                    trozo = resp.read(65536)
                    if not trozo:
                        break
                    self.wfile.write(trozo)
                    self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError, socket.timeout):
            pass

    do_GET = do_POST = do_PUT = do_DELETE = _manejar


def main():
    srv = ThreadingHTTPServer((ESCUCHA, PUERTO), Portero)
    print("portero en %s:%d -> cabina %s  (WoL: %s, difusion %s)"
          % (ESCUCHA, PUERTO, CABINA, CABINA_MAC or "sin MAC", BROADCAST))
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\nadios")


if __name__ == "__main__":
    import sys
    if "--self-check" in sys.argv:
        p = paquete_wol("AA:BB:CC:DD:EE:FF")
        assert len(p) == 102 and p[:6] == b"\xff" * 6, "magic packet mal"
        assert p[6:12] == bytes.fromhex("aabbccddeeff"), "MAC mal colocada"
        try:
            paquete_wol("nope")
        except ValueError:
            pass
        else:
            raise AssertionError("deberia rechazar MAC invalida")
        base = os.path.realpath(".")
        fuera = os.path.realpath(os.path.join(base, "../etc/passwd"))
        assert os.path.commonpath([base, fuera]) != base, "guard de traversal roto"
        print("self-check OK")
    else:
        main()
