# 11 — Disassembly do caminho de volume (CS43198 + placa)

> Primeiro passe de disassembly, sem decompilador: `llvm-objdump -dr` sobre os
> `.ko` (ELF relocável aarch64) + extração do `.rodata` guiada pelos símbolos.
> Objetivo: sair do "as strings dizem que existe" para "o código faz isto".

## 1. Método (reprodutível)

```bash
KO=analysis/fw-1.1.1/vendor_dlkm

# funções (símbolos preservados)
readelf -sW $KO/anolog_board_jm21.ko | awk '$4=="FUNC"{print $2, $8}'

# disassembly com relocations = nomes de símbolos resolvidos
llvm-objdump -dr --no-show-raw-insn $KO/anolog_board_jm21.ko

# .rodata: em ET_REL, st_value = offset dentro da seção
readelf -SW $KO/anolog_board_jm21.ko | grep .rodata
#   [3] .rodata PROGBITS  off=0x570 size=0x1a90
```

Ler uma tabela:

```python
d = open('.../anolog_board_jm21.ko','rb').read()
ro = d[0x570:0x570+0x1a90]                 # .rodata
import struct
val = struct.unpack('<121i', ro[0x0ccc:0x0ccc+484])   # vol_table_po_gain_l
```

## 2. Funções com nome no `cs43198.ko`

```
cs43198_i2c_probe / remove      cs43198_config_dac
cs43198_set_sample_rate         cs43198_set_volume_db   (728 bytes)
cs43198_set_dre                 cs43198_set_lpf
cs43198_set_mono_mode           cs43198_set_thd_c2
cs43198_sw_mute                 cs43198_reg_read
cs43198_readable_register       cs43198_volatile_register
cs43198_precious_register
```

`set_volume_db` recebe `(dai, left, right)` e escreve nos **dois** regmaps
(`regmap_l`, `regmap_r`). O driver usa `fiio_regmap_write`,
`fiio_regmap_read`, `dac_dual_regmap_write` e `dac_dual_regmap_update_bits` —
ou seja, o "dual" é tratado no `dac_core`, não no `cs43198`.

## 3. O pipeline de volume (decifrado)

`anolog_board_update_volume` (offset `0x690`, `anolog_board_jm21.ko`), pseudo-C:

```c
void anolog_board_update_volume(void)
{
    dai = g_dac_dai;                       // .bss
    if (!dai->on) return;
    if (dai->system_work_mode == SYSTEM_MODE_BT) return;

    if (dai->gain_update) { ... }          // caminho de troca de ganho (0x80c)

    pogain = dai->pogain;                  // 0..4
    if (dai->volume == 120 && pogain == 0) { ... }   // caso especial (0x7ec)

    if (pogain <= 2)  tab = {l, m, h}[pogain];   // .rodata+0x1a78
    else              tab = h;                   // default do switch

    dai->volume_table = tab;               // offset 0x98

    int code = tab[dai->volume] + gain_table[pogain];
    code = min(code, tab[0]);              // clamp em 255

    dai->volumeL_DB = code;                // offset 0x88
    dai->volumeR_DB = code;                // offset 0x8c
    priv->dac_vol_db = code;               // anolog_board_priv +0x08

    dai->ops->set_volume_db(dai, dai->volumeL_DB, dai->volumeR_DB);
}
```

Confirmações lidas no código:

- `ldrsw x8,[x19,#0xac]` → `pogain`; `ldr x10,[x19,#0x98]` → `volume_table`;
  `lsl x9,x2,#2` → indexação `int[]`.
- `adrp/add` para `.rodata+0x1a78` → array de 3 ponteiros (`l`, `m`, `h`).
- `cmp w2,#0x78` → 120 é caso especial (fim de curso).
- `__cfi_slowpath_diag` antes do `blr x20` → chamada indireta via `ops+0x30`
  (`set_volume_db`), coerente com a vtable do BTF.
- `str w8,[x20,#0x8]` grava em `anolog_board_priv.dac_vol_db`.

## 4. As tabelas (dados extraídos)

5 tabelas × **121 entradas** (0–120), monotônicas decrescentes, exportadas em
`analysis/fw-1.1.1/volume-tables.csv`.

| step | gain_l | gain_m | gain_h | gain_sh | gain_uh |
|------|--------|--------|--------|---------|---------|
| 0 | 255 | 255 | 255 | 255 | 255 |
| 1 | 231 | 219 | 215 | 219 | 213 |
| 10 | 179 | 167 | 153 | 155 | 149 |
| 30 | 125 | 113 | 93 | 100 | 94 |
| 60 | 84 | 72 | 60 | 70 | 64 |
| 90 | 54 | 42 | 30 | 40 | 34 |
| 120 | 24 | 12 | **0** | 10 | 4 |

