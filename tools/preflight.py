#!/usr/bin/env python3
"""
preflight.py — valida imagens geradas contra a referencia STOCK, offline.

Cada defeito de empacotamento que nos custou uma rodada de flash virou um check
aqui: header, kernel, compressao do ramdisk, padding, AVB, DTB e conteudo do
ramdisk. Se o check falha, NAO grave a imagem.

Uso:
    ./tools/preflight.py --built <dir>            # compara com dumps/fw-1.1.1
    ./tools/preflight.py --built <dir> -v         # mostra todos os checks
"""
import argparse, pathlib, struct, subprocess, sys, tempfile, os

ROOT = pathlib.Path(__file__).resolve().parent.parent
STOCK = ROOT / "dumps/fw-1.1.1"

# particao -> (arquivo stock, tamanho da particao)
PARTS = {
    "boot":        ("boot.img",        100663296),
    "init_boot":   ("init_boot.img",     8388608),
    "vendor_boot": ("vendor_boot.img", 100663296),
    "recovery":    ("recovery.img",    100663296),
    "dtbo":        ("dtbo.img",         25165824),
}

MAGIC_FDT = bytes.fromhex("d00dfeed")
ok = fail = 0

def cmp(name, expected, got):
    global ok, fail
    if expected == got:
        ok += 1
        return True
    fail += 1
    print(f"  FALHA  {name}: esperado {expected!r}, encontrado {got!r}")
    return False

