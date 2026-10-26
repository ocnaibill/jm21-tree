#!/system/bin/sh
# audio-bringup.sh - sobe o audio do JM21 DENTRO DO RECOVERY (TWRP).
# Issue #13-B (docs/48 secao 10). Rodar como root, no recovery.
#
# RESULTADO (verificado):
#   /proc/asound/cards -> [bengalidpsndcar] bengal-idp-snd-card
#   /dev/snd/controlC0 + pcmC0D*
#
# A ORDEM IMPORTA em cada bloco. Cada regra abaixo foi MEDIDA, nao suposta.

VDL=/mnt/vdlkm
M=$VDL/lib/modules
ok() { printf "%-28s %s\n" "$1" "$2"; }
cnt() { grep -c "^$1 " /proc/modules; }

# ---------------------------------------------------------------- 1. montagens
mkdir -p /vendor $VDL /lib/firmware
mount -o ro /dev/block/mapper/vendor_a /vendor 2>/dev/null
mount -o ro /dev/block/mapper/vendor_dlkm_a $VDL 2>/dev/null
[ -f $M/spf_core_dlkm.ko ] || { echo "FALHA: vendor_dlkm nao montado"; exit 1; }

# request_firmware procura em /lib/firmware, NAO no /vendor montado depois
cp /vendor/firmware/adsp.* /lib/firmware/ 2>/dev/null
ok "firmware adsp" "$(ls /lib/firmware 2>/dev/null | wc -l) arquivos"

# ------------------------------------------------------------- 2. base do DSP
# ordem importa: spf_core antes do adsp_loader
for m in snd_event_dlkm q6_pdr_dlkm q6_notifier_dlkm gpr_dlkm spf_core_dlkm \
         audpkt_ion_dlkm audio_pkt_dlkm audio_prm_dlkm adsp_loader_dlkm; do
    insmod $M/$m.ko 2>/dev/null
done

# ------------------------------------------------------- 3. ADSP (por NOME!)
# o indice do remoteproc MUDA entre boots; nunca usar remoteproc0 as cegas
for r in /sys/class/remoteproc/remoteproc*; do
    case $(cat $r/name 2>/dev/null) in *adsp*) echo start > $r/state ;; esac
done
sleep 3
for r in /sys/class/remoteproc/remoteproc*; do
    case $(cat $r/name 2>/dev/null) in *adsp*) ok "ADSP" "$(cat $r/state)" ;; esac
done

# ------------------------------- 4. codecs + machine (machine ANTES dos macros)
# pinctrl_lpi_dlkm -> fornece msm_cdc_pinctrl_* (sem ele va/tx_macro falham)
# swr*_dlkm        -> fornece swrm_wcd_notify
# mbhc_dlkm        -> fornece wcd_mbhc_* (antes do wcd937x_dlkm)
# machine_dlkm     -> exporta msm_cdc_pinctrl_select_* (os macros dependem dele)
for m in pinctrl_lpi_dlkm swr_dlkm swr_ctrl_dlkm bolero_cdc_dlkm \
         mbhc_dlkm wcd9xxx_dlkm wcd_core_dlkm wcd937x_dlkm wcd937x_slave_dlkm \
         machine_dlkm; do
    insmod $M/$m.ko 2>/dev/null
done
ok "bolero/machine" "bolero=$(cnt bolero_cdc_dlkm) machine=$(cnt machine_dlkm)"

# ------------------------- 5. rebind do spf_core (cria o device do card)
# SO funciona com o ADSP ja 'running'. Sem DSP: 0 filhos, sem enumeracao.
echo soc:spf_core_platform > /sys/bus/platform/drivers/spf-core-platform/unbind 2>/dev/null
sleep 1
echo soc:spf_core_platform > /sys/bus/platform/drivers/spf-core-platform/bind 2>/dev/null
sleep 5
ok "filhos do spf_core" "$(ls /sys/bus/platform/devices/ | grep -c 'spf_core_platform:')"

# --------------------------------------------------------- 6. macros de audio
for m in va_macro_dlkm rx_macro_dlkm tx_macro_dlkm; do
    insmod $M/$m.ko 2>/dev/null
done
ok "macros" "va=$(cnt va_macro_dlkm) rx=$(cnt rx_macro_dlkm) tx=$(cnt tx_macro_dlkm)"

# ------------------------------------------- 7. codec que o DT exige
# asoc-codec-names pede: msm-stub-codec.1, bolero-codec, fiio_codec
insmod $M/stub_dlkm.ko 2>/dev/null
ok "stub_dlkm (msm-stub-codec)" "$(cnt stub_dlkm)"

# ------------------- 8. stack de Bluetooth: o ULTIMO elo do card
# O DAI link de BT SCO defere sem btfmslim_slave. A cadeia:
#   cnss_utils (cnss_utils_update_device_type) -> btpower -> bt_fm_slim
for m in cnss_prealloc cnss_utils btpower bt_fm_slim; do
    insmod $M/$m.ko 2>/dev/null
done
ok "bt stack" "cnss_utils=$(cnt cnss_utils) btpower=$(cnt btpower) bt_fm_slim=$(cnt bt_fm_slim)"

# ----------------------------------------------------------- 9. probe do card
echo soc:spf_core_platform:sound > /sys/bus/platform/drivers_probe 2>/dev/null
sleep 5

echo
echo "=== /proc/asound/cards:"
cat /proc/asound/cards
echo "=== /dev/snd:"
ls /dev/snd/ 2>/dev/null | tr '\n' ' '; echo
