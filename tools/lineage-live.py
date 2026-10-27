#!/usr/bin/env python3
"""
lineage-live.py — serve o painel do tools/lineage-status.sh via HTTP.

Pensado para acesso remoto pelo tailnet:
    python3 tools/lineage-live.py --bind 100.x.y.z --port 8765
    -> http://100.x.y.z:8765/

A pagina se auto-atualiza a cada N segundos (nao precisa de JS).
"""
import argparse, html, subprocess, pathlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = pathlib.Path(__file__).resolve().parent
STATUS = HERE / "lineage-status.sh"
REFRESH = 10

PAGE = """<!DOCTYPE html>
<html><head><meta charset="utf-8">
<meta http-equiv="refresh" content="{refresh}">
<title>Lineage jm21 — build</title>
<style>
 body{{background:#0d1117;color:#c9d1d9;font:13px/1.45 ui-monospace,monospace;margin:0;padding:14px}}
 pre{{margin:0;white-space:pre-wrap}}
 .hdr{{color:#58a6ff;font-weight:600;margin-bottom:10px}}
 .ok{{color:#3fb950}} .err{{color:#f85149}} .warn{{color:#d29922}}
 a{{color:#58a6ff}}
</style></head><body>
<div class="hdr">jm21 / LineageOS 20 — auto-refresh {refresh}s — {ts}</div>
<pre>{body}</pre>
</body></html>"""


def run_status() -> str:
    try:
        out = subprocess.run([str(STATUS)], capture_output=True, text=True, timeout=25)
        return out.stdout + (out.stderr or "")
    except Exception as exc:                                   # noqa: BLE001
        return f"erro ao rodar lineage-status.sh: {exc}"


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):                                          # noqa: N802
        import datetime
        raw = run_status()
        body = html.escape(raw)
        body = body.replace("SUCESSO", '<span class="ok">SUCESSO</span>')
        body = body.replace(">>> OTA gerada", '<span class="ok">>>> OTA gerada</span>')
        body = body.replace("nenhuma imagem gerada", '<span class="warn">nenhuma imagem gerada</span>')
        page = PAGE.format(refresh=REFRESH,
                           ts=datetime.datetime.now().strftime("%H:%M:%S"),
                           body=body)
        data = page.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *a):                                 # silencio
        pass


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--bind", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--refresh", type=int, default=10)
    a = ap.parse_args()
    REFRESH = a.refresh
    print(f"servindo em http://{a.bind}:{a.port}/ (refresh {a.refresh}s)", flush=True)
    ThreadingHTTPServer((a.bind, a.port), Handler).serve_forever()
