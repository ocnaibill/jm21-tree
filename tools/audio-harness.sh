#!/usr/bin/env bash
# audio-harness.sh - carrega o techpack de audio do vendor_dlkm dentro do TWRP
# e verifica se a placa de som (bengal_snd) nasce. Experimento 1 da issue #13
# (docs/48 secao 8).
#
# Uso: tools/audio-harness.sh          (TWRP precisa estar rodando, adb = recovery)
#      tools/audio-harness.sh --check  (so verifica o estado atual)

set -o pipefail

# Ordem OFICIAL, lida de /vendor/lib/modules/modules.load no Android
# (linhas 111..187 do arquivo). Nao e chute: e o que o proprio Android faz.
ORDER=(
  qcom_q6v5 qcom_q6v5_pas
  q6_notifier_dlkm spf_core_dlkm audio_pkt_dlkm q6_dlkm adsp_loader_dlkm
  audio_prm_dlkm q6_pdr_dlkm
  swr_dlkm swr_ctrl_dlkm wcd_core_dlkm wcd9xxx_dlkm machine_dlkm
  bolero_cdc_dlkm wcd937x_dlkm wcd937x_slave_dlkm
)

say() { echo "[$(date +%H:%M:%S)] $*"; }

state=$(timeout 5 adb get-state 2>/dev/null)
if [ "$state" != "recovery" ]; then
  say "adb esta em '$state' — precisa estar em 'recovery' (TWRP)."
  say "faca: adb reboot recovery"
  exit 1
fi

say "TWRP: $(adb shell getprop ro.twrp.version | tr -d '\r')"

# --- localiza/monta vendor_dlkm ---
# o vendor_dlkm monta em /vendor/lib/modules (e o firmware do ADSP fica em
# /vendor/firmware, que vem da particao vendor)
adb shell 'mount | grep -q " /vendor/lib/modules " || { mkdir -p /vendor/lib/modules; dev=$(ls /dev/block/mapper/vendor_dlkm* 2>/dev/null | head -1); [ -n "$dev" ] && mount -o ro "$dev" /vendor/lib/modules; }' >/dev/null 2>&1

moddir=$(adb shell 'ls -d /vendor/lib/modules 2>/dev/null | head -1' | tr -d '\r')
if [ -z "$moddir" ]; then
  say "FALHA: vendor_dlkm nao montado em /vendor/lib/modules"
  adb shell 'mount | grep -E "vendor|dlkm"; ls /dev/block/mapper | grep -i dlkm'
  exit 1
fi
say "modulos em: $moddir ($(adb shell "ls $moddir | wc -l" | tr -d '\r') arquivos)"

say "--- antes: placas de som conhecidas"
adb shell 'cat /proc/asound/cards 2>/dev/null || echo "(sem /proc/asound)"' | sed 's/^/    /'

if [ "${1:-}" = "--check" ]; then
  adb shell 'dmesg | grep -iE "asoc|bengal_snd|snd-card" | tail -10' | sed 's/^/    /'
  exit 0
fi

# --- carrega em ordem ---
for m in "${ORDER[@]}"; do
  if adb shell "ls $moddir/$m.ko" >/dev/null 2>&1; then
    out=$(adb shell "insmod $moddir/$m.ko 2>&1" | tr -d '\r')
    if [ -z "$out" ]; then
      say "OK   $m"
    else
      say "ERRO $m: $out"
    fi
    sleep 0.3
  else
    say "SKIP $m (nao existe no vendor_dlkm)"
  fi
done

say "--- depois: placas de som"
adb shell 'cat /proc/asound/cards 2>/dev/null || echo "(sem /proc/asound)"' | sed 's/^/    /'

say "--- dmesg (asoc/pcm/snd):"
adb shell 'dmesg | grep -iE "asoc|bengal_snd|snd|adsp|q6v5" | tail -25' | sed 's/^/    /'

say "--- modules carregados:"
adb shell 'cat /proc/modules | awk "{print \$1}" | grep -E "dlkm|q6|adsp|bolero|wcd|swr|machine" ' | sed 's/^/    /'
