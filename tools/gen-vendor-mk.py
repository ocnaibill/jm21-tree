#!/usr/bin/env python3
"""Regenera vendor/fiio/jm21/proprietary/proprietary.mk a partir da arvore extraida.

Filtros (cada um resolveu uma classe de erro do build):
  1. .apk            -> precisa ser modulo Soong (android_app_import)
  2. vintf           -> DEVICE_MANIFEST_FILE / fragments (nao vai por copy_files)
  3. instalados pelo Soong -> o build ja coloca no destino (conflito de alvo)
O resto entra como PRODUCT_COPY_FILES, INCLUSIVE vendor/etc/init/*.rc.
"""
import os, re, pathlib

ROOT = pathlib.Path.home() / "lineage20"
PROP = ROOT / "vendor/fiio/jm21"
TREE = PROP / "proprietary"
MK_OUT = TREE / "proprietary.mk"
INSTALLS = ROOT / "out/soong/installs-lineage_jm21.mk"

SKIP_DIRS = {"lost+found", "firmware", "firmware_mnt", "bt_firmware", "dsp"}
OUT = {
    "vendor": "$(TARGET_COPY_OUT_VENDOR)",
    "odm": "$(TARGET_COPY_OUT_ODM)",
    "vendor_dlkm": "$(TARGET_COPY_OUT_VENDOR_DLKM)",
}
VINTF_TOP = {"etc/vintf/manifest.xml", "etc/vintf/compatibility_matrix.xml"}

# destinos que o Soong instala
installed = set()
if INSTALLS.exists():
    for ln in INSTALLS.read_text().splitlines():
        m = re.match(r'^out/target/product/jm21/([^:]+):', ln)
        if m:
            installed.add(m.group(1).strip())

lines = [
    "# Gerado por tools/gen-vendor-mk.py — nao editar a mao.",
    "# Fonte: dumps/fw-1.1.1 (vendor.img, odm.img, vendor_dlkm.img)",
    "",
    "PRODUCT_COPY_FILES += \\",
]
count = skip_apk = skip_vintf = skip_conflict = 0
for part, dest in OUT.items():
    base = TREE / part
    if not base.is_dir():
        continue
    for dirpath, dirnames, filenames in os.walk(base):
        rel_dir = pathlib.Path(dirpath).relative_to(base)
        if rel_dir.parts and rel_dir.parts[0] in SKIP_DIRS:
            dirnames[:] = []
            continue
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for fn in sorted(filenames):
            src = pathlib.Path(dirpath) / fn
            if src.is_symlink():
                continue
            rel = (rel_dir / fn).as_posix()
            if fn.endswith(".apk"):
                skip_apk += 1
                continue
            if f"{part}/{rel}".split("/", 1)[1] in VINTF_TOP or "/etc/vintf/manifest/" in f"/{rel}":
                skip_vintf += 1
                continue
            if f"{part}/{rel}" in installed:
                skip_conflict += 1
                continue
            lines.append(f"    vendor/fiio/jm21/proprietary/{part}/{rel}:{dest}/{rel} \\")
            count += 1

lines[-1] = lines[-1].rstrip(" \\")
lines += ["", f"# copiados: {count}  |  pulados: {skip_apk} apk, {skip_vintf} vintf, {skip_conflict} ja instalados pelo Soong", ""]
MK_OUT.write_text("\n".join(lines) + "\n")
print(f"copiados={count} apk={skip_apk} vintf={skip_vintf} conflito_soong={skip_conflict}")
print("init.qcom.rc (hw):", (TREE / "vendor/etc/init/hw/init.qcom.rc").exists())
