# 18 — Superfície sysfs e o caminho userspace → kernel

> Fonte: `/vendor/etc/init/hw/init.fiio.common.rc` e `init.fiio.usb.rc` (agora
> extraídos para `analysis/fw-1.1.1/vendor/etc/init/hw/`), cruzados com strings
> dos módulos. Os `chmod 0666` do init **são** a documentação da API: cada nó
> listado existe para ser escrito pelo userspace.

## 1. Os nós de áudio (o que interessa)

| Nó em `soc:fiio_attr/` | Módulo que registra | Papel |
|------------------------|---------------------|-------|
| `dac_ctrl` | `dac_core_module` | controle de estado do DAC (startup/shutdown/mute) |
| `dac_vol` | `dac_core_module` | volume do DAC |
| `dac_read_reg` | `dac_core_module` | leitura de registrador do CS43198 (debug) |
| `board_debug` | `anolog_board_jm21` | debug da placa |
| `board_vol_dac` | `anolog_board_jm21` | volume/ganho por modo |
| `board_dac_dre_switch` | `anolog_board_jm21` | liga/desliga DRE |
| `board_delay_ctrl` | `anolog_board_jm21` | controla os delays da sequência de energia |
| `board_is_pause_by_headset` | `anolog_board_jm21` | pausa automática ao tirar o fone |
| `headset_type` | `dac_core_module` + `fiio_headset_jack` | tipo de saída detectada (3,5 / 4,4 / LO / SPDIF) |
| `headset_debug` | `fiio_headset_jack` | limiares/estado de detecção |
| `i2c_test_auto`, `i2c_test_write`, `i2c_test_get_failed_count` | `fiio_primary_modules` | bancada de I2C |

## 2. Os nós do FPGA

| Nó | Módulo | Papel |
|----|--------|-------|
| `fpga_power` | `gw-fpga` | energia do FPGA |
| `fpga_bypass` | `fpga_audio_interface` | modo bypass |
| `fpga_hwinit`, `fpga_config` | `fpga_audio_interface` / `gw-fpga` | configuração de I2S/SPDIF |
| `fpga_firmware_name`, `fpga_gw_fw_name`, `fpga_gw_update_firmware_name` | `gw-fpga` | nome do bitstream |
| `fpga_gw_update`, `fpga_gw_erase`, `fpga_gw_reload`, `fpga_gw_power_ctrl` | `gw-fpga` | gravação do bitstream (SSPI) |
| `fpga_gw_read_code` | `gw-fpga` | lê ID/user/status code do Gowin |
| `fpga_gw_input_func`, `fpga_gw_spi_func` | `gw-fpga` | seleção de função de entrada / função SPI |

Estes nós são a **interface de bancada do FPGA**: dá para gravar bitstream,
reler o código de status e trocar a função de entrada sem abrir o aparelho.

## 3. Nós que o init prepara mas **não existem** neste firmware

`[FW]` Zero ocorrências no `vendor_dlkm.img`:

- `board_vol_nju` — controle de volume NJU (chip de outro modelo)
- `i2c_test_read`
- `sw_hold_ctrl`

Ou seja: o `init.fiio.common.rc` é **compartilhado entre modelos FiiO** e faz
`chmod` de um superconjunto. Nó inexistente = `chmod` falha silenciosamente.

## 4. Propriedade → ação (os gatilhos reais)

