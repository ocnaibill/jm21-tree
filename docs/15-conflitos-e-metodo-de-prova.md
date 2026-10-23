# 15 — Conflitos: como decidir, e o que já foi decidido

> Regra do laboratório: conflito não se resolve por plausibilidade. Cada item
> abaixo tem (a) as hipóteses, (b) o teste discriminante, (c) o critério de
> aceitação. Só entra como fato o que passar por (b) e (c).

## 0. Princípios de prova usados aqui

1. **Código vence review.** Um registrador escrito com valor documentado no
   datasheet é evidência mais forte que a descrição de um review ou de um site.
2. **Teste discriminante > teste confirmatório.** Só vale o experimento em que
   hipóteses rivais dão resultados diferentes; medir "funciona" não distingue
   nada.
3. **Uma medição não fecha um modelo.** Topologia precisa de pelo menos dois
   testes independentes (elétrico + comportamental).
4. **Registrar o que refutaria.** Cada hipótese leva junto o resultado que a
   derrubaria — se nenhum resultado possível a derruba, ela não é científica.

## 1. Conflito A — topologia dos dois DACs / SE × BAL

### Hipóteses

| # | Hipótese | Origem |
|---|----------|--------|
| A1 | Cada DAC toca um canal (L/R); BAL é soma analógica | leitura "dual DAC" |
| A2 | Cada DAC alimenta uma saída (um para SE, um para BAL) | review `[EXT]` |
| A3 | Os dois DACs recebem o mesmo estéreo, com **polaridade invertida** entre eles (par diferencial) | nosso código |

### Evidência decisiva (já obtida) — **A3**

`cs43198_config_dac`, ramo PCM, `SPECIAL_MODE_2` `[FW]`:

```c
fiio_regmap_write(name, dac_dai->regmap_l, 0x90004, 0x00);   // chip "L"
fiio_regmap_write(name, dac_dai->regmap_r, 0x90004, 0x0C);   // chip "R"
```

`0x90004` é **PCM Path Signal Control 2** (datasheet §7.5.6):

| bit | nome | valor em R |
|-----|------|-----------|
| 3 | `PCM_INV_A` | **1** |
| 2 | `PCM_INV_B` | **1** |
| 1 | `PCM_SWAP_CHAN` | 0 |
| 0 | `PCM_COPY_CHAN` | 0 |

Ou seja: **o chip "R" recebe exatamente o mesmo sinal, com os dois canais
invertidos**. Isso derruba A1 (não há divisão por canal) e confirma A3: é um par
diferencial formado por dois chips idênticos.

Reforços independentes:

- `cs43198_set_volume_db` em `SPECIAL_MODE_2` escreve **o mesmo** valor nos dois
  regmaps (`0x90002` = L, `0x90001` = R) — mesma informação nos dois chips.
- `cs43198_set_mono_mode` **não** é chamado nesse modo (só em `SPECIAL_MODE_1` e
  `_3`) — cada chip está em estéreo.
- `post_power_control`: `amp_pwr` liga sempre; `amp2_pwr` liga **só** para
  `current_output_type >= 3`. Bate com "SE usa um amp, BAL usa os dois".

### O que ainda não está provado

| Pergunta | Teste discriminante | Critério |
|----------|---------------------|----------|
| Qual chip alimenta o SE? | Mutar digitalmente **um** chip (escrever 0xFF em `0x90001/2` de um regmap) e medir SE e BAL | SE cai → o chip mutado é o do SE; BAL cai pela metade e continua → soma diferencial |
| BAL é diferencial de verdade? | Medir L+ e L− (ou a tensão entre os dois ramos) com tom de 1 kHz | Sinal em antifase nos dois ramos |
| `out_sel` muda o quê? | Alternar `output_type` e medir continuidade dos relés (GPIO 29/86) | Já sabemos por código: é o caminho SPDIF; confirmar que não troca SE/BAL |
| Crosstalk 110 dB no BAL é coerente? | Medir crosstalk nos dois modos | BAL muito melhor que SE → confirma drive diferencial |

## 2. Conflito B — onde o "ganho" é aplicado

### Hipóteses

| # | Hipótese | Origem |
|---|----------|--------|
| B1 | Chaveamento na realimentação dos SGM8262 | pesquisa `[EXT]` |
| B2 | `OUT_FS[1:0]` / `HV_EN` / `+1dB_EN` do CS43198 | datasheet + nosso código |
| B3 | Puramente digital (as 5 tabelas) | nosso código |

### Evidência já obtida

- **B1 é impossível como descrito**: o SGM8262 não tem pino de controle — é um
  op-amp de ganho fixo. Só haveria chaveamento se houvesse rede resistiva
  externa com chaves. `[?]` sem esquemático.
- `anolog_board_update_volume` **não escreve GPIO nenhum**; com `gain_update`
  ela só troca a tabela e recalcula os códigos `[FW]`.
- `gain_table[pogain]` (5 `int`) está **zerada** na imagem — o modo não desloca a
  curva por offset.
- O único efeito de hardware visto com volume é **`+1dB_EN`**:

```c
gain_spe = (volume == 120 && current_output_type == 0);
...
dac_dual_regmap_update_bits(dai, 0x80000, 0x1, gain_spe == 1);   // bit 0 = +1dB_EN
```

