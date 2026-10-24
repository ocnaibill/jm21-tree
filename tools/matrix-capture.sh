#!/usr/bin/env bash
# Escuta o log da HAL e fotografa o estado do DAC/FPGA a cada configuracao de
# stream. Usado na matriz de estados (P1). Nao escreve no aparelho alem de
# definir o registrador a ser lido no sysfs de debug.
#
# Uso: ./tools/matrix-capture.sh [segundos]
# Saida: device-baseline/matrix-<timestamp>.txt

set -u
DUR="${1:-1200}"
ATTR=/sys/devices/platform/soc/soc:fiio_attr
OUT="device-baseline/matrix-$(date +%Y%m%d-%H%M%S).txt"
mkdir -p device-baseline

snapshot() {
  {
    adb shell "su -c \"printf '  sysfs: vol=%s board=%s hs=%s ot=%s\\n' \
      \$(cat $ATTR/dac_vol) \$(cat $ATTR/board_vol_dac) \
      \$(cat $ATTR/headset_type) \$(cat $ATTR/board_output_type)\"" 2>/dev/null
    adb shell "su -c \"echo '  fpga :'\$(cat $ATTR/fpga_config)\"" 2>/dev/null
    # leitura de registrador: escreve, espera o store propagar, le
    adb shell "su -c \"for r in 589826 589825 589824 524288 131072; do \
      echo \\\$r > $ATTR/dac_read_reg; sleep 0.2; printf '  reg 0x%05x=' \\\$r; \
      cat $ATTR/dac_read_reg; done\"" 2>/dev/null
    adb shell 'dumpsys media.audio_flinger' 2>/dev/null \
      | awk '/Standby: no/{f=1} f&&/Sample rate|HAL format/{printf "  flinger: %s\n",$0; {sub(/^ +/,""); print "  flinger: " $0}}' | head -2
  } >>"$OUT"
}

adb logcat -c 2>/dev/null
echo "# matriz iniciada $(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$OUT"

timeout "$DUR" adb logcat -s fiioaudio 2>/dev/null | while IFS= read -r line; do
  case "$line" in
    *match_audio_hardware_params*)
      echo "=== $(date -u +%H:%M:%S) ${line#*fiioaudio: }" >>"$OUT"
      snapshot
      ;;
  esac
done

echo "# matriz encerrada $(date -u +%Y-%m-%dT%H:%M:%SZ)" >>"$OUT"
echo "salvo em $OUT"
