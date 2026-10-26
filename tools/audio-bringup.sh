#!/system/bin/sh
# audio-bringup.sh - leva o audio do JM21 ate onde da dentro do TWRP.
# Issue #13-B (docs/48 secao 10). Rodar no recovery como root.
#
# Estado que esta receita alcanca:
#   - ADSP (remoteproc adsp) = running
#   - techpack carregado, macros (rx/va/tx) ligados
#   - SoundWire com swr0/swr1 + wcd937x-slave (igual ao Android)
#   - card soc:spf_core_platform:sound criado, mas SEM driver (ver 10.20)

VDL=/mnt/vdlkm

# 1. monta o vendor (firmware) e o vendor_dlkm (modulos do techpack)
mkdir -p /vendor $VDL /lib/firmware
mount -o ro /dev/block/mapper/vendor_a /vendor 2>/dev/null
mount -o ro /dev/block/mapper/vendor_dlkm_a $VDL 2>/dev/null
# request_firmware procura em /lib/firmware, NAO no /vendor
cp /vendor/firmware/adsp.* /lib/firmware/ 2>/dev/null

# 2. base do DSP (ordem importa: spf_core antes do adsp_loader)
for m in snd_event_dlkm q6_pdr_dlkm q6_notifier_dlkm gpr_dlkm spf_core_dlkm \
         audpkt_ion_dlkm audio_pkt_dlkm audio_prm_dlkm adsp_loader_dlkm; do
    insmod $VDL/lib/modules/$m.ko 2>/dev/null
done

# 3. sobe o ADSP - o indice do remoteproc MUDA entre boots, usar o nome
for r in /sys/class/remoteproc/remoteproc*; do
    case $(cat $r/name 2>/dev/null) in
        *adsp*) echo start > $r/state ;;
    esac
done
sleep 3

# 4. A ORDEM AQUI E CRITICA (cada erro abaixo custou uma rodada):
#    - pinctrl_lpi_dlkm  -> fornece msm_cdc_pinctrl_* (sem ele va/tx_macro falham)
#    - swr_dlkm/swr_ctrl -> fornecem swrm_wcd_notify (sem eles os macros falham)
#    - mbhc_dlkm         -> fornece wcd_mbhc_* (tem de vir ANTES do wcd937x_dlkm)
#    - wcd937x_slave_dlkm-> registra o driver SoundWire "wcd937x-slave"
for m in pinctrl_lpi_dlkm swr_dlkm swr_ctrl_dlkm bolero_cdc_dlkm \
         va_macro_dlkm rx_macro_dlkm tx_macro_dlkm \
         mbhc_dlkm wcd9xxx_dlkm wcd_core_dlkm wcd937x_dlkm wcd937x_slave_dlkm \
         machine_dlkm; do
    insmod $VDL/lib/modules/$m.ko 2>/dev/null
done
sleep 5

# 5. re-executa a enumeracao do spf_core (cria/refaz o device 'sound')
echo soc:spf_core_platform > /sys/bus/platform/drivers/spf-core-platform/unbind 2>/dev/null
sleep 1
echo soc:spf_core_platform > /sys/bus/platform/drivers/spf-core-platform/bind 2>/dev/null
sleep 5

echo "=== ADSP:"
for r in /sys/class/remoteproc/remoteproc*; do echo "  $(cat $r/name) $(cat $r/state)"; done
echo "=== SoundWire:"
ls /sys/bus/soundwire/devices/ 2>/dev/null | sed 's/^/  /'
echo "=== drivers SoundWire (vazio = codec nao registrou):"
ls /sys/bus/soundwire/drivers/ 2>/dev/null | sed 's/^/  /'
echo "=== card device:"
readlink /sys/bus/platform/devices/soc:spf_core_platform:sound/driver 2>/dev/null || echo "  (sem driver)"
echo "=== /proc/asound/cards:"
cat /proc/asound/cards
