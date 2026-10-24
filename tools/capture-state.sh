#!/usr/bin/env bash
# Snapshot READ-ONLY do estado de audio do JM21, para comparar cenarios.
# Uso: ./tools/capture-state.sh <rotulo>
# Saida: device-baseline/<timestamp>-<rotulo>/estado.txt

set -u
LABEL="${1:-snapshot}"
OUT="device-baseline/$(date +%Y%m%d-%H%M%S)-$LABEL"
mkdir -p "$OUT"
F="$OUT/estado.txt"

{
  echo "# JM21 — $LABEL — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "## sysfs (fiio_attr)"
  adb shell 'for f in dac_vol board_vol_dac headset_type board_output_type board_dac_dre_switch board_is_pause_by_headset; do printf "%s=" "$f"; cat /sys/devices/platform/soc/soc:fiio_attr/$f 2>/dev/null; echo; done'
  echo
  echo "## fpga_config"
  adb shell 'cat /sys/devices/platform/soc/soc:fiio_attr/fpga_config 2>/dev/null'
  echo
  echo "## hw_params ativos"
  adb shell 'for p in /proc/asound/card0/pcm*/sub0/hw_params; do s=$(cat $p 2>/dev/null); [ -n "$s" ] && echo "$p: $s"; done'
  echo
  echo "## media_session (fiio.music)"
  adb shell 'dumpsys media_session | grep -A2 "package=com.fiio.music" | grep -E "state=|package="'
  echo
  echo "## AudioFlinger: threads fora de standby"
  adb shell 'dumpsys media.audio_flinger' | awk '/Output thread/{blk=$0} /Standby: no/{print blk; print; found=1} END{if(!found) print "(nenhum)"}'
  echo
  echo "## AudioFlinger: taxa/formato do(s) thread(s) ativo(s)"
  adb shell 'dumpsys media.audio_flinger' | grep -E "Output thread|Standby:|Sample rate:|HAL format:|HAL frame count:|Flags:" | head -60
  echo
  echo "## logcat fiioaudio/fiiodevice"
  adb shell 'logcat -d -s fiioaudio fiodevice' | tail -40
  echo
  echo "## dmesg dac/headset (ultimas)"
  adb shell 'dmesg | grep -i -E "headset_notifier|HEADSET_|cs43198|anolog_board" | tail -15'
} >"$F" 2>&1

echo "salvo em $F"
grep -E "^(dac_vol|board_vol_dac|headset_type|board_output_type)=" "$F"
grep -A1 "## hw_params" "$F" | tail -1