Observações objetivas:

- Todas começam em **255** e terminam entre **0 e 24**.
- O passo 0→1 cai 24–42 unidades; depois 8, 8, 6, 6, 6, 4, 4… e, do meio para o
  fim, **1 unidade por step** (curva fina no fim, grossa no topo).
- Em step 60: `l`=84, `m`=72, `h`=60.

### Escala — resolvida pelo datasheet `[FW]` externo

O datasheet do CS43198 (DS1156F2, §7.5.3) define `PCM_VOLUME` assim:

```
0000 0000   0 dB
0000 0001  -0,5 dB
...
0111 1000  -60 dB   (default)
1111 1110  -127 dB
1111 1111  mute digital
```

Ou seja: **0x00 = 0 dB** e **0xFF = mute**, 0,5 dB por LSB. Isso inverte a
leitura que estava aqui antes (255 = 0 dB) e muda a interpretação:

| step | l | m | h | sh | uh |
|------|---|---|---|----|----|
| 0 | 0xFF | 0xFF | 0xFF | 0xFF | 0xFF |
| 60 | -42 dB | -36 dB | -30 dB | -35 dB | -32 dB |
| 120 | **-12 dB** | **-6 dB** | **0 dB** | **-5 dB** | **-2 dB** |

Leitura correta:

1. **Step 0 = mute**, step 120 = máximo. A escala de UI é direta (0–120), como
   no aparelho.
2. Os 5 modos **não são compensação de ganho** (hipótese anterior, descartada):
   são curvas diferentes que terminam em níveis digitais diferentes — `h` chega
   a 0 dB, `m` para em −6 dB, `l` em −12 dB. O ganho analógico de cada modo é
   fixo no hardware; a tabela só molda a curva.
3. O `min(code, tabela[0])` faz sentido: `tabela[0]` = 0xFF = mute é o **teto**
   de atenuação, não um "máximo de volume".
4. `gain_table[pogain]` é um offset opcional (zerado na imagem) — se algum dia
   for preenchido, desloca a curva inteira.

O default `0x78` (−60 dB) do chip explica por que o driver **sempre** escreve
volume após o `config_dac`: sem isso o DAC sairia a −60 dB.

## 5. Modos de ganho

Os 5 sufixos (`l`, `m`, `h`, `sh`, `uh`) casam com os símbolos já vistos no
driver: `GAIN_L`, `GAIN_M`, `GAIN_H`, `GAIN_OVER_EAR`, `GAIN_SUPER_OVER_EAR`
(`gain_spe`/`pogain` na struct). O JM21 **inicia em `pogain=2` (High)** —
`anolog_board_load_work` grava `pogain=2`, `pogain_bk=2`,
`volume_table=vol_table_po_gain_h` no boot (`12-energia-e-controles.md` §4).

O switch em `0x824` só mapeia **0→l, 1→m, 2→h** e usa `h` como default (`>2`).
Logo, no caminho normal do JM21, apenas 3 tabelas são alcançáveis; `sh`/`uh`
existem para outros modelos ou outro caminho (ex.: `gain_update`) `[?]`.

## 6. O que já dá para afirmar (e o que não)

| Afirmação | Status |
|-----------|--------|
| Volume é atenuado no **domínio digital do DAC**, com tabela por modo de ganho | fato (disassembly + dados) |
| Ganho analógico é compensado por atenuação digital | fato (tabelas) |
| 121 passos, com passo fino no extremo inferior | fato |
| `volumeL_DB`/`volumeR_DB` recebem o **mesmo** código (balanço à parte) | fato |
| Os dois CS43198 recebem estéreo completo e idêntico (dual DAC paralelo) | fato — `SPECIAL_MODE_2`; ver `12` §4 |
| Registradores de volume: PCM `0x90002`/`0x90001`, DSD `0x70000`/`0x70001` | fato (`cs43198_set_volume_db`) |
| Unidade exata (0,5 dB/LSB) e ponto de 0 dB | hipótese |
| `gain_table` é preenchida em runtime e por quem | desconhecido |
| Uso de `sh`/`uh` no JM21 | desconhecido |

## 7. Próximos alvos (curtos, alto retorno)

1. `cs43198_set_volume_db` completa → mapear código → registrador (L/R) e a
   conversão de dB.
2. `cs43198_config_dac` → sequência de init do chip (registradores + delays).
3. `anolog_board_config_dac` → ordem/tempo de `dac_pwr`, `dac_rst`, `amp_pwr`.
4. `cs43198_readable_register` / `volatile_register` → reconstruir o mapa de
   registradores por faixa de endereço.
5. `anolog_board_set_volume_db` (`0x8f0`) → caminho alternativo chamado pela HAL.

Nada disso exige instalar ferramenta nova: `llvm-objdump` + `pahole` bastam.
