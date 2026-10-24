#!/usr/bin/env bash
# Clone completo do JM21 para o host, em streaming (não ocupa /data no aparelho).
#
# Uso: tools/full-clone.sh [dir_saida]
#   SKIP="userdata metadata"  partições a pular (default: userdata)
#   SERIAL=...                seleciona o aparelho (default: adb -d)
#
# Gera <dir>/<partição>.img, <dir>/SHA256SUMS e <dir>/MANIFEST.txt.
# É idempotente: partições já clonadas (e com hash no manifesto) são puladas.

set -u
OUT="${1:-device-baseline/clone}"
SKIP="${SKIP-userdata}"
SERIAL="${SERIAL:-}"

ADB=(adb)
[ -n "$SERIAL" ] && ADB+=(-s "$SERIAL") || ADB+=(-d)

mkdir -p "$OUT"
MAN="$OUT/MANIFEST.txt"
[ -f "$MAN" ] || echo "# partição tamanho_esperado sha256" > "$MAN"

echo "== listando partições =="
PARTS=$("${ADB[@]}" shell 'ls /dev/block/by-name/' | tr -d '\r' | sort)

for name in $PARTS; do
    case " $SKIP " in *" $name "*) echo "-- pulando $name (SKIP)"; continue ;; esac
    img="$OUT/$name.img"
    if [ -f "$img" ] && grep -q "^$name " "$MAN" 2>/dev/null; then
        echo "-- $name já clonado"
        continue
    fi
    # tamanho em bytes (bloco do device)
    size=$("${ADB[@]}" shell "su -c 'blockdev --getsize64 /dev/block/by-name/$name'" 2>/dev/null | tr -d '\r')
    printf "== %-22s %12s bytes\n" "$name" "${size:-?}"
    if ! "${ADB[@]}" exec-out su -c "dd if=/dev/block/by-name/$name bs=1M 2>/dev/null" > "$img"; then
        echo "   FALHOU"; rm -f "$img"; continue
    fi
    got=$(stat -c %s "$img")
    if [ -n "$size" ] && [ "$got" != "$size" ]; then
        echo "   AVISO: tamanho lido $got != esperado $size"
    fi
    h=$(sha256sum "$img" | cut -d' ' -f1)
    echo "$name $got $h" >> "$MAN"
    echo "   ok $h"
done

sha256sum "$OUT"/*.img > "$OUT/SHA256SUMS"
echo "== pronto: $OUT =="
du -sh "$OUT"