`0x80000` = **Analog Output Control 1**: bits [5:4] = `OUT_FS`, bit 0 =
`+1dB_EN` (datasheet §7.5.1). O init fixa `0x80000 = 0x30` (OUT_FS = 11) e
**nunca muda OUT_FS** — só o `+1dB_EN` no volume máximo.
- `gain_pwr_update` (marcado ao **cruzar** o modo 4) existe na struct, mas
  **nenhum módulo decompilado o lê**. `[?]` Pode estar no kernel embutido ou em
  módulo ainda não analisado.

### Leitura atual (provisória, honesta)

B3 é o que o código mostra para 0–3; o modo 4 (super over-ear) provavelmente
muda **topologia de energia** (`gain_pwr_update` + mensagem "power need change,
so power restart!!!"), o que sugere uma alimentação mais alta (HV_EN por
hardware). B2 fica como mecanismo plausível para esse último degrau.

### Testes que decidem

1. **Bancada elétrica** (com o aparelho, sem abrir): tom 1 kHz a 0 dBFS, carga
   32 Ω, volume fixo em 120; medir Vrms em cada modo.
   - Se a diferença medida ≈ diferença das tabelas digitais (0 / −6 / −12 dB),
     **B3 confirmado**.
   - Se houver degrau extra, ele é analógico → procurar qual.
2. **Regmap dump** (root): `cat /sys/kernel/debug/regmap/*/registers` antes e
   depois de trocar o ganho.
   - `0x80000` mudando → B2 confirmado naquele modo.
   - Nada mudando → B3.
3. **Corrente de alimentação** em cada modo, com o mesmo nível de saída: modo
   com mais ganho analógico puxa mais corrente para o mesmo SPL.

## 3. Conflito C — FPGA no caminho (já resolvido no essencial)

| Fato | Evidência |
|------|-----------|
| FPGA tem driver próprio, bitstreams A/B e é alimentado por `fpga_pwr_en` (GPIO 3) | `[DT]` `[DRV]` |
| FPGA muda de firmware/energia por **modo**: `LOCAL_PLAYBACK` e `USB_XMOS` ligam; `USB_DAC` e `BT_QCC` não | `fpga_ctrl_power_by_mode`, enum `fpga_work_mode` |
| **FPGA gera o MCLK dos DACs** | `fpga_set_mclk()` loga "set dac_mclk 90/98MHz", "45/49MHz", "22/24MHz" |
| FPGA faz SPDIF TX/RX, HDMI code, XMOS, seleção de MCLK e *fill clock* | `fpga_config*`, `fpga_config_spdif_*`, `fpga_fill_clk` |

**Consequência arquitetural:** o SoC não é o clock master dos DACs. O caminho é
`SoC → (MI2S/TDM) → FPGA → (I2S + MCLK 22/24, 45/49, 90/98 MHz) → CS43198`.
O enum `AUDIO_DAC_MCLK_22/45/90` cobre as **duas famílias** (×1 e ×1,0884), então
a escolha 44,1 × 48 kHz acontece no FPGA.

`[?]` Continua em aberto se o FPGA faz apenas *clocking/roteamento* ou também
processa amostras. A struct `fpga_config_params` não tem campo de razão de
reamostragem, o que favorece "só roteia e reclocka".

## 4. Protocolo de bancada (para quando o aparelho chegar)

Pré-requisitos: carga resistiva 32 Ω (e 16/300 Ω), interface de áudio com
entrada, multímetro, e root para os dumps de regmap.

1. **Baseline**: 1 kHz, 0 dBFS, volume 120, High gain, EQ off, sem fone
   detectado (forçar saída), SE e BAL.
2. **Escala de volume**: varrer 0/30/60/90/120 e medir. Comparar com
   `volume-tables.csv` (0,5 dB/LSB). Desvio sistemático → há etapa analógica
   no caminho.
3. **Modos de ganho**: mesmo sinal, medir os 5 (ou os que a UI expõe).
4. **Isolamento de canal**: mutar um chip pelo regmap (root) e medir SE/BAL.
5. **Taxas**: 44,1/48/96/192/384 kHz e DSD64/128/256; conferir
   `/proc/asound/card*/pcm*/sub*/hw_params` e o MCLK selecionado (log do FPGA).
6. **Coaxial**: 3,5 mm em modo coax → capturar e comparar bits com a fonte.
7. **Repetir tudo duas vezes** com aparelho reiniciado — histerese é dado.

### Critérios de aceitação

- Modelo de topologia: testes 4 e 1 concordam com o código (inversão + amps).
- Modelo de ganho: teste 3 + regmap dump (teste 2 do §2) apontam para a mesma
  hipótese.
- Bit-perfect: teste 6 com captura idêntica bit a bit.

## 5. O que ainda vale pesquisar fora do aparelho

- **Esquemático** (pedido GPL/serviço à FiiO): resolve topologia e ganho de uma
  vez, sem inferência.
- **Kallsyms do kernel**: quem chama os 4 wrappers GPL e se existe código FiiO
  embutido no `Image`.
- **`fiio_snd_soc_dummy_dai.ko`**: é o DAI que o ALSA do Android usa; é o último
  elo entre o `dac_core` e o framework.
- **Bitstream do GW1NZ-1**: se o FPGA só reclocka, o bitstream deve mostrar
  PLL/IO e nenhum DSP de áudio.
