# 26 — `fiioconfig`: layout da partição de configuração

> Fonte: dump da partição (`mmcblk0p71`, 10 MB) + decompilação do
> `fiio_config.ko`. Dump bruto em `device-baseline/fiioconfig/` (contém SN —
> fora do git).

## 1. Visão geral

```
partição : /dev/block/by-name/fiioconfig -> /dev/block/mmcblk0p71
tamanho  : 10 485 760 bytes (10 MB)
em uso   : ~48 KB (12 blocos de 4 KB com dados)
acesso   : fiio_config.ko via kernel_read/kernel_write direto no block device
           (não é filesystem montado)
```

## 2. Mapa de campos (extraído do módulo)

| Offset | Tam. | Campo | Função no módulo | Valor observado |
|--------|------|-------|------------------|-----------------|
| `0x0000` | ~0x28 | cabeçalho de configuração | — | `"enable"` + campos |
| `0x0C00` | 4 | **trim do DAC esquerdo** | `read_left_dac_master_trim_index_from_storage` | `0` |
| `0x0C04` | 4 | **trim do DAC direito** | `read_right_dac_master_trim_index_from_storage` | `0` |
| `0x1000` | 4 | checksum do **CST812T** (touch) | `read_cst812t_checksum_from_storage` | `0` |
| `0x1400` | 50 | nome do firmware do FPGA | `read_fpga_firmware_name_from_storage` | vazio |
| `0x1800` | 50 | **SN** | `sequence_number_read_SN` | `"20070008442701"` |
| `0x1C00` | 50 | **NB** | `sequence_number_read_NB` | `"A00aa5a"` + `"442701"` |
| `0x5000` | — | segundo registro (journal) | — | magic `0xcac3`, contador `0x4f` |

## 3. Cabeçalho em `0x0000`

```
"enable\0\0"          0x000c0000    0x00001000    0x00000a00
4                     0             0xcac1        5             0x500c
```

Leitura: flag (`enable`), dois tamanhos (`0x1000` = 4 KB e `0xa00` = 2,5 KB),
contadores e o **magic `0xcac1`**. O bloco em `0x5000` tem magic `0xcac3`,
contador `0x4f` (79) e o mesmo tamanho `0xc` — assinatura de **registro
versionado** (A/B ou journal de desgaste).

`[HIP]` O par `0xcac1`/`0xcac3` parece ser "cabeçalho de registro" com contador
de geração: a cada gravação, o registro inativo é reescrito e o contador sobe.
Confirmar comparando dois dumps após gravar SN/NB.

## 4. O achado que responde à pergunta do usuário

`read_left/right_dac_master_trim_index_from_storage` — os **MasterTrim existem**,
mas como **calibração por unidade gravada na `fiioconfig`**, lida pelo driver no
boot. Não são kcontrols.

Isso fecha o caso dos "controles fantasma" do `fiio_adev_set_codec_param`:

| Controle pedido pela HAL | Realidade no JM21 |
|--------------------------|-------------------|
| `DAC L/R MasterTrim` | **existe** como índice de calibração na `fiioconfig` (`0xC00`/`0xC04`), aplicado pelo driver |
| `Audio Headset Type` | existe como **sysfs** (`headset_type`) + notifier, não como mixer |
| `DAC MUTE` | feito por evento (`PLAYER_MUTE` → `snd_dac_dai_mute`) |
| `DAC Hifi Boost Mode` | sem contrapartida — é o `+1dB_EN` do `0x80000`, ligado só no volume 120 |
| `DAC line Out`, `LR Balance`, `PO Gain`, `Filter`, `Playback Volume`, `POLO`, `THD C2`, `Audio Format` | kcontrols reais |

Ou seja: **a HAL usa uma API única para funções de naturezas diferentes** —
mixer, sysfs, evento e calibração. O `-22` acontece porque ela procura tudo no
mixer.

## 5. Relação com os outros nós

- `config_sn` / `config_nb` (sysfs) → escrevem em `0x1800` / `0x1C00`.
- `fpga_firmware_name` (sysfs) → escreve em `0x1400`.
- `charging_disable_status`, `power_off_charge_switch`, `usb_boot_switch` →
  também persistem aqui.
- O `numservice.sh` (serviço do init) grava SN/NB no primeiro boot.

## 6. O que ainda falta

| Item | Como fechar |
|------|-------------|
| Semântica exata do cabeçalho (0x0000) | comparar dois dumps após gravar um campo |
| O que é `0x5000` (registro alternativo) | idem |
| Faixa/meaning do trim (`0` = calibrado? não calibrado?) | ler o driver de ganho + variar |
| Checksum do CST812T | comparar com o firmware do touch |
| Se o SN/NB são gravados em fábrica ou no 1º boot | `numservice.sh` + log do `fiio_init.sh` |

## 7. Segurança

O dump contém **SN e NB** (identificadores do aparelho). Por isso:
- fica em `device-baseline/` (gitignored);
- não publicar em issue/print;
- em qualquer relatório, truncar os valores.
