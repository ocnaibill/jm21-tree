#!/usr/bin/env python3
"""Página de acompanhamento ao vivo do build do kernel (LAN).

Uso: python3 tools/build-live.py [log] [porta]
  http://<ip-do-host>:8080/      página com auto-refresh
  http://<ip-do-host>:8080/log   log puro
"""
import os
import sys
import time
import html
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LOG = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/jm21-kbuild/build2.log")
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 8080
START = time.time()


def tail(path, n):
    try:
        with open(path, "r", errors="replace") as f:
            lines = f.readlines()
        return lines[-n:]
    except FileNotFoundError:
        return ["(log ainda não existe)\n"]


def stats(path):
    try:
        with open(path, "r", errors="replace") as f:
            data = f.read()
    except FileNotFoundError:
        return {}
    return {
        "cc": data.count("  CC "),
        "ld": data.count("  LD "),
        "lto": data.count("  LTO "),
        "modpost": data.count("MODPOST"),
        "errors": sum(1 for l in data.splitlines() if "error:" in l or l.startswith("ERROR")),
        "warn": data.count("warning:"),
    }


PAGE = """<!doctype html><html><head><meta charset="utf-8">
<meta http-equiv="refresh" content="10">
<title>jm21-kbuild</title>
<style>
body{{background:#111;color:#ddd;font-family:ui-monospace,monospace;margin:0;padding:16px}}
h1{{font-size:15px;color:#8bd;margin:0 0 8px}}
.bar{{display:flex;gap:18px;flex-wrap:wrap;margin-bottom:10px;font-size:13px}}
.bar b{{color:#fff}}
pre{{background:#0a0a0a;border:1px solid #222;padding:10px;font-size:12px;
line-height:1.35;white-space:pre-wrap;word-break:break-word}}
.err{{color:#f66}}
</style></head><body>
<h1>jm21-kbuild — Plano B (kernel 5.15.41 + módulos vendor)</h1>
<div class="bar">
<span>última linha: <b>{last}</b></span>
<span>CC: <b>{cc}</b></span><span>LD: <b>{ld}</b></span>
<span>LTO: <b>{lto}</b></span><span>MODPOST: <b>{modpost}</b></span>
<span>erros: <b class="{cls}">{errors}</b></span>
<span>warnings: <b>{warn}</b></span>
<span>tempo: <b>{elapsed}</b></span>
</div>
<pre>{body}</pre>
<p style="font-size:12px;color:#666">auto-refresh 10 s · <a style="color:#8bd" href="/log">log puro</a></p>
</body></html>"""


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        if self.path.startswith("/log"):
            body = "".join(tail(LOG, 400))
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.end_headers()
            self.wfile.write(body.encode())
            return
        st = stats(LOG)
        lines = tail(LOG, 80)
        body = "".join(html.escape(l) for l in lines)
        last = html.escape(lines[-1].strip() if lines else "")
        elapsed = int(time.time() - START)
        page = PAGE.format(
            last=last, body=body,
            cc=st.get("cc", 0), ld=st.get("ld", 0), lto=st.get("lto", 0),
            modpost=st.get("modpost", 0), errors=st.get("errors", 0),
            warn=st.get("warn", 0), cls="err" if st.get("errors") else "",
            elapsed=f"{elapsed // 60}m{elapsed % 60:02d}s",
        )
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.end_headers()
        self.wfile.write(page.encode())


if __name__ == "__main__":
    print(f"servindo {LOG} em http://0.0.0.0:{PORT}/")
    ThreadingHTTPServer(("0.0.0.0", PORT), H).serve_forever()
