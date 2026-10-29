#!/usr/bin/env python3
"""Extrai kernel/ramdisk/bootconfig de um boot image (header v3/v4)."""
import struct, sys, pathlib

def parse(path):
    d = pathlib.Path(path).read_bytes()
    assert d[:8] == b'ANDROID!', "sem magic ANDROID!"
    kv = struct.unpack('<I', d[40:44])[0]
    ksz, rsz = struct.unpack('<II', d[8:16])
    osv, hsz = struct.unpack('<II', d[16:24])
    cmd = d[44:44+1536].split(b'\0')[0]
    page = 4096
    off = ((hsz + page - 1) // page) * page
    kernel = d[off:off+ksz]; off += ((ksz + page - 1)//page)*page
    ramdisk = d[off:off+rsz]; off += ((rsz + page - 1)//page)*page
    rest = d[off:]
    bootconfig = b''
    if kv >= 4:
        if rest[:8] == b'T-B-L\0'[:4] + b'\0\0\0\0' or True:
            bootconfig = rest
    return dict(header_version=kv, kernel_size=ksz, ramdisk_size=rsz,
                header_size=hsz, cmdline=cmd, kernel=kernel,
                ramdisk=ramdisk, rest=rest, total=len(d))

def magic_of(b):
    if b[:2] == b'\x1f\x8b': return 'gzip'
    if b[:4] == b'\x02\x21\x4c\x18': return 'lz4'
    if b[:4] == b'\x04\x22\x4d\x18': return 'lz4-legacy'
    if b[:6] == b'\xfd7zXZ\x00': return 'xz'
    if b[:3] == b'BZh': return 'bzip2'
    if b[:5] == b'\x5d\x00\x00\x00\x00': return 'lzma?'
    return 'raw/desconhecido'

for p in sys.argv[1:]:
    h = parse(p)
    print(f"== {p}")
    print(f"   header_version={h['header_version']} kernel={h['kernel_size']} ramdisk={h['ramdisk_size']} header={h['header_size']} total={h['total']}")
    print(f"   cmdline={h['cmdline'][:60]!r}")
    print(f"   ramdisk magic={magic_of(h['ramdisk'])}  rest={len(h['rest'])} bytes ({magic_of(h['rest'])})")
    out = pathlib.Path('/tmp/rd') / (pathlib.Path(p).parent.name + '-' + pathlib.Path(p).stem)
    out.mkdir(parents=True, exist_ok=True)
    (out / 'ramdisk.bin').write_bytes(h['ramdisk'])
    (out / 'rest.bin').write_bytes(h['rest'])
    print(f"   -> {out}")
