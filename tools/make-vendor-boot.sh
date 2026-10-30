#!/usr/bin/env bash
#
# make-vendor-boot.sh — gera um vendor_boot com o fstab do primeiro estagio
# SEM verificacao AVB para system/system_ext/product.
#
# Por que: o fstab stock exige `avb=vbmeta_system` + `avb_keys=...gsi...`, e o
# fs_mgr so aceita um vbmeta_system assinado com as chaves GSI. Como o nosso
# sistema e assinado com a testkey da AOSP, a montagem falha e o boot morre
# antes do bootanimation.
#
# Uso: ./tools/make-vendor-boot.sh [saida]
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STOCK="$ROOT/dumps/fw-1.1.1/vendor_boot.img"
OUT="${1:-$HOME/jm21-artifacts/vendor_boot-noverity.img}"
MKBOOTIMG="$HOME/lineage20/out/host/linux-x86/bin/mkbootimg"
AVBTOOL="$HOME/lineage20/external/avb/avbtool"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT

python3 - "$STOCK" "$W" <<'PY'
import struct, sys, pathlib
d = pathlib.Path(sys.argv[1]).read_bytes()
w = pathlib.Path(sys.argv[2])
vrs = struct.unpack_from('<I', d, 24)[0]
cmdline = d[28:28+2048].split(b'\x00', 1)[0]
hsz = struct.unpack_from('<I', d, 2096)[0]
dtbsz = struct.unpack_from('<I', d, 2100)[0]
vrt_size = struct.unpack_from('<I', d, 2112)[0]
bootcfg_sz = struct.unpack_from('<I', d, 2124)[0]
page = 4096
off = ((hsz + page - 1)//page)*page
(w/'vendor_ramdisk.lz4').write_bytes(d[off:off+vrs])
off += ((vrs + page - 1)//page)*page
(w/'dtb').write_bytes(d[off:off+dtbsz] if dtbsz else b'')
off += ((dtbsz + page - 1)//page)*page
off += ((vrt_size + page - 1)//page)*page
(w/'bootconfig').write_bytes(d[off:off+bootcfg_sz] if bootcfg_sz else b'')
(w/'cmdline').write_bytes(cmdline)
print(f"ramdisk={vrs} dtb={dtbsz} bootconfig={bootcfg_sz} cmdline={cmdline.decode()}")
PY

lz4 -d -c "$W/vendor_ramdisk.lz4" > "$W/rd.cpio"
mkdir "$W/x" && (cd "$W/x" && cpio -id --quiet < "$W/rd.cpio" 2>/dev/null)

# remove a exigencia de AVB para as particoes verificadas por vbmeta_system
for f in "$W"/x/first_stage_ramdisk/fstab.*; do
    [ -f "$f" ] || continue
    sed -i -E 's/,avb=vbmeta_system//g; s/,avb_keys=[^ ]*//g' "$f"
    echo "editado: $(basename "$f") -> $(grep -c 'avb=vbmeta_system' "$f") refs a vbmeta_system"
done

(cd "$W/x" && find . -print0 | cpio --null -o -H newc --quiet > "$W/rd-new.cpio")
lz4 -l -12 --no-frame-crc -f "$W/rd-new.cpio" "$W/rd-new.lz4" >/dev/null

CMDLINE="$(cat "$W/cmdline")"
ARGS=(--header_version 4 --pagesize 4096 --base 0x00000000
      --kernel_offset 0x00008000 --ramdisk_offset 0x01000000
      --tags_offset 0x00000100 --dtb_offset 0x01f00000
      --vendor_cmdline "$CMDLINE"
      --vendor_ramdisk "$W/rd-new.lz4" --vendor_boot "$W/vb.img")
[ -s "$W/dtb" ] && ARGS+=(--dtb "$W/dtb")
[ -s "$W/bootconfig" ] && ARGS+=(--vendor_bootconfig "$W/bootconfig")
"$MKBOOTIMG" "${ARGS[@]}"
python3 "$AVBTOOL" add_hash_footer --image "$W/vb.img" --partition_name vendor_boot \
    --partition_size 100663296 --algorithm NONE >/dev/null
cp "$W/vb.img" "$OUT"
echo "OK: $OUT ($(stat -c%s "$OUT") bytes)"
