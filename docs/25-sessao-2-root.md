# 25 — Sessão 2: root e leitura real do hardware

> Magisk em `init_boot_a`, slot `_a`, build 1.1.1. Escrita única: `init_boot_a`.
> Nada mais foi flashado. Dumps com conteúdo pessoal (SN) ficam em
> `device-baseline/` (fora do git).

## 1. Root

```
fastboot getvar current-slot  -> a
fastboot getvar product       -> khaje
fastboot getvar unlocked      -> yes
fastboot flash init_boot_a magisk_patched-30700_LiUPh.img -> OKAY
```

Log do Magisk (no próprio aparelho): `HEADER_VER [4]`, `KERNEL_SZ [0]`,
`RAMDISK_SZ [2005925]`, `Stock boot image detected`,
`KEEPVERITY=[true] KEEPFORCEENCRYPT=[true]`, `VBMETA` preservado.

Depois do reboot: `su -c id` → `uid=0(root) ... context=u:r:magisk:s0`.
Boot normal, `verifiedbootstate` continua `orange`.

## 2. Kcontrols — os 8 reais (de 160 no card)

`tinymix -D 0` (com root):

```
137 INT  DAC Playback Volume        30
138 INT  DAC line Out Volume         0
139 INT  DAC LR Balance             20   (centro; ±20)
140 INT  DAC PO Gain                 2   (High)
141 INT  DAC Digital Filter Mode     2
144 INT  Audio POLO Mode             3
145 INT  DAC THD C2                  0
146 INT  Audio Format                0
```

`[FW-DEV]` **Confirmado o achado dos "controles fantasma"**: não existem
`DAC MUTE`, `DAC L MasterTrim`, `DAC R MasterTrim`, `DAC Hifi Boost Mode` nem
`Audio Headset Type`. A HAL os pede (tabela de 12) e recebe `-22`.

Também confirma: `DAC Playback Volume` = 30 = exatamente o `dac_vol`/stream
volume. O volume da UI vai direto para o controle ALSA.

## 3. Registradores reais (`dac_read_reg`)

O driver expõe `dac_read_reg`: escreve-se o **número decimal** do registrador e
lê-se o valor **decimal** (lê sempre `regmap_l`).

### Ocioso (DAC em power-down)

```
0x80000 = 48 (0x30)    OUT_FS=11, +1dB_EN=0
0x90000 = 2  (0x02)    filtro: high-pass
0x90001 = 120 (0x78)   volume B no default do chip (-60 dB)
0x90002 = 120 (0x78)   volume A no default
0x90003 = 168 (0xA8)
0x20000 = 254 (0xFE)   Power Down Control: tudo desligado
0x10010 = 0            pop-free/DXD travado
```

### Tocando (volume 30, 3,5 mm, FLAC 44,1/16)

```
0x80000 = 48  (0x30)   OUT_FS=11, +1dB_EN=0   (só liga no volume 120)
0x90000 = 66  (0x42)   filtro preset 2        (kcontrol = 2)
0x90001 = 93           volume canal B
0x90002 = 93           volume canal A
0x90003 = 172 (0xAC)   caminho PCM ativo/sem mute
0x20000 = 174 (0xAE)   power-up: bits 6 e 4 limpos de 0xFE
0x10010 = 0
0x70000 = 120          volume DSD no default (não usado)
```

**Três confirmações de ouro:**

1. `0x90002 = 0x90001 = 93` — os dois canais com o **mesmo código**, e 93 é
   exatamente `vol_table_po_gain_h[30]` (validado antes em 5 pontos).
2. `0x20000` vai de `0xFE` → `0xAE`: exatamente `0xFE & ~0x40 & ~0x10`, a
   sequência de power-up que decompilamos.
3. `0x90000 = 0x42` casa com o kcontrol de filtro = 2 (bit 6 + bit 1).

## 4. Comandos de rota (`dac_ctrl`)

O sysfs `dac_ctrl` aceita strings:

```
route_po     route_lo     route_ba     route_balo
```

É o seletor de saída por software — o caminho para testar PO/LO/BAL/SPDIF sem
passar pela UI. `[?]` Efeito exato de cada um ainda não testado (exige trocar
rota com o fone plugado).

## 5. `fiioconfig` — o último desconhecido, aberto

Partição: `/dev/block/mmcblk0p71`, **10 485 760 bytes (10 MB)**, mas só
**48 KB** têm dados (12 blocos de 4 KB). Dump guardado em
`device-baseline/fiioconfig/` (contém o SN — não vai para o git).

Estrutura observada:

| Offset | Conteúdo |
|--------|----------|
| `0x0000` | cabeçalho ASCII `"enable"` + campos (`0x0c`, `0x1000`, `0x0a00`, `4`, `0`, **`0xcac1`**, `5`, `0x500c`) |
| `0x04b0` | string `"/fiioconfig"` |
| `0x1000` | contadores (2, 3) |
| `0x1800` | **SN** — string de 14 chars + preenchimento `0xFF` |
| `0x5000` | segundo registro, com marcador **`0xcac3`** |

`[FW]` O módulo `fiio_config.ko` usa `kernel_read`/`kernel_write` direto no
block device e tem os modelos de string `FiiOSN00000000` / `FiiONB00000000`,
além dos atributos `config_sn` / `config_nb`. O marcador `0xcac1`/`0xcac3` por
bloco sugere **registros versionados** (A/B ou journaling de desgaste).

`[?]` Falta casar o header com a struct do módulo (BTF do `fiio_config.ko` não
expõe struct com nome `fiio*`; o parsing é por offset literal).

## 6. O que ficou de fora (e por quê)

- **`i2cdetect`**: não existe `/dev/i2c-*` no Android (i2c-dev não habilitado).
  Os endereços já estavam confirmados por `/sys/bus/i2c/devices`.
- **dump de regmap via debugfs**: `CONFIG_REGMAP_DEBUGFS` não está ligado no
  kernel. O caminho é o `dac_read_reg` (usado acima).
- **`+1dB_EN` no volume 120**: não testado — é alto demais para fazer sem
  combinar. Fica para a próxima, com o fone longe.

## 7. Conferência das partições após o flash

```
init_boot_a (aparelho) = de0c6dea… → idêntico à imagem patchada   ✔
init_boot_b (aparelho) = ed08a8e1… → ≠ do nosso OTA 1.1.1
nosso init_boot.img (OTA 1.1.1) = 858655e7…
```

**Interpretação:** o slot **B está em outro build** (provável versão anterior,
anterior à última atualização OTA — normal em A/B: só o slot ativo é atualizado).
Isso não indica problema, mas muda o plano de rollback: **restaurar pelo nosso
`init_boot.img` do OTA 1.1.1**, não pelo slot B.

O `init_boot_a` bater exatamente com a imagem patchada fecha a prova de que a
escrita foi correta e que o boot atual veio dela.

## 8. Próximos passos

1. Decodificar o `fiioconfig` (header, registros `0xcac1`/`0xcac3`, SN/NB) e
   escrever `docs/26-fiioconfig.md`.
2. Testar `dac_ctrl route_po/lo/ba/balo` e observar `headset_type`,
   `board_output_type`, ganho de amp e `0x20000` em cada rota.
3. Testar `+1dB_EN` em 120 (com cautela) e confirmar o bit em `0x80000`.
4. Medição de bancada (topologia/ganho) com o FT1.
5. Comparar `init_boot_a` do aparelho com o nosso (fechar a dúvida de build).