| Propriedade | Ação |
|-------------|------|
| `fiio.usb.boot.mode=enable/disable` | escreve `usb_boot_switch` |
| `fiio.vehicle.mode=enable/disable` | escreve `power_off_charge_switch` (invertido) |
| `fiio.config.fpga.firmware=*` | escreve `fpga_gw_update_firmware_name ${valor}` |
| `fiio.ssusb.speed=*` / `fiio.ssusb.mode=*` | escreve em `4e00000.ssusb/speed` e `/mode` |
| `fiio.sys.ctrl=*` | inicia `system_ctrl.sh` com o valor |
| `fiio.start.uac.service=1/0` | inicia/para `fiiouac` |
| `fiio.start.huawei_hiplay.service=1/0` | inicia/para `huawei_hiplay` |
| `fiio.init.service=1` | inicia `fiio_init.sh` |
| `fiio.do.master.clear=1` | inicia `fiio_uninit.sh` (reset de fábrica?) |
| `fiio.start.dropcaches=1` | inicia `fiio_drop_caches.sh` |
| `fiio.start.numservice=1` | inicia `numservice.sh` (grava SN/NB) |
| `fiio.handle.files=0` | inicia `mcopy_files` (`handle_files.sh cp_files`) |
| `fiio.output.logs=1`, `fiio.dumpsys.logs=1` | coleta de logs |
| `fiio.uninstall.google=1`, `fiio.bmgr.google=1` | remove/aciona serviços Google |

## 5. Serviços FiiO (o que a HAL/apps podem disparar)

`/system/bin/fiiouac` · `/system/bin/huawei_hiplay` · `/system/bin/hiplay?` ·
`/system/bin/logsystem` · `/system/bin/output_logs.sh` ·
`/system/bin/dumpsys_logs.sh` · `/system/bin/google_uninstall.sh` ·
`/system/bin/google_bmgr.sh` · `/system/bin/handle_files.sh` ·
`/system/bin/fiio_init.sh` · `/system/bin/fiio_uninit.sh` ·
`/system/bin/fiio_drop_caches.sh` · `/vendor/bin/system_ctrl.sh` ·
`/vendor/bin/numservice.sh`

## 6. USB: os dois modos e um detalhe

| Config | VID:PID | Função |
|--------|---------|--------|
| MTP | `18d1:4ee1` | MTP (+ ADB em `mtp,adb` = `18d1:4ee2`) |
| **UAC2** | **`2972:0045`** | DAC USB (`uac2.0`), também em `uac2,adb` |

`[FW]` O descritor USB do modo UAC2 grava **`serialnumber` fixo: `"3fa90f5"`**,
igual em qualquer aparelho (aparece no `init.fiio.usb.rc`). Isso não é o serial
real do dispositivo — é um valor de exemplo que ficou no script. Consequência:
dois JM21 ligados ao mesmo PC como DAC USB podem colidir na enumeração.

## 7. Notas de segurança (fatos, não opinião)

1. **Todos os nós são `0666`** — qualquer processo (mesmo app comum, se o
   SELinux permitir) pode escrever em `dac_vol`, `fpga_gw_update`,
   `fpga_bypass`, `config_sn`… O SELinux é o único guarda.
2. `fiio.enter.dump=enable` escreve `c` em `/proc/sysrq-trigger` → **provoca
   crash intencional** para gerar dump. Se alguma superfície não privilegiada
   conseguir setar essa propriedade, é negação de serviço trivial.
3. `fiio.enable.dump` escreve comandos AT em `/data/vendor/port_bridge/at_miso`.
4. `numservice.sh` grava SN/NB em `config_sn`/`config_nb` — a identidade do
   aparelho vem daqui (e da partição `fiioconfig`).
5. `fiio.do.master.clear` dispara `fiio_uninit.sh` — provável reset de estado.

## 8. O que isso fecha

O caminho completo agora tem as duas pontas documentadas:

```
app → HAL (libfiioaudio)         [userspace, strings mapeadas]
    → kcontrol ALSA              [dac_core: volume, gain, filtro, formato]
    → sysfs soc:fiio_attr/*      [nós desta página]
    → notifier chain             [19 cadeias, eventos 0–8]
    → dac_core/anolog_board/cs43198/FPGA
```

`[?]` Falta só identificar, dentro da `libfiioaudio.so`, **qual** desses nós
cada ação escreve (próximo passo: RE da HAL).

## 9. Dica de bancada para quando o aparelho chegar

Com root, `ls /sys/devices/platform/soc/soc:fiio_attr/` deve listar praticamente
esta tabela. A diferença entre a lista real e a do init é a assinatura exata
deste modelo — e serve para separar o que é código compartilhado do que é JM21.