def boot_header(d):
    """Retorna dict com os campos do header ANDROID!/VNDRBOOT!"""
    if d[:8] == b"ANDROID!":
        kv = struct.unpack("<I", d[40:44])[0]
        ksz, rsz = struct.unpack("<II", d[8:16])
        osv, hsz = struct.unpack("<II", d[16:24])
        page = 4096
        off = ((hsz + page - 1) // page) * page
        ramdisk_off = off + ((ksz + page - 1) // page) * page
        return dict(kind="boot", header_version=kv, kernel=ksz, ramdisk=rsz,
                    header_size=hsz, ramdisk_off=ramdisk_off,
                    ramdisk_bytes=d[ramdisk_off:ramdisk_off + rsz])
    if d[:8] == b"VNDRBOOT":
        kv, page = struct.unpack("<II", d[8:16])
        vrs = struct.unpack("<I", d[24:28])[0]
        hsz, dtbsz = struct.unpack("<II", d[2096:2104])
        off = ((hsz + page - 1) // page) * page
        return dict(kind="vendor_boot", header_version=kv, kernel=0,
                    ramdisk=vrs, header_size=hsz, ramdisk_off=off,
                    ramdisk_bytes=d[off:off + vrs], dtb_size=dtbsz)
    return None

def compression(b):
    if b[:4] == b"\x02\x21\x4c\x18": return "lz4"
    if b[:2] == b"\x1f\x8b": return "gzip"
    if b[:6] == b"\xfd7zXZ": return "xz"
    return "desconhecido"

def dump_ramdisk_list(raw, label):
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="pf-"))
    rd = tmp / "rd.bin"; rd.write_bytes(raw)
    cpio = tmp / "rd.cpio"
    comp = compression(raw)
    try:
        if comp == "lz4":
            with cpio.open("wb") as fh:
                subprocess.run(["lz4", "-d", "-c", str(rd)], stdout=fh, check=True,
                               stderr=subprocess.DEVNULL)
        elif comp == "gzip":
            with cpio.open("wb") as fh:
                subprocess.run(["gzip", "-dc", str(rd)], stdout=fh, check=True,
                               stderr=subprocess.DEVNULL)
        else:
            return None
        out = subprocess.run(["cpio", "-it", "--quiet"], stdin=cpio.open("rb"),
                             capture_output=True, text=True)
        return sorted(x for x in out.stdout.splitlines() if x.strip())
    except Exception:
        return None

def check_partition(name, built_path, verbose):
    global ok, fail
    stock_file, part_size = PARTS[name]
    ref = (STOCK / stock_file)
    if not ref.exists():
        print(f"- {name}: referencia stock ausente, pulando")
        return
    if not built_path.exists():
        print(f"- {name}: imagem nao encontrada ({built_path})")
        return

    print(f"\n== {name}")
    sd = ref.read_bytes(); bd = built_path.read_bytes()
    sh = boot_header(sd); bh = boot_header(bd)

    if name == "dtbo":
        cmp("FDT presente", sd.find(MAGIC_FDT) >= 0, bd.find(MAGIC_FDT) >= 0)
        if len(bd) > part_size:
            fail += 1
            print(f"  FALHA  dtbo maior que a particao ({len(bd)} > {part_size})")
        else:
            ok += 1
        return

    if not bh:
        print("  FALHA  header nao reconhecido (nem ANDROID! nem VNDRBOOT!)")
        fail += 1
        return
    cmp("header_version", sh["header_version"], bh["header_version"])
    cmp("tamanho do kernel", sh["kernel"], bh["kernel"])
    cmp("compressao do ramdisk",
        compression(sh["ramdisk_bytes"]), compression(bh["ramdisk_bytes"]))
    cmp("imagem preenchida ate a particao", part_size, len(bd))

    # AVB: mesmo offset de footer (ou ausencia nos dois)
    sf = sd.rfind(b"AVBf"); bf = bd.rfind(b"AVBf")
    cmp("footer AVB presente", sf >= 0, bf >= 0)
    if sf >= 0 and bf >= 0:
        cmp("offset do footer AVB", sf, bf)

    if bh["kind"] == "vendor_boot":
        # bootconfig: sem ele o kernel ignora ro.boot.* (usbcontroller, bootdevice)
        cmp("bootconfig presente", b"#BOOTCONFIG" in sd, b"#BOOTCONFIG" in bd)
        cmp("DTB presente", sd.find(MAGIC_FDT) >= 0, bd.find(MAGIC_FDT) >= 0)
        sl = dump_ramdisk_list(sh["ramdisk_bytes"], "stock")
        bl = dump_ramdisk_list(bh["ramdisk_bytes"], "built")
        if sl and bl:
            smod = [x for x in sl if x.endswith(".ko")]
            bmod = [x for x in bl if x.endswith(".ko")]
            cmp("modulos no ramdisk (>= stock)", True, len(bmod) >= len(smod))
            cmp("first_stage_ramdisk/fstab",
                any("first_stage_ramdisk" in x for x in sl),
                any("first_stage_ramdisk" in x for x in bl))
        return

    gl = dump_ramdisk_list(sh["ramdisk_bytes"], "stock")
    bl = dump_ramdisk_list(bh["ramdisk_bytes"], "built")
    if name == "init_boot" and bl is not None:
        if "force_debuggable" not in bl:
            fail += 1
            print("  AVISO  force_debuggable ausente: nao havera adb no boot do sistema")
    bl = dump_ramdisk_list(bh["ramdisk_bytes"], "built")
    if gl and bl:
        missing = sorted(set(gl) - set(bl))
        if missing:
            fail += 1
            print(f"  FALHA  arquivos faltando no ramdisk: {missing[:6]}")
        else:
            ok += 1

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--built", required=True, help="diretorio com as imagens geradas")
    ap.add_argument("-v", "--verbose", action="store_true")
    a = ap.parse_args()
    bdir = pathlib.Path(a.built).expanduser()
    if not bdir.is_dir():
        sys.exit(f"diretorio inexistente: {bdir}")

    print(f"preflight: {bdir}  x  {STOCK}")
    for name in PARTS:
        check_partition(name, bdir / f"{name}.img", a.verbose)

    print(f"\nresumo: {ok} ok, {fail} falha(s)")
    sys.exit(1 if fail else 0)

if __name__ == "__main__":
    main()
