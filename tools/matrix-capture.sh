#!/usr/bin/env bash
# Escuta o log da HAL e fotografa o estado do DAC/FPGA a cada configuracao de
# stream. Rodada 2 (P1b): inclui os registradores que variam com a taxa e o
# dmesg do FPGA.
#
# Uso: ./tools/matrix-capture.sh [segundos]
# Saida: device-baseline/matrix-<timestamp>.txt

set -u
DUR="${1:-1500}"
ATTR=/sys/devices/platform/soc/soc:fiio_attr
OUT="device-baseline/matrix-$(date +%Y%m%d-%H%M%S).txt"
mkdir -p device-baseline

# decimais: 0x90002,0x90001,0x90000,0x80000,0x20000,0x10006,
#           0x40010-0x40019,0x5000A,0x5000B,0x70000,0x70001,0x20052
REG="589826 589825 589824 524288 131072 65542 65547 65548 262160 262161 262162 262163 262164 262165 262166 262167 262168 262169 327690 327691 458752 458753 131154"

snapshot() {
  {
    adb shell "su -c \"printf '  sysfs: vol=%s board=%s hs=%s ot=%s\\n' \
      \$(cat $ATTR/dac_vol) \$(cat $ATTR/board_vol_dac) \
      \$(cat $ATTR/headset_type) \$(cat $ATTR/board_output_type)\"" 2>/dev/null
    adb shell "su -c \"echo '  fpga-cache:'\$(cat $ATTR/fpga_config)\"" 2>/dev/null
    adb shell "su -c \"for r in $REG; do \
      echo \\\$r > $ATTR/dac_read_reg; sleep 0.15; printf '  reg 0x%05x=' \\\$r; \
      cat $ATTR/dac_read_reg; done\"" 2>/dev/null
    adb shell 'dmesg | grep -E "fpga_set_mclk|fpga_fill_clk|fpga_i2c_write" | tail -4' 2>/dev/null \
      | sed 's/^/  dmesg:/'
  } >>"$OUT"
}

adb logcat -c 2>/dev/null
echo "# matriz P1b iniciada $(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$OUT"

timeout "$DUR" adb logcat -s fiioaudio 2>/dev/null | while IFS= read -r line; do
  case "$line" in
    *match_audio_hardware_params*)
      echo "=== $(date -u +%H:%M:%S) ${line#*fiioaudio: }" >>"$OUT"
      snapshot
      ;;
  esac
done

echo "# matriz P1b encerrada $(date -u +%Y-%m-%dT%H:%M:%SZ)" >>"$OUT"
echo "salvo em $OUT"
