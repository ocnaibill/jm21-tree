#!/usr/bin/env bash
# recovery-tool.sh — backup/restore/flash de partições com o aparelho no RECOVERY
# (adb root; nao precisa de su, ao contrario do full-clone.sh).
#
# Uso:
#   ./tools/recovery-tool.sh check
#   ./tools/recovery-tool.sh backup <dir> [--boot|--all|<part> ...]
#   ./tools/recovery-tool.sh restore <dir> [--yes]
#   ./tools/recovery-tool.sh flash <particao> <imagem> [--yes]
#   ./tools/recovery-tool.sh shell '<cmd>'
#
# '--boot' (default): boot, init_boot, dtbo, vendor_boot, vbmeta, recovery,
#   vbmeta_system + bootloader (xbl, abl) do slot atual.
# '--all': todas as 94 partições (pode ser dezenas de GB).
set -euo pipefail
cd "$(dirname "$0")/.."

ADB=(adb)
SERIAL="${SERIAL:-}"
[[ -n "$SERIAL" ]] && ADB=(adb -s "$SERIAL")

die() { echo "erro: $*" >&2; exit 1; }

state() { "${ADB[@]}" devices | awk 'NR>1 && $2!=""{print $2}' | head -1; }

require_root() {
  local st; st=$(state)
  [[ "$st" == "recovery" || "$st" == "device" ]] || die "aparelho nao encontrado (estado: ${st:-nenhum})"
  "${ADB[@]}" root >/dev/null 2>&1 || true
  sleep 2
  local id; id=$("${ADB[@]}" shell id 2>/dev/null | tr -d '\r')
  [[ "$id" == *"uid=0"* ]] || die "sem root no adb (id: $id). Em recovery, precisa de ro.debuggable=1 no ramdisk."
  echo "ok: root ($id)"
}

slot() { "${ADB[@]}" shell getprop ro.boot.slot_suffix 2>/dev/null | tr -d '\r'; }

part_size() {
  "${ADB[@]}" shell "blockdev --getsize64 /dev/block/by-name/$1" 2>/dev/null | tr -d '\r'
}

list_parts() { "${ADB[@]}" shell 'ls /dev/block/by-name' 2>/dev/null | tr -d '\r'; }

backup_one() { # $1 = particao, $2 = dir
  local name=$1 out=$2 img="$2/${1}.img" sz
  sz=$(part_size "$name") || die "particao $name nao existe"
  [[ -z "$sz" || "$sz" == "0" ]] && { echo "  pulando $name (vazia)"; return 0; }
  echo "  $name ($sz bytes)"
  "${ADB[@]}" exec-out "dd if=/dev/block/by-name/$name bs=1M 2>/dev/null" > "$img"
  local got; got=$(stat -c%s "$img")
  [[ "$got" == "$sz" ]] || die "tamanho divergente em $name: $got != $sz"
  ( cd "$2" && sha256sum "$(basename "$img")" >> SHA256SUMS )
}

cmd_check() { require_root; echo "slot: $(slot)"; echo "particoes: $(list_parts | wc -l)"; }

cmd_backup() {
  local dir=${1:?uso: backup <dir> [--boot|--all|parts...]}; shift || true
  require_root
  mkdir -p "$dir"
  : > "$dir/SHA256SUMS"
  local parts=()
  if [[ $# -eq 0 || "$1" == "--boot" ]]; then
    local s; s=$(slot)
    parts=(boot${s} init_boot${s} dtbo${s} vendor_boot${s} vbmeta${s} recovery${s} vbmeta_system${s} xbl${s} abl${s})
  elif [[ "$1" == "--all" ]]; then
    mapfile -t parts < <(list_parts)
  else
    parts=("$@")
  fi
  echo "backup para $dir (${#parts[@]} particoes)"
  for p in "${parts[@]}"; do backup_one "$p" "$dir"; done
  { echo "device: $( "${ADB[@]}" shell getprop ro.serialno | tr -d '\r')";
    echo "slot: $(slot)"; echo "date: $(date -Iseconds)"; } > "$dir/MANIFEST.txt"
  echo "ok: $(sha256sum "$dir"/*.img | wc -l) arquivos, hashes em $dir/SHA256SUMS"
}

cmd_restore() {
  local dir=${1:?uso: restore <dir> [--yes]}; shift || true
  require_root
  [[ -f "$dir/SHA256SUMS" ]] || die "sem SHA256SUMS em $dir"
  ( cd "$dir" && sha256sum -c SHA256SUMS ) || die "hash divergente; abortando"
  echo "As particoes abaixo serao regravadas:"
  ls "$dir"/*.img | xargs -n1 basename
  read -r -p "confirma? (digite SIM) " a; [[ "$a" == "SIM" ]] || die "abortado"
  for img in "$dir"/*.img; do
    local p; p=$(basename "$img" .img)
    echo "gravando $p"
    "${ADB[@]}" push "$img" /tmp/r.img >/dev/null
    "${ADB[@]}" shell "dd if=/tmp/r.img of=/dev/block/by-name/$p bs=1M 2>/dev/null; sync; rm -f /tmp/r.img"
  done
  echo "ok: restore concluido"
}

cmd_flash() {
  local part=${1:?uso: flash <particao> <imagem> [--yes]} img=${2:?falta a imagem}; shift 2 || true
  require_root
  [[ -f "$img" ]] || die "imagem nao existe: $img"
  local psz isz; psz=$(part_size "$part") || die "particao $part nao existe"
  isz=$(stat -c%s "$img")
  [[ "$isz" -le "$psz" ]] || die "imagem ($isz) maior que a particao ($psz)"
  echo "$part: imagem $isz / particao $psz"
  read -r -p "gravar $img em $part? (digite SIM) " a; [[ "$a" == "SIM" ]] || die "abortado"
  "${ADB[@]}" push "$img" /tmp/f.img >/dev/null
  "${ADB[@]}" shell "dd if=/tmp/f.img of=/dev/block/by-name/$part bs=1M 2>/dev/null; sync; rm -f /tmp/f.img"
  echo "ok: $part gravada"
}

cmd_shell() { require_root; "${ADB[@]}" shell "$@"; }

case "${1:-}" in
  check) shift; cmd_check "$@" ;;
  backup) shift; cmd_backup "$@" ;;
  restore) shift; cmd_restore "$@" ;;
  flash) shift; cmd_flash "$@" ;;
  shell) shift; cmd_shell "$@" ;;
  *) sed -n '2,20p' "$0"; exit 1 ;;
esac
