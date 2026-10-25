#!/usr/bin/env python3
"""Q20 - superficie exportada dos apps FiiO (issue #7).

Para cada componente que aparece numa Resolver Table SEM `permission`, lista as
acoes/categorias/data-schemes que ele aceita (linhas seguintes no dumpsys).
Saida agrupada por pacote, sem duplicatas.
"""
import re, subprocess

PKGS = [
    "com.android.aboutfiio", "com.fiio.tape", "com.fiio.fiioeq", "com.fiio.devicevendor",
    "com.fiio.market", "com.fiio.android", "com.fiio.entersleep", "com.android.fiioupdate",
    "com.fiio.music", "com.android.fiioroon", "com.fiio.scrcpy", "com.fiio.ipod",
    "com.android.fiio.scrcpy",
]

TABLES = ("Activity Resolver Table", "Receiver Resolver Table",
          "Service Resolver Table", "Provider Resolver Table")
ENTRY = re.compile(r'^\s+[0-9a-f]{6,8}\s+(\S+)\s+filter\s+[0-9a-f]+(.*)$')
ACTION = re.compile(r'^\s+(Action|Category|Scheme|Authority):\s*"?([^"]+)"?\s*$')

# ruido: bibliotecas de terceiros, nao codigo da FiiO
NOISE = ("androidx.", "com.google.", "com.microsoft.", "io.grpc.", "com.crashlytics.")


def dump(pkg):
    return subprocess.run(["adb", "shell", "dumpsys", "package", pkg],
                          capture_output=True, text=True).stdout


def audit(pkg):
    cur = None
    comp = None
    found = {}
    for line in dump(pkg).splitlines():
        for t in TABLES:
            if line.strip().startswith(t):
                cur = t.split()[0]
                comp = None
        m = ENTRY.match(line)
        if m:
            comp = None
            name, rest = m.group(1), m.group(2)
            if "permission" not in rest and not any(n in name for n in NOISE):
                key = (cur, name)
                comp = found.setdefault(key, [])
            continue
        a = ACTION.match(line)
        if a and comp is not None:
            val = f'{a.group(1)}:{a.group(2)}'
            if val not in comp:
                comp.append(val)
    return found


total = 0
for p in PKGS:
    rows = audit(p)
    if not rows:
        continue
    total += len(rows)
    print(f"\n## {p}")
    for (kind, name), acts in sorted(rows.items()):
        short = name.replace(p, "")
        print(f"   - {kind:<8} {short}")
        for a in acts:
            print(f"        {a}")
print(f"\nTOTAL de componentes exportados sem permissao (fora de libs de terceiros): {total}")
