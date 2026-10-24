# 23 — Sessão 1 com o aparelho (baseline read-only)

> Coleta: `tools/collect-baseline.sh` em 2026-10-23 21:31 (local), firmware 1.1.1,
> aparelho stock. **Nada foi escrito no dispositivo.** Saída bruta em
> `device-baseline/20261023-213158/` (fora do git).

## 1. Duas correções importantes (minha auditoria estava errada)

| Afirmação externa | Meu veredito em `docs/16` | **Realidade medida** |
|-------------------|---------------------------|----------------------|
| "SELinux permissive de fábrica" | "sem evidência / provavelmente falso" | **CONFIRMADO**: `getenforce` = **Permissive** |
| "Bootloader desbloqueado de fábrica" | "sem evidência / provavelmente falso" | **CONFIRMADO**: `ro.boot.verifiedbootstate=orange`, `ro.boot.flash.locked=0` |

Lição registrada: o firmware **não** carrega estado de boot nem modo SELinux —
eles vêm do bootloader/`init`, então a ausência no pacote não provava nada. A
auditoria acertou em refutar `super`/`splash`, mas errou aqui por excesso de
confiança.

`veritymode=enforcing` (dm-verity ativo), apesar do bootloader destravado.

## 2. Identificação

```
Versão            : 1.1.1
Fingerprint       : (igual ao pacote: eng.fiio.20260428.144644)
Modelo em DT      : "Qualcomm Technologies, Inc. KHAJEW IDP nopmi"
compatible        : qcom,khaje-idp qcom,khaje qcom,idp
Placa de som      : bengalidpsndcar  (bengal-idp-snd-card)
Armazenamento     : eMMC (mmcblk0), A/B (boot_a/p81, boot_b/p82, ...)
fiioconfig        : /dev/block/mmcblk0p71
```

## 3. I²C — tudo confirmado

```
barramento 2 (Geni-I2C):  2-0030 cs43198   2-0033 cs43198   2-0036 fpga_i2c  2-0042 fsa4480
barramento 0 (i2c_gpio) :  0-0022 fusb302
barramento 1            :  1-001a sgm41513  1-0064 cw221X
barramento 3            :  3-0038 fts (touch)  3-005d gt9xx
```

Fecha o `[?]` de docs/01/04: **bus 2**, DACs em **0x30 e 0x33**, FPGA em **0x36**.

## 4. GPIOs — números absolutos (e a base do TLMM)

`[FW]` dmesg do `anolog_board`:

| Propriedade DT | GPIO local | **GPIO absoluto** |
|----------------|-----------|-------------------|
| `dac_rst` | 2 | **391** |
| `out_sel` | 29 | **418** |
| `ang_pwr` | 75 | **464** |
| `dac_pwr` | 79 | **468** |
| `amp_pwr` | 85 | **474** |
| `amp2_pwr` | 67 | **456** |
| `sw_en` | 86 | **475** |
| `fpga_pwr_en` | 3 | **392** |
| `fpga_cs` | 17 | **406** |

Base do controlador TLMM = **389** (391 − 2). Os valores do DT estavam certos;
o kernel soma a base.

O driver do FPGA confirma o que o DT dizia: `fpga_1v2_en`, `fpga_3v3_en` e
`code_1v8_en` **não existem** neste aparelho — só `fpga_pwr_en`.

## 5. FPGA em execução

```
fpga_manager fpga0: GW Slave Serial FPGA Manager registered
[GW_FPGA] fpga_cs = 406   fpga_pwr_en = 392
```

Ou seja: além do SPI de controle, o bitstream é carregado por **Slave Serial**
pelo framework `fpga_manager`. `fpga_gw_version = 0x0` (ID de status lido como
zero — `[?]` se o bitstream está carregado neste estado ocioso).

Estado ao vivo (`fpga_config`):

```
dsd=0 out_format=0 imclkt=0
dac1_mclk_en=0 dac1_mclk=0 dac2_mclk_en=0 dac2_mclk=0
p2d=0 p2d_t=0 one_line=0 mul_line=0
```

**Confirma dois MCLKs independentes** (`dac1_mclk`, `dac2_mclk`) e a existência
do modo `one_line` que vimos em `snd_dac_hw_params` (que dobra a taxa).

## 6. DAC em execução

```
[CS43198] cs43198_i2c_probe(841), dac_id = 0   -> dac l finished
[CS43198] cs43198_i2c_probe(841), dac_id = 1   -> dac r finished
```

Valores ociosos:

| Nó | Valor | Leitura |
|----|-------|---------|
| `dac_vol` | **69** | volume da UI |
| `board_vol_dac` | **255** | código do DAC = 0xFF = **mute** (idle) |
| `headset_type` | 0 | nada plugado |
| `board_output_type` | 1 | tipo "linha"/normal |
| `board_dac_dre_switch` | vazio | leitura sem valor |

O `255` confirma na prática a escala do datasheet: **0xFF = mute**.

## 7. Jack: DT correto, detectores opcionais ausentes

