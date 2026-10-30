#!/usr/bin/env bash
#
# make-recovery.sh — empacota o recovery do Lineage no formato que o JM21 aceita.
#
# O que este aparelho exige (descoberto em 2026-10-30):
#   1. recovery KERNEL-LESS (o kernel vive no boot)
#   2. ramdisk em LZ4
#   3. vbmeta AVB **nao assinado** embutido (avbtool --algorithm NONE)
#   4. imagem preenchida ate o tamanho da particao
#
set -euo pipefail
TREE="${1:-$HOME/lineage20}"
IMG="$TREE/out/target/product/jm21/recovery.img"
OUT="${2:-$HOME/jm21-artifacts/recovery-lineage.img}"
MKBOOTIMG="$TREE/out/host/linux-x86/bin/mkbootimg"
AVBTOOL="$TREE/external/avb/avbtool"
WORK=$(mktemp -d)

python3 - "$IMG" "$WORK/rd.lz4" <<'PY'
import struct, sys, pathlib
d = pathlib.Path(sys.argv[1]).read_bytes()
ks, rs = struct.unpack('<II', d[8:16]); hsz = struct.unpack('<I', d[20:24])[0]
off = ((hsz+4095)//4096)*4096 + ((ks+4095)//4096)*4096
pathlib.Path(sys.argv[2]).write_bytes(d[off:off+rs])
print(f"ramdisk extraido: {rs} bytes (kernel ignorado: {ks})")
PY

$MKBOOTIMG --ramdisk "$WORK/rd.lz4" --header_version 4 --pagesize 4096 \
    --os_version 12.0.0 --os_patch_level 2022-04 --output "$WORK/rec.img"

python3 "$AVBTOOL" add_hash_footer --image "$WORK/rec.img" \
    --partition_name recovery --partition_size 100663296 --algorithm NONE >/dev/null

cp "$WORK/rec.img" "$OUT"
rm -rf "$WORK"
echo "OK: $OUT ($(stat -c%s "$OUT") bytes)"
