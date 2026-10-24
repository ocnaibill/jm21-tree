#!/usr/bin/env python3
"""Compara os CRCs de modversions exigidos por um .ko com um Module.symvers.

Uso: python3 tools/abi-check.py <Module.symvers> <arquivo.ko> [...]
Lê a seção __versions (struct modversion_info: u64 crc + char name[56]).
"""
import struct
import sys


def sections(path):
    data = open(path, "rb").read()
    if data[:4] != b"\x7fELF" or data[4] != 2:
        raise SystemExit(f"{path}: não é ELF64")
    le = data[5] == 1
    e = "<" if le else ">"
    e_shoff = struct.unpack_from(e + "Q", data, 0x28)[0]
    e_shentsize = struct.unpack_from(e + "H", data, 0x3A)[0]
    e_shnum = struct.unpack_from(e + "H", data, 0x3C)[0]
    e_shstrndx = struct.unpack_from(e + "H", data, 0x3E)[0]

    def sh(i):
        off = e_shoff + i * e_shentsize
        name, typ = struct.unpack_from(e + "II", data, off)
        flags, addr, offset, size = struct.unpack_from(e + "QQQQ", data, off + 8)
        return name, typ, offset, size

    _, _, stroff, strsize = sh(e_shstrndx)
    strtab = data[stroff:stroff + strsize]
    out = {}
    for i in range(e_shnum):
        name_off, typ, offset, size = sh(i)
        end = strtab.find(b"\0", name_off)
        name = strtab[name_off:end].decode()
        out[name] = (offset, size)
    return data, out


def parse_versions(path):
    data, secs = sections(path)
    if "__versions" not in secs:
        return {}
    off, size = secs["__versions"]
    res = {}
    for i in range(0, size, 64):
        chunk = data[off + i: off + i + 64]
        if len(chunk) < 64:
            break
        crc = struct.unpack_from("<Q", chunk, 0)[0]
        name = chunk[8:].split(b"\0")[0].decode(errors="replace")
        if name:
            res[name] = crc
    return res


def main():
    symvers_path, kos = sys.argv[1], sys.argv[2:]
    sym = {}
    for line in open(symvers_path):
        parts = line.split()
        if len(parts) >= 2:
            sym[parts[1]] = int(parts[0], 16)
    print(f"Module.symvers: {len(sym)} símbolos\n")
    for ko in kos:
        req = parse_versions(ko)
        ok = bad = miss = 0
        bad_list = []
        for name, crc in req.items():
            if name not in sym:
                miss += 1
                bad_list.append(f"  FALTA   {name}")
            elif sym[name] == crc:
                ok += 1
            else:
                bad += 1
                bad_list.append(f"  CRC {name}: ko=0x{crc:08x} kernel=0x{sym[name]:08x}")
        status = "COMPATÍVEL" if bad == 0 and miss == 0 else "INCOMPATÍVEL"
        print(f"{ko.split('/')[-1]:26s} {len(req):4d} símbolos | ok {ok:4d} | "
              f"CRC errado {bad:3d} | faltando {miss:3d}  -> {status}")
        for l in bad_list[:8]:
            print(l)


if __name__ == "__main__":
    main()
