#!/usr/bin/env python3
"""
MiniStore - Sistema heredado de inventario ("on-premise").

Patron 7 (Lift-and-Shift): este mismo archivo, SIN cambios, corre en el servidor fisico
de la tienda y en la EC2 privada de AWS (10.2.1.10). Solo usa la libreria estandar de
Python, por eso la EC2 no necesita salida a Internet para instalar nada.

Endpoints:
  GET  /health                          -> estado y modo actual
  GET  /inventory/{productId}           -> stock del producto
  POST /admin/simulate?mode=normal      -> responde en ~50 ms
  POST /admin/simulate?mode=slow        -> duerme SLOW_DELAY_SECONDS (5 s) -> Timeout + Retry en Java
  POST /admin/simulate?mode=down        -> HTTP 500 inmediato           -> Circuit Breaker OPEN
"""
import json
import logging
import os
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

PORT = int(os.environ.get("INVENTORY_PORT", "8081"))
SLOW_DELAY_SECONDS = float(os.environ.get("SLOW_DELAY_SECONDS", "5"))
WAREHOUSE = os.environ.get("WAREHOUSE", "BODEGA-QUITO-01")
VALID_MODES = ("normal", "slow", "down")

INVENTORY = {1: 25, 2: 8, 3: 40, 4: 3}

_state = {"mode": os.environ.get("INITIAL_MODE", "normal")}
_lock = threading.Lock()

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s [legacy-inventory] %(message)s")
log = logging.getLogger("legacy")


def current_mode():
    with _lock:
        return _state["mode"]


class Handler(BaseHTTPRequestHandler):
    server_version = "MiniStoreLegacy/1.0"

    def _send(self, status, payload):
        body = json.dumps(payload).encode("utf-8")
        try:
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            # El cliente (Java) corto la conexion por Timeout: es lo esperado en modo slow
            log.warning("cliente cerro la conexion antes de recibir la respuesta")

    def do_GET(self):
        path = urlparse(self.path).path.rstrip("/")
        if path == "/health":
            return self._send(200, {"status": "UP", "mode": current_mode(), "warehouse": WAREHOUSE})

        if path.startswith("/inventory/"):
            try:
                product_id = int(path.rsplit("/", 1)[1])
            except ValueError:
                return self._send(400, {"error": "productId invalido"})

            mode = current_mode()
            if mode == "down":
                log.error("GET %s -> 500 (modo down)", path)
                return self._send(500, {"error": "Inventario no disponible (simulado)"})
            if mode == "slow":
                log.warning("GET %s -> durmiendo %.1fs (modo slow)", path, SLOW_DELAY_SECONDS)
                time.sleep(SLOW_DELAY_SECONDS)
            else:
                time.sleep(0.05)

            if product_id not in INVENTORY:
                return self._send(404, {"error": "producto no existe en inventario"})
            log.info("GET %s -> stock=%d", path, INVENTORY[product_id])
            return self._send(200, {"productId": product_id, "stock": INVENTORY[product_id], "warehouse": WAREHOUSE})

        return self._send(404, {"error": "ruta no encontrada"})

    def do_POST(self):
        parsed = urlparse(self.path)
        if parsed.path.rstrip("/") == "/admin/simulate":
            mode = parse_qs(parsed.query).get("mode", [""])[0]
            if mode not in VALID_MODES:
                return self._send(400, {"error": "mode debe ser uno de %s" % (VALID_MODES,)})
            with _lock:
                _state["mode"] = mode
            log.warning("modo de simulacion cambiado a '%s'", mode)
            return self._send(200, {"mode": mode})
        return self._send(404, {"error": "ruta no encontrada"})

    def log_message(self, fmt, *args):
        pass  # usamos nuestro propio logging


if __name__ == "__main__":
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    server.daemon_threads = True
    log.info("Inventario heredado escuchando en :%d (modo=%s)", PORT, current_mode())
    server.serve_forever()
