# 12 — Energia, GPIOs e controles ALSA (decompilado)

> Fonte: Ghidra 12.1.2 headless sobre `anolog_board_jm21.ko` e
> `dac_core_module.ko`, com os nomes de símbolo que o BTF preservou.
> Script: `tools/ghidra/DecompileToFile.java`.

## 1. Mapa dos 7 GPIOs (reconstruído)

O driver preenche `gpio_ctrl[7]` a partir do array `gpio_name[]` do `.data`.
Lendo as 7 relocações `R_AARCH64_ABS64` apontando para o `.rodata`, a ordem real
é:

| Índice | Propriedade DT | GPIO (DT) | Papel |
|--------|----------------|-----------|-------|
| `[0]` | `gpio,dac_rst` | 2 | reset dos DACs |
| `[1]` | `gpio,out_sel` | 29 | seleção de saída (PO × SPDIF) |
| `[2]` | `gpio,ang_pwr` | 75 | alimentação analógica |
| `[3]` | `gpio,dac_pwr` | 79 | alimentação dos DACs |
| `[4]` | `gpio,amp_pwr` | 85 | amp 1 |
| `[5]` | `gpio,amp2_pwr` | 67 | amp 2 |
| `[6]` | `gpio,sw_en` | 86 | chave/relé de saída |

Método (reprodutível):

```bash
readelf -rW anolog_board_jm21.ko | grep R_AARCH64_ABS64 | head -7
# 0x00 -> .rodata+0xbb5, 0x08 -> +0x26d, ... 0x30 -> +0x973
python3 - <<'EOF'
d=open('anolog_board_jm21.ko','rb').read(); ro=d[0x570:0x570+0x1a90]
for o in (0xbb5,0x26d,0x480,0x136,0x143,0xb46,0x973):
    print(ro[o:ro.find(b'\x00',o)].decode())
EOF
```

## 2. Temporizações reais

O compiler transformou cada `msleep(n)`/`usleep` em `n` chamadas de
`__const_udelay(0x418958)`. No arm64, `udelay(n)` usa multiplicador `0x10c7`;
logo `0x418958 / 0x10c7 ≈ 1000` → **cada chamada ≈ 1 ms**.

| Bloco | Nº de chamadas | Tempo |
|-------|----------------|-------|
| após `ang_pwr` | 20 | **20 ms** |
| após `dac_pwr` | 10 | **10 ms** |
| após `out_sel` (pós-energia) | 10 | **10 ms** |
| após `sw_en` (pós-energia) | 10 | **10 ms** |
| desligamento de amps | 50 | **50 ms** |

## 3. Sequências de energia

### Liga (caminho normal)

```c
pre_power_control(true):          // se dac_dai->on == false
    ang_pwr = 1;  msleep(20);

set_dac_power(true):
    fpga->power_by_mode(true, 0);
    dac_pwr = 1;  msleep(10);
    dac_rst = 1;  dac_dai->on = true;

post_power_control(true):         // depende de current_output_type
    if (output_type < 2) out_sel = 1;  else out_sel = 0;   // tipos 3 e 4
    msleep(10);
    sw_en = 1;  msleep(10);
    soft_mute = true;
    amp_pwr = 1;
    if (output_type >= 3) amp2_pwr = 1;
    anolog_board_dc_det_enable();
```

### Desliga (ordem inversa, com mute antes)

```c
post_power_control(false):
    msleep(10);
    amp_pwr = 0;  amp2_pwr = 0;
    msleep(50);
    sw_en = 0;  out_sel = 0;
    dc_det_enable();

set_dac_power(false):
    dac_dai->on = false; report_playing_info(...);
    dac_rst = 0;  dac_pwr = 0;
    fpga->power_by_mode(false, 0);

pre_power_control(false):
    ang_pwr = 0;
```

Regra de ouro do chip: **liga `ang_pwr → dac_pwr → (10 ms) → dac_rst` e desliga
`dac_rst → dac_pwr → ang_pwr`**, com amps sempre antes/depois.

### Caminho SPDIF (`current_output_type == 2`)

Quando a saída é SPDIF, o driver **desliga os DACs** e usa outro caminho:

```c
dac_dai->on = false;
out_sel = 1;  msleep(10);
sw_en   = 1;  msleep(20);
ang_pwr = 0;
dac_rst = 0;
dac_pwr = 1;                 // trilho compartilhado permanece
anolog_board_post_power_control(false);
fpga->power_by_mode(true, 0);
```

