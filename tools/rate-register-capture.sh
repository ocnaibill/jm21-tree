#!/usr/bin/env bash
# Captura minima: para cada configuracao de stream, le APENAS o registrador de
# taxa (SP_SRATE = 0x1000B) com 1 s de estabilizacao, e o codigo do FPGA no
# dmesg. Evita o lag de leituras em sequencia rapida.
#
# Uso: ./tools/rate-register-capture.sh [segundos]

set -u
DUR="${1:-1200}"
ATTR=/sys/devices/platform/soc/soc:fiio_attr
OUT="device-baseline/rate-$(date +%Y%m%d-%H%M%S).txt"
mkdir -p device-baseline

read_one() {  # read_one <decimal>
  adb shell "su -c \"echo $1 > $ATTR/dac_read_reg; sleep 1; cat $ATTR/dac_read_reg\"" 2>/dev/null | tr -d '\r'
}

adb logcat -c 2>/dev/null
echo "# rate-capture iniciado $(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$OUT"

timeout "$DUR" adb logcat -s fiioaudio 2>/dev/null | while IFS= read -r line; do
  case "$line" in
    *match_audio_hardware_params*)
      sleep 1.5
      rate=$(read_one 65547)
      echo "=== $(date -u +%H:%M:%S) 0x1000B=$rate" >>"$OUT"
      echo "    ${line#*fiioaudio: }" >>"$OUT"
      adb shell 'dmesg | grep "fpga_i2c_write, reg = 0x02" | tail -1' 2>/dev/null \
        | sed 's/^/    /' >>"$OUT"
      ;;
  esac
done

echo "# rate-capture encerrado $(date -u +%Y-%m-%dT%H:%M:%SZ)" >>"$OUT"
echo "salvo em $OUT"
