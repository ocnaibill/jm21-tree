#!/usr/bin/env bash
#
# lineage-status.sh — painel de progresso do build do LineageOS 20 para o JM21.
#
# Uso:
#   ./tools/lineage-status.sh          # retrato unico
#   ./tools/lineage-status.sh -w 30    # atualiza a cada 30s
#
TREE="${LINEAGE_TREE:-$HOME/lineage20}"
DEV="$TREE/device/fiio/jm21"
MK="$TREE/vendor/fiio/jm21/proprietary/proprietary.mk"

bar() {  # $1 = pct
    local pct=${1:-0} n=$(( ${1:-0} / 5 ))
    printf "["
    for ((i=0;i<20;i++)); do [ "$i" -lt "$n" ] && printf "#" || printf "."; done
    printf "] %3s%%" "$pct"
}

phase() {
    local unit
    unit=$(systemctl --user list-units --all --plain --no-legend 2>/dev/null \
           | grep -oE "^(lineage-build[0-9]*|fixconf[0-9]*|soong-b[0-9]*)" | tail -1)
    if [ -z "$unit" ]; then echo "parado"; return; fi
    if ! systemctl --user is-active -q "$unit"; then echo "parado (ultimo: $unit)"; return; fi
    case "$unit" in
        fixconf*) echo "resolvendo conflitos de arquivo ($unit)" ;;
        soong*)   echo "gerando build.ninja ($unit)" ;;
        *)        echo "build ($unit)" ;;
    esac
}

echo "=== LineageOS 20 / jm21 — $(date '+%H:%M:%S') ==="
echo

# --- fase
printf "fase            : %s\n" "$(phase)"

# --- progresso do ninja (ultimo log que tiver %)
LOG=""
for f in /tmp/lineage-build.log /tmp/fixconf.log /tmp/soong-b9.log /tmp/fixconf-out3.log; do
    [ -f "$f" ] && LOG="$f"
done
if [ -n "$LOG" ]; then
    last=$(grep -oE "\[ *[0-9]+% [0-9]+/[0-9]+\]" "$LOG" 2>/dev/null | tail -1)
    if [ -n "$last" ]; then
        pct=$(echo "$last" | grep -oE "[0-9]+%" | tr -d %)
        printf "ninja           : %s  %s\n" "$(bar "$pct")" "$last"
    fi
fi

# --- conflitos resolvidos e arquivos restantes
resolved=0
for f in /tmp/fixconf-out.log /tmp/fixconf-out3.log; do
    [ -f "$f" ] && resolved=$((resolved + $(grep -c "^iteracao" "$f" 2>/dev/null)))
done
printf "conflitos removidos: %s\n" "$resolved"
if [ -f "$MK" ]; then
    total=$(grep -c "^    vendor/fiio/jm21/proprietary/" "$MK" 2>/dev/null)
    printf "blobs no mk     : %s\n" "${total:-0}"
fi

# --- patches aplicados
if [ -d "$TREE/frameworks/base/.git" ]; then
    n=$(git -C "$TREE/frameworks/base" diff --stat 2>/dev/null | tail -1 | grep -oE "^ *[0-9]+ files?" | grep -oE "[0-9]+")
    printf "patches aplicados: %s arquivo(s) alterados no frameworks/base\n" "${n:-0}"
fi

# --- disco e memoria
printf "disco livre     : %s\n" "$(df -h /home | awk 'NR==2{print $4}')"
printf "mem / swap      : %s / %s\n" \
    "$(free -h | awk '/^Mem/{print $3" de "$2}')" \
    "$(free -h | awk '/^Swap/{print $3" de "$2}')"

# --- ultimo evento relevante
if [ -n "$LOG" ]; then
    echo
    echo "--- ultimas linhas ($LOG):"
    grep -E "^FAILED|error:|removido|build stopped|SUCESSO|####" "$LOG" 2>/dev/null | tail -4
fi

# --- artefatos
echo
if [ -f "$TREE/out/target/product/jm21/lineage_jm21-ota.zip" ]; then
    echo ">>> OTA gerada: $(ls -lh "$TREE/out/target/product/jm21/lineage_jm21-ota.zip" | awk '{print $5}')"
elif [ -f "$TREE/out/target/product/jm21/system.img" ]; then
    echo ">>> system.img gerada: $(ls -lh "$TREE/out/target/product/jm21/system.img" | awk '{print $5}')"
else
    echo ">>> nenhuma imagem gerada ainda"
fi

# modo watch
if [ "${1:-}" = "-w" ]; then
    while true; do sleep "${2:-30}"; clear; exec "$0"; done
fi
