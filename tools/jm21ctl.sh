#!/usr/bin/env bash
# jm21ctl — controle do FiiO JM21 por adb (root) usando as interfaces já mapeadas:
# kcontrols ALSA, sysfs soc:fiio_attr (dac_ctrl / dac_read_reg) e keyevents de volume.
#
# Uso: ./jm21ctl.sh [-s SERIAL] <comando> [args]
#   status                 resumo (volume, ganho, filtro, taxa, modo, saída)
#   vol [get|set N|+N|-N]  volume da música (via keyevents do framework)
#   gain [get|set 0|1|2]   DAC PO Gain (baixo/médio/alto)
#   filter [get|set 0..4]  DAC Digital Filter Mode
#   balance [get|set 0..40] DAC LR Balance (20 = centro)
#   lineout [get|set N]    DAC line Out Volume
#   thdc2 [get|set N]      DAC THD C2
#   reg read 0xADDR        lê um registrador nos dois chips (via dac_ctrl)
#   reg dump [N]           read_all_regs, mostra as N últimas linhas
#   rate                   taxa no DAC (0x1000B), código do FPGA e linha da HAL

set -u
SERIAL="${JM21_SERIAL:-}"
[ "${1:-}" = "-s" ] && { SERIAL="$2"; shift 2; }

ADB=(adb)
[ -n "$SERIAL" ] && ADB+=( -s "$SERIAL" ) || ADB+=( -d )

die() { echo "erro: $*" >&2; exit 1; }
sh_() { "${ADB[@]}" shell "$@"; }
root_() { "${ADB[@]}" shell "su -c '$1'"; }

ATTR=/sys/devices/platform/soc/soc:fiio_attr

kctl_get() {
  root_ "tinymix -D 0 \"$1\"" 2>/dev/null | awk -F': ' '{print $2}' | awk '{print $1}'
}
kctl_set() {
  root_ "tinymix -D 0 \"$1\" $2" >/dev/null 2>&1
}

reg_read_dec() {
  root_ "echo $1 > $ATTR/dac_read_reg; sleep 1; cat $ATTR/dac_read_reg" 2>/dev/null | tail -1
}

vol_now() { kctl_get "DAC Playback Volume"; }

cmd_status() {
  local v g f b r fpga hal
  v=$(vol_now); g=$(kctl_get "DAC PO Gain"); f=$(kctl_get "DAC Digital Filter Mode")
  b=$(kctl_get "DAC LR Balance"); r=$(reg_read_dec 65547)
  fpga=$(sh_ "dmesg | grep 'reg = 0x02' | tail -1" 2>/dev/null | sed 's/.*data = //;s/,.*//')
  hal=$(sh_ "logcat -d -s fiioaudio | grep match_audio_hardware_params | tail -1" 2>/dev/null | sed 's/.*match_audio_hardware_params: //')
  echo "volume (UI) : ${v:-?}"
  echo "PO gain     : ${g:-?}  (0=baixo 1=médio 2=alto)"
  echo "filtro      : ${f:-?}"
  echo "balanço     : ${b:-?}  (20 = centro)"
  echo "0x1000B     : ${r:-?}  (1=44.1k 2=48k 3=88.2k 4=96k 5=176.4k 6=192k 7=352.8k 8=384k)"
  echo "FPGA reg 0x02: ${fpga:-?}"
  echo "HAL         : ${hal:-<sem stream>}"
  echo "saída       : $(sh_ 'getprop fiio.current.play.device' 2>/dev/null)"
}

cmd_vol() {
  local op="${1:-get}" cur target delta i
  cur=$(vol_now)
  [ -z "$cur" ] && die "não consegui ler o volume"
  case "$op" in
    get) echo "$cur"; return ;;
    set) target="${2:-}" ;;
    +*) target=$((cur + ${op#+})) ;;
    -*) target=$((cur - ${op#-})) ;;
    *) die "uso: vol [get|set N|+N|-N]" ;;
  esac
  [ -z "$target" ] && die "uso: vol set N"
  [ "$target" -lt 0 ] && target=0
  [ "$target" -gt 120 ] && target=120
  delta=$((target - cur))
  if [ "$delta" -gt 0 ]; then
    for i in $(seq 1 "$delta"); do sh_ "input keyevent 24" >/dev/null 2>&1; sleep 0.15; done
  elif [ "$delta" -lt 0 ]; then
    for i in $(seq 1 $((-delta))); do sh_ "input keyevent 25" >/dev/null 2>&1; sleep 0.15; done
  fi
  sleep 1
  echo "$(vol_now)"
}

cmd_kctl() {
  local name="$1" op="$2" val="$3"
  case "${op:-get}" in
    get) kctl_get "$name" ;;
    set) [ -z "${val:-}" ] && die "uso: $name set VALOR"; kctl_set "$name" "$val"; sleep 0.5; kctl_get "$name" ;;
    *) die "uso: get|set" ;;
  esac
}

cmd_reg() {
  case "${1:-}" in
    read)
      local a="${2:-}"; [ -z "$a" ] && die "uso: reg read 0xADDR"
      root_ "echo $((a)) > $ATTR/dac_read_reg; sleep 1; cat $ATTR/dac_read_reg" 2>/dev/null | tail -1
      ;;
    dump)
      local n="${2:-120}"
      root_ "echo read_all_regs > $ATTR/dac_ctrl" >/dev/null 2>&1
      sleep 2
      sh_ "dmesg | grep -iE 'CS43198.*read reg' | tail -n $n"
      ;;
    *) die "uso: reg read 0xADDR | reg dump [N]" ;;
  esac
}

cmd_rate() {
  local r fpga hal
  r=$(reg_read_dec 65547)
  fpga=$(sh_ "dmesg | grep 'reg = 0x02' | tail -1" 2>/dev/null | sed 's/.*data = //;s/,.*//')
  hal=$(sh_ "logcat -d -s fiioaudio | grep match_audio_hardware_params | tail -1" 2>/dev/null | sed 's/.*match_audio_hardware_params: //')
  echo "0x1000B : ${r:-?}"
  echo "FPGA    : ${fpga:-?}"
  echo "HAL     : ${hal:-<sem stream>}"
}

case "${1:-}" in
  status)  cmd_status ;;
  vol)     shift; cmd_vol "$@" ;;
  gain)    shift; cmd_kctl "DAC PO Gain" "${1:-get}" "${2:-}" ;;
  filter)  shift; cmd_kctl "DAC Digital Filter Mode" "${1:-get}" "${2:-}" ;;
  balance) shift; cmd_kctl "DAC LR Balance" "${1:-get}" "${2:-}" ;;
  lineout) shift; cmd_kctl "DAC line Out Volume" "${1:-get}" "${2:-}" ;;
  thdc2)   shift; cmd_kctl "DAC THD C2" "${1:-get}" "${2:-}" ;;
  reg)     shift; cmd_reg "$@" ;;
  rate)    cmd_rate ;;
  *) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//' ; exit 1 ;;
esac
