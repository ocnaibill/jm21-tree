#!/usr/bin/env python3
"""Dump FDT (device tree blob) and Android DTBO images without external tools.

Usage:
  dt_dump.py <dtbo.img|dtb> --list          list DTBO entries
  dt_dump.py <dtbo.img> --dump <index>      dump one DTBO entry as a tree
  dt_dump.py <dtb> --tree                   dump a plain DTB as a tree
  dt_dump.py <dtbo.img> --grep <regex>      search nodes/properties in all entries
"""

import argparse
import re
import struct
import sys

FDT_MAGIC = 0xD00DFEED
DTBO_MAGIC = 0xD7B7AB1E

FDT_BEGIN_NODE = 1
FDT_END_NODE = 2
FDT_PROP = 3
FDT_NOP = 4
FDT_END = 9

PROP_FMT = {1: "B", 2: "H", 4: "I", 8: "Q"}


class Fdt:
    def __init__(self, blob):
        self.blob = blob
        magic, self.totalsize, off_struct, off_strings, off_rsvmap, version, \
            last_comp, boot_cpuid, size_strings, size_struct = struct.unpack(">10I", blob[:40])
        if magic != FDT_MAGIC:
            raise ValueError("not an FDT blob")
        self.version = version
        self.struct_off = off_struct
        self.strings_off = off_strings
        self.size_struct = size_struct

    def string_at(self, off):
        start = self.strings_off + off
        end = self.blob.index(b"\x00", start)
        return self.blob[start:end].decode("utf-8", "replace")

    def walk(self):
        """Yield (depth, kind, payload) events in document order."""
        off = self.struct_off
        depth = 0
        end = self.struct_off + self.size_struct
        while off < end:
            (token,) = struct.unpack(">I", self.blob[off:off + 4])
            off += 4
            if token == FDT_BEGIN_NODE:
                nul = self.blob.index(b"\x00", off)
                name = self.blob[off:nul].decode("utf-8", "replace")
                off = (nul + 4) & ~3
                yield depth, "node", name
                depth += 1
            elif token == FDT_END_NODE:
                depth -= 1
                yield depth, "endnode", None
            elif token == FDT_PROP:
                length, nameoff = struct.unpack(">II", self.blob[off:off + 8])
                off += 8
                value = self.blob[off:off + length]
                off = (off + length + 3) & ~3
                yield depth, "prop", (self.string_at(nameoff), value)
            elif token == FDT_NOP:
                continue
            elif token == FDT_END:
                return
            else:
                raise ValueError("bad FDT token 0x%x at %d" % (token, off - 4))


def fmt_value(value):
    if not value:
        return "(empty)"
    if len(value) % 4 == 0 and len(value) <= 64:
        cells = struct.unpack(">%dI" % (len(value) // 4), value)
        if any(c > 0xFFFFFF for c in cells) or len(cells) > 1:
            hexed = " ".join("<0x%x>" % c if c > 0xFF else "%d" % c for c in cells)
            text = printable(value)
            return "%s%s" % (hexed, "  ; \"%s\"" % text if text else "")
    text = printable(value)
    if text and len(text) == len(value):
        return "\"%s\"" % text
    return "0x" + value.hex()


def printable(value):
    out = []
    for b in value:
        if 32 <= b < 127:
            out.append(chr(b))
        elif b == 0:
            out.append(" ")
        else:
            return None
    return "".join(out).strip()


def parse_dtbo(blob):
    magic, total_size, header_size, entry_size, entry_count, entries_offset, \
        page_size, version = struct.unpack(">8I", blob[:32])
    if magic != DTBO_MAGIC:
        return None
    entries = []
    for i in range(entry_count):
        base = entries_offset + i * entry_size
        dt_size, dt_offset, dt_id, dt_rev = struct.unpack(">4I", blob[base:base + 16])
        entries.append({
            "index": i,
            "size": dt_size,
            "offset": dt_offset,
            "id": dt_id,
            "rev": dt_rev,
            "blob": blob[dt_offset:dt_offset + dt_size],
        })
    return {"version": version, "total_size": total_size, "entries": entries}


def dump_tree(blob, out=sys.stdout):
    fdt = Fdt(blob)
    out.write("# FDT version=%d size=%d\n" % (fdt.version, fdt.totalsize))
    for depth, kind, payload in fdt.walk():
        pad = "  " * depth
        if kind == "node":
            out.write("%s%s {\n" % (pad, payload or "/"))
        elif kind == "endnode":
            out.write("%s};\n" % pad)
        else:
            name, value = payload
            out.write("%s  %s = %s;\n" % (pad, name, fmt_value(value)))


def node_lines(blob, prefix=""):
    """Flatten a tree into 'path prop = value' lines for grepping/evidence."""
    fdt = Fdt(blob)
    stack = []
    for depth, kind, payload in fdt.walk():
        if kind == "node":
            stack.append(payload)
        elif kind == "endnode":
            if stack:
                stack.pop()
        else:
            name, value = payload
            path = "/" + "/".join(n for n in stack if n)
            yield "%s%s %s = %s" % (prefix, path, name, fmt_value(value))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("image")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--dump", type=int)
    ap.add_argument("--tree", action="store_true")
    ap.add_argument("--grep")
    args = ap.parse_args()

    with open(args.image, "rb") as fh:
        blob = fh.read()

    dtbo = parse_dtbo(blob)
    if dtbo is None:
        if args.list:
            print("plain DTB (no DTBO table), use --tree")
            return 0
        dump_tree(blob)
        return 0

    if args.list:
        print("DTBO version=%d total=%d entries=%d" % (
            dtbo["version"], dtbo["total_size"], len(dtbo["entries"])))
        for e in dtbo["entries"]:
            fp = Fdt(e["blob"])
            stack, compat = [], []
            for depth, kind, payload in fp.walk():
                if kind == "node":
                    stack.append(payload)
                elif kind == "endnode":
                    if stack:
                        stack.pop() 
                elif payload[0] == "compatible":
                    compat.append(payload[1].rstrip(b"\x00").decode("utf-8", "replace"))
            print("  [%2d] id=%d rev=%d size=%-7d roots=%s" % (
                e["index"], e["id"], e["rev"], e["size"],
                ",".join(sorted(set(c.replace("\x00", " ") for c in compat)))[:110]))
        return 0

    if args.dump is not None:
        for e in dtbo["entries"]:
            if e["index"] == args.dump:
                dump_tree(e["blob"])
                return 0
        print("entry %d not found" % args.dump, file=sys.stderr)
        return 1

    if args.grep:
        pattern = re.compile(args.grep, re.I)
        for e in dtbo["entries"]:
            for line in node_lines(e["blob"], prefix="[%d] " % e["index"]):
                if pattern.search(line):
                    print(line)
        return 0

    ap.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main())
