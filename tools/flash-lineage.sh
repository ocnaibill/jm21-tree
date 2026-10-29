#!/usr/bin/env bash
#
# flash-lineage.sh — grava a primeira LineageOS 20 (2026-10-28) no JM21.
#
#   ./tools/flash-lineage.sh [dir-dos-artefatos] [--com-stock-vendor-boot]
#
# ATENCAO: isto TROCA o sistema e EXIGE factory reset (FBE atrelado ao system).
# O userdata sera apagado; o cartao SD nao e afetado.
#
# Rollback: dumps/fw-1.1.1 (system/vendor/product/odm/system_ext/vbmeta/boot/...)
#
set -euo pipefail

D="${1:-$HOME/jm21-artifacts/lineage-20261028}"
STOCK="$HOME/repos/jm21-tree/dumps/fw-1.1.1"
VBMETA_NOVERITY="$HOME/jm21-gsi/vbmeta-noverity.img"

step() { printf "\n== %s\n" "$*"; }

step "1/5 conferindo artefatos"
for f in boot.img init_boot.img dtbo.img system.img system_ext.img product.img \
         vendor.img odm.img vendor_dlkm.img system_dlkm.img; do
    [ -f "$D/$f" ] || { echo "falta $D/$f" >&2; exit 1; }
done
[ -f "$VBMETA_NOVERITY" ] || { echo "falta $VBMETA_NOVERITY" >&2; exit 1; }
echo "ok"

step "2/5 bootloader: vbmeta (verificacao off) + boot/init_boot/dtbo"
adb reboot bootloader
for i in $(seq 1 30); do sleep 2; fastboot devices | grep -q . && break; done
fastboot flash vbmeta "$VBMETA_NOVERITY"
fastboot flash boot     "$D/boot.img"
fastboot flash init_boot "$D/init_boot.img"
fastboot flash dtbo     "$D/dtbo.img"
# vendor_boot: mantemos o STOCK — o nosso tem ramdisk minimo (3 modulos) e o
# stock tem os modulos de primeira fase. Trocar so se o boot falhar por isso.
if [ "${2:-}" = "--com-stock-vendor-boot" ]; then
    fastboot flash vendor_boot "$STOCK/vendor_boot.img"
fi

step "3/5 fastbootd: particoes logicas"
fastboot reboot fastboot
for i in $(seq 1 40); do sleep 2; [ "$(fastboot getvar is-userspace 2>&1 | grep -o 'yes' || true)" = yes ] && break; done
fastboot flash system      "$D/system.img"
fastboot flash system_ext  "$D/system_ext.img"
fastboot flash product     "$D/product.img"
fastboot flash vendor      "$D/vendor.img"
fastboot flash odm         "$D/odm.img"
fastboot flash vendor_dlkm "$D/vendor_dlkm.img"
fastboot flash system_dlkm "$D/system_dlkm.img"

step "4/5 factory reset (userdata) — FBE nao sobrevive a troca de system"
fastboot reboot bootloader
for i in $(seq 1 30); do sleep 2; fastboot devices | grep -q . && break; done
fastboot -w

step "5/5 reiniciando"
fastboot reboot
echo
echo "pronto. Primeiro boot pode levar alguns minutos."
echo "Se cair no recovery com 'Can't load Android system', refaca o wipe."
