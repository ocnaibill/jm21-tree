#!/usr/bin/env bash
# build-recovery.sh — gera a imagem de recovery do JM21 (kernel-less) com:
#   1) init.recovery.qcom.rc: "on early-init / write /sys/fs/selinux/enforce 0"
#   2) policy: allow init kernel:security setenforce
#              allow adbd shell:process setcurrent
#   3) prop.default: ro.debuggable=1, ro.secure=0 (adb root no recovery)
#
# Uso: ./tools/build-recovery.sh [saida.img]   (default: /tmp/recovery-jm21.img)
# Requer: dumps/fw-1.1.1/recovery.img, gcc + libsepol.a, python3, lz4, mkbootimg.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${1:-/tmp/recovery-jm21.img}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

echo "== 1. extraindo o recovery stock =="
unpack_bootimg --boot_img dumps/fw-1.1.1/recovery.img --out "$W/rec" >/dev/null
lz4 -d "$W/rec/ramdisk" "$W/ramdisk.cpio" >/dev/null

echo "== 2. compilando o sepolicy-patch =="
gcc -O2 -o "$W/sepolicy-patch" tools/sepolicy-patch.c /usr/lib/libsepol.a -lpthread

echo "== 3. extraindo a sepolicy do ramdisk =="
python3 - "$W/ramdisk.cpio" "$W/sepolicy.orig" <<'PY'
import struct, sys
src=open(sys.argv[1],'rb').read(); pos=0; data=None
while pos < len(src):
    hdr=src[pos:pos+110]
    if len(hdr)<110 or hdr[:6]!=b'070701': break
    f=[int(hdr[6+i*8:14+i*8],16) for i in range(13)]
    fsize=f[6]; nsize=f[11]; pos+=110
    name=src[pos:pos+nsize-1].decode('latin1'); pos+=nsize
    pos=(pos+3)&~3
    if name=='sepolicy': data=src[pos:pos+fsize]
    pos+=fsize; pos=(pos+3)&~3
    if name=='TRAILER!!!': break
assert data, 'sepolicy nao encontrada no ramdisk'
open(sys.argv[2],'wb').write(data)
print('sepolicy', len(data), 'bytes')
PY

echo "== 4. aplicando as regras =="
"$W/sepolicy-patch" "$W/sepolicy.orig" "$W/sepolicy.p1" init kernel security setenforce
"$W/sepolicy-patch" "$W/sepolicy.p1" "$W/sepolicy.p2" adbd shell process setcurrent

echo "== 5. rebuild do cpio (rc + prop + policy) =="
python3 - "$W/ramdisk.cpio" "$W/sepolicy.p2" "$W/ramdisk.new.cpio" <<'PY'
import struct, sys
src=open(sys.argv[1],'rb').read(); pol=open(sys.argv[2],'rb').read()
pos=0; entries=[]; trailer=b''
while True:
    hdr=src[pos:pos+110]
    if len(hdr)<110 or hdr[:6]!=b'070701': break
    f=[int(hdr[6+i*8:14+i*8],16) for i in range(13)]
    fsize=f[6]; nsize=f[11]; start=pos; pos+=110
    name=src[pos:pos+nsize-1].decode('latin1'); pos+=nsize
    pos=(pos+3)&~3
    data=src[pos:pos+fsize]; pos+=fsize; pos=(pos+3)&~3
    if name=='TRAILER!!!': trailer=src[start:pos]; break
    entries.append([hdr,name,data])
def mk(hdr,name,data):
    b=bytearray(hdr); b[54:62]=b'%08X'%len(data)
    n=name.encode()+b'\0'; b[94:102]=b'%08X'%len(n)
    return bytes(b)+n+b'\0'*((4-(110+len(n))%4)%4)+data+b'\0'*((4-len(data)%4)%4)
res=b''
for hdr,name,data in entries:
    if name=='sepolicy': data=pol
    elif name=='init.recovery.qcom.rc':
        t=data.decode('latin1')
        if 'enforce 0' not in t:
            t="on early-init\n    write /sys/fs/selinux/enforce 0\n\n"+t
        data=t.encode('latin1')
    elif name=='prop.default':
        t=data.decode('latin1')
        if 'ro.debuggable=1' not in t: t+="\nro.debuggable=1\nro.secure=0\n"
        data=t.encode('latin1')
    res+=mk(hdr,name,data)
res+=trailer
open(sys.argv[3],'wb').write(res)
print('cpio', len(res), 'bytes')
PY

echo "== 6. comprimindo (LZ4 legacy) e montando a imagem (sem kernel) =="
lz4 -l -12 -f "$W/ramdisk.new.cpio" "$W/ramdisk.new.lz4" >/dev/null
mkbootimg --ramdisk "$W/ramdisk.new.lz4" --header_version 4 \
  --os_version 13.0.0 --os_patch_level 2023-02 --pagesize 4096 --output "$OUT"

echo "ok: $OUT ($(stat -c%s "$OUT") bytes)"
echo "flash: fastboot flash recovery_a $OUT && adb reboot recovery"
echo "depois: adb root && ./tools/recovery-tool.sh check"