Isso casa com a flag `config_fiio_35mm_multiplexing_spdif_enabled`: o jack de
3,5 mm é multiplexado com saída SPDIF (coaxial). `[?]` Falta confirmar se o
óptico (`opt_tx`) sai pelo mesmo jack ou por outro ponto — o FPGA tem
`spdif_tx` e `opt_tx` separados.

## 4. Modo de canal e ganho padrão (JM21)

`anolog_board_load_work` (executado no boot) fixa `[FW]`:

```c
dac_dai->system_work_mode_old = SYSTEM_MODE_MTP;
dac_dai->channel_mode = SPECIAL_MODE_2;   // 2 DACs
dac_dai->pogain = 2;                       // GAIN_H
dac_dai->pogain_bk = 2;
dac_dai->volume_table = vol_table_po_gain_h;
```

`enum audio_channel_mode`: `STEREO=0, MONO=1, SPECIAL_1=2, SPECIAL_2=3,
SPECIAL_3=4, SPECIAL_4=5`.

**Resposta a Q6:** no JM21 o modo é `SPECIAL_MODE_2` → **2 DACs em paralelo**.
Em `cs43198_set_volume_db`, nesse modo:

```c
regmap_l: 0x90002 = lvol ; regmap_r: 0x90002 = lvol    // canal A
regmap_l: 0x90001 = rvol ; regmap_r: 0x90001 = rvol    // canal B
```

Ou seja, **os dois chips recebem o estéreo completo e são escritos
identicamente** (dual DAC paralelo, soma analógica). O modo mono-por-chip
(`SPECIAL_MODE_3`, 4 DACs) existe no código, mas não é o do JM21.

**Resposta parcial a Q13:** o aparelho **inicia em High gain** (`pogain=2`).

## 5. Onde cada controle ALSA escreve

`dac_core_module.ko` implementa os kcontrols; cada `put` grava num campo de
`snd_dac_dai` e dispara o callback de atualização:

| Kcontrol | Campo (offset) | Efeito |
|----------|----------------|--------|
| `DAC Playback Volume` | `volume` (0x84) | 0–120; dispara `update_volume` |
| `DAC PO Gain` | `pogain` (0xac) | 0–4; `gain_update=1`; `pogain_bk` guarda o anterior |
| `DAC LR Balance` | `lrbalance` (0xa4) | balanço; `gain_update=0` |
| `DAC line Out Volume` | — | volume de line out |
| `DAC Digital Filter Mode` | `lpf_setting` (0xa0) | ver §6 |
| DRE | `dre_setting` (0xd4) | ver §6 |
| THD C2 | `thd_c2` (0xc8) | `persist.sys.thd.c2.way` |

Detalhe de `pogain`: a troca só marca `gain_pwr_update` quando **cruza o modo 4**
(`SUPER_OVER_EAR`), porque esse modo muda a topologia de energia. E
`pogain_bk` guarda o valor anterior — visível na UI como "voltar ao ganho
anterior".

## 6. Filtros digitais e DRE (registradores reais)

`cs43198_set_lpf` mapeia o índice do usuário para o **PCM Filter Option**
(registrador `0x90000` do chip), e **só se aplica em PCM**:

| `lpf_setting` | Valor escrito | Composição |
|---------------|---------------|------------|
| 0 | `0x02` | base 2 |
| 1 | `0x82` | base 2 + bit 7 |
| 2 | `0x42` | base 2 + bit 6 |
| 3 | `0xC2` | base 2 + bits 6 e 7 |
| 4 | `0x03` | base 3 |
| 5 | `0x22` + `nos_status=1` | base 2 + **bit 5 = NOS** |

O datasheet confirma o bit 5 como NOS (`Enable NOS filter → 0x90000 OR 0x20`) e
nomeia os bits 7 e 6 nas tabelas de características como `FILTER_SLOW_FASTB`
(roll-off lento × rápido) e `PHCOMP_LOWLATB` (compensação de fase / baixa
latência). `[HIP]` A combinação exata usada pela FiiO em cada preset vem da UI;
os 6 valores são inequívocos, os nomes dos bits 6/7 ainda são leitura de tabela.

`cs43198_set_dre` (Dynamic Range Enhancement):

```c
write 0x10010 = 0x99;                       // unlock
if (dre_setting) { write 0xc0001 = 1; write 0xc0056 = 0x0f; }
else             { write 0xc0001 = 0; }
write 0x10010 = 0;                          // lock
```

O padrão "0x99 → altera → 0" é a sequência de desbloqueio de página do CS43198.

## 7. Endereçamento de registrador `[FW]` + datasheet

O datasheet do CS43198 (DS1156F2) usa os **mesmos endereços** que o driver
escreve — o "9" e o "7" são blocos reais do mapa, não uma convenção nossa:

