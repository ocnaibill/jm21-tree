# 01 — Hardware e subsistema analógico

> Fontes: device tree (`dtbo.img`, overlay 40), módulos de kernel, `build.prop`
> e alegações do fabricante (marcadas).

## 1. Plataforma

| Item | Observado | Evidência |
|------|-----------|-----------|
| SoC | Qualcomm `khaje` (SM6225 / Snapdragon 680) | `[DT]` compatíveis `qcom,khaje`, `qcom,khaje-idp`, `qcom,khaje-qrd` |
| Árvore vendor/device | `bengal_515` | `[PROP]` `ro.product.vendor.device`, `pre-device` do OTA |
| Board | `bengal` | `[PROP]` `ro.product.board` |
| CPU | 4x A73 + 4x A53 (Kryo 265) | `[FAB]` (não validado em DT nesta fase) |
| GPU | Adreno 610 | `[PROP]` `ro.opengles.version=196610` (3.2) |
| Kernel | **5.15.41** `g9ded8564ff52-dirty` | `[DRV]` vermagic de 12 módulos |
| Primeira API Android | 33 (Android 13) | `[PROP]` `ro.product.first_api_level=33` |
| Memória / tela | — | `[?]` não presente no OTA |

### `khaje` vs `bengal_515` — não confundir

O firmware usa **dois nomes** para coisas diferentes:

- `khaje` é o SoC/driver-level (compatíveis de DT, `qcom,khaje-*`).
- `bengal_515` é o nome da árvore vendor/QSSI e do `pre-device` do OTA.

Isso é típico de plataformas Qualcomm que compartilham a *vendor tree* entre
variantes. Consequência prática: qualquer busca por código-fonte deve usar
`khaje` para o board e `bengal`/`bengal_515` para HAL e árvore vendor `[HIP]`.

## 2. Cadeia de áudio (hardware)

```
SoC (I2S/TDM) ──► FPGA Gowin ──► CS43198 L (I2C 0x33) ─┐
                        │        CS43198 R (I2C 0x30) ─┤
                        │                              ├─► SGM8262 #1 ─► 3.5 mm SE
                        └─ controle/clock ────────────┘   SGM8262 #2 ─► 4.4 mm BAL
```

O FPGA não estava previsto na primeira versão do dossiê. Ele existe como
dispositivo de primeira classe no DT e tem driver, firmware e interface de
áudio próprios `[DT]` `[DRV]`.

## 3. Os dois DACs

| Nó DT | `reg` (I2C) | `id` | Símbolo | Papel |
|-------|-------------|------|---------|-------|
| `cs43198@32` | **0x33** | 0 | `cs43198_l` | Canal esquerdo |
| `cs43198@31` | **0x30** | 1 | `cs43198_r` | Canal direito |

`[DT]` overlay 40, `fragment@20`.

Pendências:

- `[?]` **Divergência nome × `reg`**: o nome do nó diz `@32`/`@31`, mas
  `reg = 0x33`/`0x30`. Confirmar com `i2cdetect -y <bus>` no aparelho.
- `[?]` O barramento I2C é `target = <0xffffffff>` no overlay (placeholder) e
  `qcom,clk-freq-out = 400000` (400 kHz). O número do barramento só aparece na
  DTB base aplicada (`/proc/device-tree/soc@0/i2c@...`).
- `[HIP]` Dois chips com `id` 0 e 1 indica driver parametrizado por instância —
  a divisão L/R por chip é o modelo esperado em Dual DAC, mas o mapeamento
  final (mono por chip × estéreo por chip) ainda não foi lido no código.

### Controles expostos pelo driver `cs43198.ko` `[DRV]`

Símbolos e mensagens que revelam a superfície de controle:

| Símbolo / string | Indica |
|------------------|--------|
| `cs43198_set_volume_db`, `volume_table`, `volumeL_DB`, `volumeR_DB` | volume em dB por canal, tabela no driver |
| `lrbalance` | balanço L/R no domínio do DAC |
| `pogain`, `pogain_bk`, `gain_pwr_update` | ganho de saída (PO gain) |
| `gain_spe` | ganho específico de saída |
| `is_dsd` | alternância PCM/DSD no `hw_params` |
| `mclk_int`, `clock_base`, `clock_list` | clock mestre interno |
| `poweroff`, `power_state` | sequência de energia |
| `[CS43198]: don't support this filt:%d` | filtros digitais selecionáveis, com validação |
| `[CS43198]: %s(%d), dac_id = %d` | identificação por `dac_id` (0/1) |