`[FW]` O nó `fiio_headset_jack` **tem** `hs35_det_gpio` (GPIO 102),
`bal44_det` (GPIO 103), `io-channels` (ADC 18) e `hs-det-delay-ms` (150) — igual
ao overlay 40. Os `get failed` do boot são de recursos **opcionais** que este
modelo não usa: `bal25_det_adc`, `hs35_det_adc`, `dc_det2`, `thx_therm_det`,
`overload_det_threshold`.

## 8. API sysfs real (difere do init)

`[FW]` `/sys/devices/platform/soc/soc:fiio_attr/` tem **mais** nós do que o
`init.fiio.common.rc` chmoda, e não tem alguns que ele lista:

**Extras confirmados:** `board_output_type`, `fpga_debug`, `fpga_gw_version`,
`lcd_id0..3`, `led_blue`, `led_green`, `led_red`, `temp_compensation`,
`ts_touchscreen_name`, `cc_state`, `charging_disable_status`,
`disable_battery_charge_level`, `user_set_disable_charge_level`,
`cw_batt_id`, `cw_batt_soh`, `cw_batt_capacity`, `power`.

**Ausentes (código compartilhado, como suspeitávamos):** `board_vol_nju`,
`i2c_test_auto/read/write/get_failed_count`, `sw_hold_ctrl`, `send_tape_type`,
`send_hold_type`.

## 9. Caminho de áudio vivo

`/proc/asound/pcm` (card 0) mostra DPCM com os DAIs dummy da FiiO:

```
00-01 PCM_RT_PROXY-RX-1     snd-soc-dummy-dai-1   playback
00-02 USB_AUDIO-RX          snd-soc-dummy-dai-2   playback
00-05 CODEC_DMA-LPAIF_RXTX-RX-0    rx_macro_rx1   playback   <- backend do HEADSET
00-14 MI2S-LPAIF_VA-RX-PRIMARY     multicodec-14  playback   <- backend do HEADPHONE
00-16 MI2S-LPAIF_WSA-RX-PRIMARY    msm-stub-rx    playback
00-18 MI2S-LPAIF_AUD-RX-SECONDARY  msm-stub-rx    playback
```

O `AudioFlinger` mantém várias saídas em standby, incluindo **384 kHz /
PCM_FLOAT** (`AudioOut_1D`, 61 440 bytes) e 192 kHz — coerente com o mixPort
`hifi_playback` da política.

## 10. Ferramentas e limites de acesso

`tinymix`, `tinyplay`, `tinycap` e `tinypcminfo` **existem** em `/system/bin`.
Mas `/dev/snd/*` é `0660 system:audio`: o usuário `shell` não abre
(`Failed to open mixer`, `cannot open device`).

→ **Ler kcontrols exige root.** Sem root, o caminho é `dumpsys` + sysfs (o que
já fizemos).

## 11. Bugs de kernel observados (não relacionados a áudio)

```
goodix-ts: Unbalanced enable for IRQ 171   (WARNING em kernel/irq/manage.c)
fiio_attr: Attribute cw_batt_id: write permission without 'store'
```

O segundo é do próprio `fiio_attr`: registra um atributo com permissão de
escrita e sem `store` — combina com o `chmod 0666` geral.

## 12. Módulos carregados que ainda não analisamos

`power_board_jm21`, `lcd_id`, `led`, `ts_core`, `fiio_wakeup`,
`fiio_charger_manager`, `goodix_gt9xx_ts`, `fusb302`, `cw221X_fuel_gauge`,
`sgm4154x_charger`.

`fiio_primary_modules` é usado por **21** módulos — o "SDK" na prática.

## 13. O que isso muda

1. `docs/16` precisa corrigir os dois vereditos (§1 acima).
2. `docs/01` ganha a tabela de GPIO absoluto e a base 389.
3. `docs/18` ganha a lista real de nós (§8) e a nota de que `tinymix` exige root.
4. `docs/02` ganha: eMMC, `fiioconfig` = `mmcblk0p71`, 90+ partições.
5. Confirmado no hardware: I²C bus 2 / 0x30 / 0x33 / 0x36, dois MCLKs no FPGA,
   `0xFF` = mute.

## 14. Próximos passos (sessão 2)

| Objetivo | Precisa de root? | Como |
|----------|------------------|------|
| Confirmar kcontrols reais (7 vs 12) | **sim** | `tinymix -D 0` |
| Dump de regmap (OUT_FS, +1dB_EN, código de volume) | **sim** | `/sys/kernel/debug/regmap/` |
| Dump da `fiioconfig` (layout) | **sim** | `dd if=/dev/block/by-name/fiioconfig` |
| Taxa real e modo de processamento ao tocar | não | `logcat -s fiioaudio` + `hw_params` |
| Volume ↔ código (69 → ?) | não | tocar e ler `board_vol_dac` |
| Topologia/ganho analógico | não | medição com o FT1 (32 Ω) |

**Sobre o FT1:** 32 Ω, 98 dB/mW — é exatamente a carga de referência da ficha
(32 Ω). Serve para os testes comparativos. **Cuidado:** a 98 dB/mW, 245 mW dão
~122 dB SPL; nunca testar volume máximo com o fone na cabeça.