| Endereço | Registro | Fonte |
|----------|----------|-------|
| `0x90000` | PCM Filter Option (bit 5 = NOS) | datasheet §7.5.2 / driver |
| `0x90001` | PCM Volume B | datasheet §7.5.3 |
| `0x90002` | PCM Volume A | datasheet §7.5.4 |
| `0x90003` | PCM Path Signal Control 1 | datasheet §7.5.5 |
| `0x70000` | DSD Volume B | datasheet §7.4.1 |
| `0x70001` | DSD Volume A | datasheet §7.4.2 |
| `0x70002` | DSD Processor Path Signal Control 1 | datasheet §7.4.3 |
| `0x70003` | DSD Interface Configuration | datasheet §7.4.4 |
| `0x70004` | DSD Processor Path Signal Control 2 | datasheet §7.4.5 |

`cs43198_readable_register` então define o recorte de acessibilidade por bloco:

| Bloco | Faixa legível |
|-------|---------------|
| `0x1` | `0x10000–0x1000d` (máscara `0x387f`) |
| `0x2` | `0x20000`, `0x20052` |
| `0x3` | `0x30001–0x3001b` |
| `0x4` | `0x40002–0x40029` |
| `0x5` | `0x50000–0x5000b` |
| `0x6` | `0x60000–0x6000b` |
| `0x7` | `0x70000–0x70006` (**DSD**) |
| `0x8` | `0x80000` |
| `0x9` | `0x90000–0x90004` (**PCM**) |
| `0xb`, `0xd`, `0xe`, `0xf` | `0xb0000`, `0xd0000–1`, `0xe0000–1a`, `0xf0000–14` |

**Correção:** a leitura anterior de "(página << 16) | reg" era uma inferência
errada; os endereços são os do chip, e os blocos são seções do mapa de
registradores. O `regmap` é configurado com 32 bits de endereço.

## 8. Sequência de init do DAC (`cs43198_config_dac`)

Dois caminhos, DSD e PCM, com a mesma espinha:

1. `0x90003` = `0xAC` (PCM, sem soft-mute) ou `0xAF` (com mute) `[FW]`
2. `0x20000` = `0xFE`; `0x20052` = 4
3. leituras de status em `0xf0000`/`0xf0001` (interruptos)
4. `0xf0010` = `0xE7` (PCM) / `0xE1` (DSD) — unlock/clock
5. `0xb0000` = 6; `0x80000` = `0x30`
6. configuração de ASP por taxa (`0x40010–0x40019`)
7. `0x50000`/`0x50001` = 0; `0x5000a`/`0x5000b` **dependem do `channel_mode`**
8. `0x90004` conforme modo (0 e 0x0C no modo de 2 DACs)
9. `0xf0011` = `0x07`; `0x10006` = 0; ajuste final em `0x20000`

Tabela de taxa → código ASP (`cs43198_calculation_rate_TO_ASP_register`):

| Taxa | Código |
|------|--------|
| 32000 | 0 |
| 44100 | 1 |
| 48000 | 2 |
| 88200 | 3 |
| 96000 | 4 |
| 176400 | 5 |
| 192000 | 6 |
| 352800 | 7 |
| 384000 | 8 |
| 705600 / 768000 | 0 (sem código próprio) |

Para DSD (`0x70004 = código | 0x13`): DSD128 (`0x56220` = 352800) → 8;
DSD64 (`0x2b110` = 176400) → 4; demais → 0.

`[?]` O "sem código próprio" para 705,6/768 kHz é suspeito: ou o chip não aceita
essas taxas por essa via, ou o driver delega ao FPGA. Vale cruzar com
`cs43198_set_sample_rate`.

## 9. Mono mode (coeficientes)

`cs43198_set_mono_mode` escreve um bloco de 24 valores em `0x18000x`
(4 grupos de 6: `...09–0c`, `...0f–10`, depois `...19–1c`, `...1f–20`, etc.).
São coeficientes de filtro por canal — usado só nos modos MONO/SPECIAL_1/SPECIAL_3.

## 10. O que ainda falta

| Item | Como fechar |
|------|-------------|
| Significado de `current_output_type` 1/2/3/4 | ler `anolog_board_output_type` + headset_jack |
| Escala dB exata do volume | `cs43198_set_volume_db` já lida: é código puro; a escala vem da UI/libfiioaudio |
| `cs43198_set_sample_rate` | decompilado — pendente de análise |
| Caminho óptico × coaxial | DT + `fpga_config_params.opt_tx` |