Nomes de controle vistos na HAL/libraries (`libfiioaudio.so`) `[FW]`:

- `DAC Playback Volume`
- `DAC line Out Volume`
- `DAC Digital Filter Mode`
- `DAC LR Balance`
- `DAC PO Gain`

São **mixer controls** (ALSA kcontrols) além do que o driver expõe nativamente —
ou seja, o caminho de controle do volume pode ser feito pela HAL via ALSA, sem
passar pelo ioctl do `dac_core` `[HIP]`.

### MCLK `[DRV]`

Constantes presentes em `anolog_board_jm21.ko`:

```
AUDIO_DAC_MCLK_22   → 22.5792 MHz (família 44,1 kHz)
AUDIO_DAC_MCLK_45   → 45.1584 MHz
AUDIO_DAC_MCLK_90   → 90.3168 MHz
```

São múltiplos exatos de 44,1 kHz, coerentes com chaveamento de clock por
família de taxa (44,1 vs 48). `[?]` Falta confirmar se existe clock equivalente
para a família 48 kHz (24.576 MHz) — a buscar nas tabelas do driver.

## 4. Amplificadores e energia

GPIOs declarados em `fiio,anolog_board` `[DT]`:

| Propriedade DT | GPIO | Função inferida |
|----------------|------|-----------------|
| `gpio,dac_pwr` | 79 | habilita alimentação dos DACs |
| `gpio,dac_rst` | 2 | reset dos DACs |
| `gpio,ang_pwr` | 75 | alimentação analógica |
| `gpio,amp_pwr` | 85 | amp 1 |
| `gpio,amp2_pwr` | 67 | amp 2 |
| `gpio,sw_en` | 86 | habilita chave/relé de saída |
| `gpio,out_sel` | 29 | seleção de saída (SE × BAL) |

`[HIP]` Dois enables de amp separados (`amp_pwr`, `amp2_pwr`) são compatíveis
com 2x SGM8262 — um por estágio/saída. Não há nó de DT para os SGM8262: eles
não têm barramento de controle, só enable e a malha analógica.

Sequência de energia observada em mensagens do driver `[DRV]`:

```
[anolog_board]: %s %d, reset dac
[anolog_board]: %s amp_pwr = %d
[anolog_board]: [%s] power need change, so power restart!!!
[anolog_board]: %s: gpio_request %s busy: %d
```

Ou seja: há sequência de reset + energia, e o driver re-executa o ciclo inteiro
quando o modo de saída muda. `[?]` Timing exato (delays entre `dac_pwr`, `rst`,
`amp_pwr`) está em `anolog_board_config_dac` — alvo de decompilação.

## 5. Detecção de fone / tipo de saída

Nó `fiio,jack_det` (`fiio_headset_jack.ko`) `[DT]` `[DRV]`:

| Item | Valor |
|------|-------|
| `hs-det-delay-ms` | 150 (0x96) |
| `hs35_det_gpio` | GPIO 102 |
| `bal44_det` | GPIO 103 |
| `io-channels` / nome | ADC `dc_det1`, canal 18 |
| `hs35-det-threshold` | 1 |

Caminhos de detecção suportados **pelo driver** `[DRV]`:

- `hs35_det_gpio` + `hs35_det_adc` (3,5 mm)
- `bal44_det_gpio` (4,4 mm balanceado)
- `bal25_det_adc` (2,5 mm — presente no driver, provavelmente não usado no JM21)
- `po635_det_gpio` (saída PO tipo 6,35 — idem)

Alarmes/proteções tratados: `DC_ERROR`, `OVERLOAD_ERROR`, `HIGH_TEMP_ERROR`,
`thx_therm_det_*`, além de `LOPO_MODE_SETTING_CHANGE` (modo de baixa potência).

`[?]` Quais dos quatro caminhos estão efetivamente ativos no JM21 (o driver é
compartilhado entre modelos FiiO). Confirmar no DT aplicado e no comportamento.

