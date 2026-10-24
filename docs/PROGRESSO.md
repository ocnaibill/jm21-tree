# Progresso do laboratório JM21

> Atualizado em 2026-10-23, após a sessão 2 (root).
> Este arquivo é o **placar**. O dossiê (`dossie.md`) é o índice; `docs/` tem o
> detalhe; as issues guardam o que falta.

## Como ler

| Marca | Significado |
|-------|-------------|
| ✅ | **Provado** — evidência primária (hardware, registro lido, hash) |
| 🟨 | **Mapeado** — decompilado/documentado, sem confirmação física |
| ⬜ | **Aberto** — não sabemos ou não testamos |
| ❌ | **Refutado** — testamos e não é assim |

## 1. Placar por camada

| Camada | Cobertura | O que falta |
|--------|-----------|-------------|
| Pacote OTA / partições / AVB | ✅ | — |
| Boot / kernel / módulos | ✅ | — |
| Device tree (GPIO, I²C, jack) | ✅ | — |
| Drivers FiiO (`dac_core`, `anolog_board`) | ✅ | consumidor de `gain_pwr_update` |
| Driver do DAC (`cs43198`) | ✅ | faixa/uso do trim calibrado |
| FPGA (driver, I²C, MCLK) | 🟨 | **o que o bitstream faz**; `fpga_config` confirmado como cache |
| HAL (`libfiioaudio`, `libfiioaqm`) | ✅ | MQA completo × core; label `MQA` com `isMQA:false` |
| Apps (`FiiOMusic`, `Settings`, `Scrcpy`) | ✅ | inventário dos demais apps (issue #7) |
| Plano de controle (kcontrols/props/sysfs) | ✅ | modos alternativos (issue #8) |
| `fiioconfig` | 🟨 | semântica do cabeçalho e do journal (`0xcac1`/`0xcac3`) |
| **Medição elétrica / bancada** | ⬜ | **tudo** — nenhuma medição física ainda |

## 2. O que já está **provado** (não é mais hipótese)

1. Caminho completo do áudio: app → AudioFlinger → HAL → kcontrol → `dac_core` →
   `anolog_board` → `cs43198` (I²C) / FPGA (I²C+SPI).
2. Volume: UI 0–120 → tabela por modo → registrador. Validado em 5 pontos e no
   registro (`0x5D` = 93 = `h[30]`).
3. **Par diferencial**: `0x90004` = `0x00` no chip L e `0x0C` no R, volumes
   idênticos nos dois.
4. Identidade do chip: `DEVID 0x431980`, `REV_ID 0xA1`.
5. Energia: `0xFE` → `0xAE` no power-up; GPIOs reais (TLMM base 389).
6. Jack: 3,5 mm = `single po`, GPIO 102/103, ADC 18.
7. FPGA no caminho: `power=on`, `bypass=0`, versão `0xf2510003`, MCLK 22/24 MHz
   a 44,1 kHz.
8. HAL não reamostra 44,1 kHz: `srcRate 44100 → halRate 44100`, 16→32 bits.
9. Bootloader destravado e SELinux permissivo (medidos).
10. `fiioconfig`: layout de SN/NB/trim/checksum/fw.

## 3. Perguntas abertas, com o caminho de fechamento

| # | Pergunta | Como fechar | Custo |
|---|----------|-------------|-------|
| Q5 | O que o FPGA faz? Só reclock/roteia? | bitstream + dmesg por taxa (P1b) | médio (issue #4) |
| Q6 | Ganho analógico existe além do digital? | `read_all_regs` em cada `PO Gain` + medição | baixo + bancada |
| Q9 | `fiio.use.kernel.play` muda o caminho? | alternar e observar `fpga_config`/regs | baixo |
| Q12 | `+1dB_EN` liga em 120? | volume 120 e ler `0x80000` | baixo (cuidado) |
| Q13 | Quantos degraus a UI expõe? | menu de ganho + `DAC PO Gain` | baixo |
| Q16 | Trim de calibração: o que muda? | variar trim em `fiioconfig` + regs | médio |
| Q20 | Apps expõem superfície insegura? | issue #7 | médio |
| Q24 | FiiO libera fonte GPL? | aguardar ticket; plano B em `17` | externo |
| Q25 | Modos alternativos expõem mais controles? | issue #8 | baixo |
| Q26 | DSD nativo: quais registradores? | `read_all_regs` tocando DSD | baixo |
| Q27 | ~~Relação clock ↔ família de taxa~~ | **respondida**: `0x1000B` = índice do driver; FPGA reg 0x02 = família + multiplicador | ✅ |
| Q28 | MQA é decode completo? | faixa MQA + log/`read_all_regs` | baixo |

## 4. Próximos experimentos (priorizados)

### P1 — Matriz de estados DAC/FPGA — ✅ rodada 1 feita (`docs/28`)

**Feito:** 44,1 / 48 / 96 / 192 kHz capturados. Confirmado: zero reamostragem
(`srcRate = halRate`), DAC idêntico entre taxas, `fpga_config` é cache, e o
rótulo de modo é um bitmask de estágios (`MQA`, `ALLTO32BIT`) — não descreve o
arquivo. 384 kHz **recusado pelo app** (arquivo válido).

**P1b feita:** os registradores ASP são fixos; a taxa vai para o **FPGA**
(`reg 0x02`: 0x41 / 0x81 / 0x82 / 0x84 = família + multiplicador).

**P1c feita:** `0x1000B` (SP_SRATE) medido em 5 taxas e **igual à tabela do
driver**; FPGA confirmado em 88,2 (`0x42`).

**352,8 e 384 kHz tocam (issue #9 fechada):** HAL `halRate 352800` (3×) e
`halRate 384000` (5×); FPGA `0x48` e `0x88` — previsões do modelo confirmadas.
A checagem `UNSUPPORTED` não dispara neste modelo. Meu diagnóstico anterior
("política do app a 192 k") estava errado por leitura parcial do log.

**DSD64 mapeado:** HAL entrega `0x1A000002` (DSD_32BIT) a 88,2 kHz em
`mode BYPASS`; `0x70004=0x13`, `0x20000=0x0A`, `0x70000/1=95`, FPGA `0x42`.
Ver `docs/29-dsd-e-384k.md`.

### (original) P1 — escopo

Para cada condição, capturar: `read_all_regs`, `fpga_config`, `fpga_gw_version`,
`board_vol_dac`, `dac_vol`, `dmesg` e a linha `match_audio_hardware_params`.

| Variável | Pontos |
|----------|--------|
| Taxa | 44,1 / 48 / 96 / 192 / 384 kHz |
| Formato | PCM 16/24, DSD64/128/256 (se houver arquivos) |
| EQ | off / on |
| Volume | 30 / 90 / 120 |

Responde: clock por família (Q27), DSD (Q26), `+1dB_EN` (Q12), se o FPGA
reconfigura por taxa (Q5), se EQ toca o DAC (não deveria).

**Saída:** `docs/28-matriz-de-estados.md` + dump por condição em
`device-baseline/`.

### P2 — Ganho analógico (Q6)

`read_all_regs` com `DAC PO Gain` = 0,1,2,3,4 e volume fixo. Se nenhum
registrador mudar, o ganho é digital puro + possível chaveamento fora do DAC
(regulador/GPIO). Confirmar com `regulator_summary` e dmesg.

### P3 — Bancada (precisa de hardware)

Medir: Vrms por modo de ganho, topologia por amp (mutando um chip), crosstalk.
Requer carga (o FT1 serve) + multímetro/interface.

### P4 — FPGA (issue #4)

Análise do bitstream GW1NZ-1: se há DSP ou só PLL/IO.

## 5. Como saber que "está andando bem"

Três sinais objetivos, todos verificáveis:

1. **Hipóteses viram fatos com evidência primária.** O placar em §1 só muda
   quando há registro lido, hash conferido ou medição — nunca por leitura de
   review.
2. **Conflitos são fechados, não acumulados.** Hoje: topologia ❌ hipótese
   "um DAC por canal" e ✅ par diferencial; "rotas são seletor" ❌; "PAL fixa
   192 kHz" ❌; "bootloader travado"/"SELinux enforcing" ❌ (medidos).
3. **Cada experimento gera artefato reprodutível.** Dump + comando + doc. Se
   não dá para repetir, não conta.

## 6. Métricas atuais

- **41 achados** no resumo do dossiê.
- **28 documentos** (`docs/00`–`27` + este).
- **8 issues** abertas (as que dependem de bancada, externo ou decisão).
- **3 APIs "fantasma"** encontradas e explicadas (HAL × kernel).
- **0 processos rodando no aparelho** deixados pela sessão (playback pausado).

## 7. Como atualizar este arquivo

Ao fim de cada sessão:
1. Mover itens entre ✅ / 🟨 / ⬜ na tabela §1.
2. Fechar/abrir linhas na tabela §3.
3. Registrar o experimento novo em §4 com o link do doc.
4. Commit `progress: <resumo>`.
