#!/usr/bin/env bash
# Coleta baseline READ-ONLY do FiiO JM21 via adb.
# Nao escreve nada no aparelho. Nao usa root por padrao (--root para os nos protegidos).
#
# Uso:  ./tools/collect-baseline.sh [--root]
# Saida: device-baseline/<timestamp>/

set -u

USE_ROOT=0
[ "${1:-}" = "--root" ] && USE_ROOT=1

OUT="device-baseline/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"
LOG="$OUT/_collect.log"

say() { printf '%s\n' "$*" | tee -a "$LOG"; }

run() {  # run <arquivo> <comando...>
  local f="$OUT/$1"; shift
  say "== $f : $*"
  if [ "$USE_ROOT" = "1" ]; then
    adb shell "su -c '$*'" >"$f" 2>&1
  else
    adb shell "$@" >"$f" 2>&1
  fi
  [ -s "$f" ] || echo "(vazio ou erro)" >>"$f"
  return 0
}

command -v adb >/dev/null || { echo "adb nao encontrado"; exit 1; }

say "Baseline JM21 — $(date -u +%Y-%m-%dT%H:%M:%SZ) — root=$USE_ROOT"

# --- estado do aparelho ---
adb devices -l >"$OUT/adb-devices.txt" 2>&1
if ! adb shell true >/dev/null 2>&1; then
  say "ERRO: adb nao responde. Autorize a depuracao USB ou instale a regra udev."
  exit 2
fi

run getprop.txt        getprop
run build.txt          "getprop | grep -E 'ro.build|ro.product|ro.vendor.build'"
run selinux.txt        getenforce
run boot-state.txt     "getprop ro.boot.verifiedbootstate; getprop ro.boot.flash.locked; getprop ro.boot.veritymode"
run version.txt        "getprop ro.product.version; getprop ro.product.ota.package_name"

# --- áudio: estado vivo ---
run asound-cards.txt   "cat /proc/asound/cards"
run asound-pcm.txt     "cat /proc/asound/pcm"
run asound-devices.txt "cat /proc/asound/devices"
run audio-flinger.txt  "dumpsys media.audio_flinger"
run audio-policy.txt   "dumpsys media.audio_policy"
run audio-service.txt  "dumpsys audio"
run tinymix.txt        "tinymix -D 0 2>/dev/null || tinymix 2>/dev/null || echo 'tinymix ausente'"
run props-audio.txt    "getprop | grep -iE 'fiio|audio|dsd|dac|mqa|uac|fpga'"

# --- HR params ao vivo (se algo estiver tocando) ---
run hwparams.txt       "for f in /proc/asound/card*/pcm*p/sub0/hw_params; do echo \"--- \$f\"; cat \$f; done"

# --- módulos e kernel ---
run lsmod.txt          "lsmod | grep -iE 'fiio|cs43|snd|fpga|aw22'"
run kallsyms-fiio.txt  "grep -iE ' (fiio|snd_dac|cs43198)' /proc/kallsyms"
run dmesg-audio.txt    "dmesg | grep -iE 'cs43198|dac_core|anolog_board|fiio|fpga|headset'"
run cmdline.txt        "cat /proc/cmdline"
run version-kernel.txt "cat /proc/version"

# --- sysfs: a API (docs/18) ---
run fiio-attr-list.txt "ls -l /sys/devices/platform/soc/soc:fiio_attr/"
run fiio-attr-values.txt "for f in /sys/devices/platform/soc/soc:fiio_attr/*; do echo \"--- \$f\"; cat \$f 2>/dev/null; done"
run gpio.txt           "cat /sys/kernel/debug/gpio"
run regulator.txt      "cat /sys/kernel/debug/regulator/regulator_summary"
run i2c-devices.txt    "ls -l /sys/bus/i2c/devices/"
run i2c-names.txt      "for d in /sys/bus/i2c/devices/*; do echo \"\$d: \$(cat \$d/name 2>/dev/null)\"; done"

# --- device tree aplicada ---
run dt-model.txt       "cat /proc/device-tree/model; echo; cat /proc/device-tree/compatible"
run dt-fiio.txt        "find /proc/device-tree -maxdepth 4 \\( -iname '*fiio*' -o -iname '*cs43198*' -o -iname '*fpga*' -o -iname '*sound*' \\) 2>/dev/null"
run dt-i2c.txt         "ls /proc/device-tree/soc@0 | grep -i i2c"

# --- partições e config ---
run by-name.txt        "ls -l /dev/block/by-name/"
run fiioconfig-info.txt "ls -l /dev/block/by-name/fiioconfig 2>/dev/null; cat /proc/partitions"
run mount.txt          "mount | grep -E 'vendor|system|persist'"

# --- só com --root ---
if [ "$USE_ROOT" = "1" ]; then
  run regmap-list.txt   "ls /sys/kernel/debug/regmap/"
  run regmap-dump.txt   "for r in /sys/kernel/debug/regmap/*/registers; do echo \"--- \$r\"; cat \$r; done"
  run fiioconfig-dump.txt "dd if=/dev/block/by-name/fiioconfig of=/dev/stdout bs=4096 count=64 2>/dev/null | od -An -tx1"
  run i2cdetect.txt     "for b in 0 1 2 3 4 5 6 7; do echo \"--- bus \$b\"; i2cdetect -y -r \$b 2>/dev/null; done"
fi

say "Pronto: $OUT"
say "Resumo rapido:"
say "  SELinux      -> $(head -1 "$OUT/selinux.txt" 2>/dev/null)"
say "  boot state   -> $(tr '\n' ' ' < "$OUT/boot-state.txt" 2>/dev/null)"
say "  versao       -> $(tr '\n' ' ' < "$OUT/version.txt" 2>/dev/null)"
say "  cards        -> $(tr '\n' ' ' < "$OUT/asound-cards.txt" 2>/dev/null | head -c 300)"