### Modos de ganho `[DRV]`

Símbolos em `anolog_board_jm21.ko` / `fiio_underlay_modules.ko`:

```
GAIN_L  GAIN_M  GAIN_H  GAIN_OVER_EAR  GAIN_SUPER_OVER_EAR  gain_table
```

`[FW]` Confirmado por disassembly: existem **5 tabelas de volume** no `.rodata`
da placa, uma por modo — `vol_table_po_gain_l`, `_m`, `_h`, `_sh`, `_uh` — com
121 entradas cada (ver `11-disassembly-do-audio.md` e
`analysis/fw-1.1.1/volume-tables.csv`).

O ganho é implementado como **compensação**: ao subir o modo, o código digital
cai na mesma posição de volume (em step 60: `l`=84, `m`=72, `h`=60). Ou seja,
o ganho analógico sobe e a atenuação digital compensa, mantendo o nível
percebido — e é isso que define o headroom real de cada modo.

`[?]` No caminho normal apenas `l`/`m`/`h` são alcançáveis (o switch usa `h`
como default); `sh`/`uh` servem a outro caminho ou a outros modelos. A UI do
JM21 expõe quantos? Pendente.

## 6. Saídas e números do fabricante

| Saída | Alegação FiiO | Evidência |
|-------|---------------|-----------|
| 3,5 mm SE | ≥ 280 mW @ 32 Ω; 8–150 Ω | `[FAB]` |
| 4,4 mm BAL | ≥ 700 mW @ 32 Ω; 8–350 Ω | `[FAB]` |

Nada no firmware confirma potência. O que o firmware confirma é a existência de
`out_sel`, dois enables de amp e detecção separada de 3,5/4,4 `[DT]`.

## 7. FPGA Gowin

| Item | Valor | Evidência |
|------|-------|-----------|
| Compatível I2C | `gowin,fpga_i2c` em `fpga@36` (0x36) | `[DT]` |
| Compatível SPI | `qcom,gw-fpga` em `gw-fpga@0` | `[DT]` |
| SPI | `spi-max-frequency = 1000000`, `spi-cpol`, `spi-cpha` (modo 3) | `[DT]` |
| Chip select | GPIO 17 (`qcom,fpga-cs-pin`) | `[DT]` |
| Enable de energia | GPIO 3 (`gpio,fpga_pwr_en`) | `[DT]` |
| Firmware | `gw_fpga_firmware_jm21.fw` | `[DT]` `[PROP]` |
| Segundo banco | `gw_fpga_firmware_jm21_2.fw` | `[PROP]` |
| Contagem/banco atual | `persist.sys.fpga.firmware.count=2`, `...cur=0` | `[PROP]` |
| Tamanho dos bitstreams | 33 605 e 29 843 bytes | `[FW]` |
| Interface de áudio | nó `fiio,fpga-audio-interface-hal` | `[DT]` |

Leitura: o FPGA tem **dois bitstreams** (A/B, mesma lógica de atualização
redundante do resto do sistema), é carregado por SPI (modo 3, 1 MHz) e tem
interface de áudio dedicada. `[HIP]` Ele faz a ponte/roteamento entre o SoC e os
DACs, provavelmente concentrando também a geração de clocks de áudio
(`fpga_dac_mclk_t` aparece em `anolog_board_jm21.ko`).

`[?]` O que exatamente o bitstream faz no caminho de dados (split L/R, DSD,
reamostragem, seleção de fonte SPDIF/USB) é o maior desconhecido do projeto.

## 8. Outros periféricos relevantes vistos no DT

- `fusb302` (USB-C PD/role switch) — relevante para USB DAC/UAC.
- `sgm41513`/`sgm4154x` (carregador) e `cw221X` (fuel gauge).
- `wcd937x`, `bolero`, `va/tx/rx_macro`, `wsa881x` — pilha de codec Qualcomm
  presente na árvore; `[?]` se o caminho de captura (microfone) usa WCD937x no
  JM21 ou se o aparelho não tem captura.
- `snd-usb-audio-qmi.ko` + `libUsbAudio.so` + `fiio.uac.active` — modo USB DAC
  (UAC) suportado tanto no kernel quanto no app `[DRV]` `[FW]` `[PROP]`.
