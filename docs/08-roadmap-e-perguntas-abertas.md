# 08 — Roadmap, portões de decisão e perguntas abertas

> **Revisitado em 2026-10-24**, depois do P1 (matriz de taxas + DSD), do netlist do
> FPGA, do diff de framework/services, da auditoria de apps, dos modos de
> operação, do ganho analógico e do modo USB DAC. Cada item agora tem estado
> explícito: ✅ respondida · 🟨 parcial · ⬜ aberta · ❌ refutada.

## 1. Fases

| Fase | Estado | O que fechou |
|------|--------|--------------|
| **F0** — análise offline do firmware | ✅ | OTA, 19 partições, kernel, DTBO, HAL, módulos, apps, framework |
| **F1** — aparelho conectado, leitura | ✅ | baseline, root (Magisk), kcontrols, registradores, P1 completo |
| **F2** — dump próprio e backup | 🟨 | OTA + `fiioconfig` dumpados; falta backup completo de `persist`/`modemst`/ambos os slots |
| **F3** — RE da camada de usuário | ✅ | HAL (`docs/19`), FiiO Music/JNI (`docs/36`), framework/services (`docs/33`), apps (`docs/32`,`docs/34`) |
| **F4** — RE do kernel | ✅ | `cs43198` (`docs/11`), `dac_core` (`docs/19`), `anolog_board` (`docs/12`), FPGA (`docs/30`,`docs/31`) |
| **F5** — reconstrução | ⬜ | depende de decisão go/no-go — **não iniciada de propósito** |

## 2. Perguntas — estado atual

### 2.1 Estruturais

| # | Pergunta | Estado | Evidência |
|---|----------|--------|-----------|
| Q1 | Barramento I2C de `cs43198@0x30/0x33` e `fpga@0x36` | ✅ | **i2c-2** para os dois DACs e o FPGA (`docs/01` §, `docs/04`) |
| Q2 | Qual DTB base é aplicada | ✅ | **khaje**, overlay JM21 no índice 40 (`docs/04`, `tools/dt_dump.py`) |
| Q3 | O bootloader é desbloqueável | ✅ | já **desbloqueado**: `flash.locked=0`, `verifiedbootstate=orange` |
| Q4 | Pacote QFIL/EDL com firehose | ❌ | **não existe** no OTA nem nas partições; recuperação por fastboot (`docs/35`) |
| Q5 | O que o FPGA faz no caminho de dados | ✅ | **re-clock + roteamento + geração de clock**; sem DSP (`docs/31`) |
| Q24 | A FiiO fornece firmware antigo mediante SN | ⬜ | e-mail GPL enviado; sem resposta (`docs/17`) |

### 2.2 Áudio

| # | Pergunta | Estado | Evidência |
|---|----------|--------|-----------|
| Q6 | Dual DAC: mono por chip ou paralelo | ✅ | `SPECIAL_MODE_2`, estéreo paralelo (`docs/12`) |
| Q7 | DSD nativo sai do CS43198 ou o FPGA serializa | ✅ | **FPGA**: `fmt=3`, `reg 0x01=0x2F` medido; DAC recebe DSD pela página 7 (`docs/29`) |
| Q8 | O FPGA reamostra? Bit-perfect | ✅ | **não reamostra** (sem DSP, `BYPASS`); taxas batem 1:1 (`docs/29`,`docs/31`) |
| Q9 | `fiio.use.kernel.play` desvia para o dummy DAI | ❌ | **não muda nada** no caminho interno: com `1` e `0`, HAL (`mode MQA`, 44100) e `snd_dac_startup` idênticos. Propriedade inerte aqui (provável legado/outro caminho) |
| Q10 | Qual `mixer_paths_*` é carregado | 🟨 | placa é `bengal-idp-snd-card` → variante `idp` (os 4 arquivos existem no `vendor.img`) |
| Q11 | Gatilho do `audio_policy_configuration_gaming.xml` | 🟨 | propriedade **`vendor.audio.gaming.enabled`** e `/data/vendor/gaming` achadas no `vendor.img`; quem a escreve não foi identificado |
| Q12 | Faixa e passo da tabela de volume | ✅ | 121 passos, 0,5 dB; **três curvas medidas** (`docs/11`, `docs/38`) |
| Q13 | Quantos degraus de ganho a UI expõe | ✅ | **3** (0/1/2 = baixo/médio/alto); driver tem 5 tabelas (`docs/38`) |
| Q14 | MQA é decode completo ou só core | 🟨 | quem decodifica é o **DAC**, não o app (`docs/36`); profundidade não provada |
| Q15 | Existe captura (mic) ativa | ✅ | **não há**: `tinycap` em pcm d=0/9/11/15/17 devolve **0 frames**; o WCD937x tem rotas DMIC no DT, mas nada conectado |
| Q16 | O que há em `fiioconfig` | ✅ | header, trims, SN/NB, journal de wear (`docs/26`) |

### 2.3 Software

| # | Pergunta | Estado | Evidência |
|---|----------|--------|-----------|
| Q17 | Lista real de `FIIO_PACKAGE_NAMES` | ✅ | duas listas (AMS e OomAdjuster), mais `com.alex.debugtool_player` (`docs/33`) |
| Q18 | O que `com.fiio.control` expõe | ✅ | **nada**: o pacote não está instalado; só aparece em allowlists (`docs/34`) |
| Q19 | `libhello-jni.so` tem decoder DSD/MQA | ❌ | é **ffmpeg estático**; SACD/DST fica em `libsacd.so` (`docs/36`) |
| Q20 | Serviços de `DebugTool`/`FactoryTest`/`EcaiTestAPP` | ✅ | **não instalados** no aparelho (`docs/34`) |
| Q21 | Diff de `framework.jar`/`services.jar` | ✅ | enum de codec params, `setMasterVolumeDac`, 64 flags, allowlists (`docs/33`) |
| Q22 | Conteúdo de `fiio_mtp_driver.iso` | ✅ | CD de drivers; configs que o expõem estão comentados (`docs/35`) |
| Q23 | Changelog oficial | ✅ | histórico no fórum, resumido em `docs/05` §5 |

### 2.4 Perguntas novas (surgiram nas sessões)

| # | Pergunta | Estado | Onde |
|---|----------|--------|------|
| N1 | Por que o módulo de kernel **`mode_select`** não existe? Algum build o traz? | ✅ | **não é embarcado** no 1.1.1 (nem no `/vendor_dlkm` do aparelho, nem na imagem); `dac_core`/`anolog_board` falham ao obtê-lo e `system_work_mode` fica 0. Não há firmware posterior (manifesto do servidor) |
| N2 | Há **dois caminhos de volume** (`setMasterVolumeDac` nativo e `DAC Playback Volume`). Qual atua quando? | ✅ | **um efeito, duas portas**: só `0x90001/2` muda; escrita direta no kcontrol é ignorada — o framework é autoritativo (`docs/33` §2) |
| N3 | Os 4 kcontrols ausentes (`DAC MUTE`, `MasterTrim L/R`, `Hifi Boost`, `Headset Type`) dependem do `mode_select`? | ✅ | **não existem neste build/modelo**: ausentes em Android, em Pure Music e após reiniciar a HAL. A dependência do `mode_select` segue como hipótese (N1) |
| N4 | `gw_fpga_firmware_jm21_2.fw` (user code `0xF2510004`) não descomprime no tamanho esperado — build parcial? | ✅ | **outro design**, não delta: duas chaves RLE, 23 pinos, `I3C_IOBUF` (`docs/31` §4) |
| N5 | Os 63 bytes entre a linha `3B` e os frames: header ou bloco pós-frames? | ✅ | **nem um nem outro**: são fluxo comprimido; com a chave `0xDB` os dados começam no offset 68 e dão 274×160 exatos (`docs/30` §8) |
| N6 | `uac_kernel_enabled=false` mas o gadget UAC funciona — o que a flag controla? | 🟨 | gadget é `uac2.0` do kernel (configfs); sem FFS de UAC e sem binário de userspace. A flag deve descrever o **offload QMI** (`snd_usb_audio_qmi`), não o gadget (`docs/39` §6) |
| N7 | Referências a pacotes ausentes (`com.fiio.control`, `com.fiio.dream`, `com.alex.debugtool_player`, `com.example.fiiotestappliction`) | ✅ | são resíduos de build compartilhado (`docs/33`,`docs/34`) |

## 3. O que continua valendo como pergunta de **bancada**

Só o que exige instrumento (não software): potência real (Vrms) por modo de
ganho, impedância de saída, crosstalk e a topologia física dos dois amps. O
resto do áudio está medido por registrador.

## 4. Backlog de ferramentas

| Item | Estado |
|------|--------|
| `tools/payload_info.py` | pendente |
| `tools/img_ls.py` | pendente (usamos `debugfs` direto) |
| `tools/props_diff.py` | pendente |
| `tools/evidence_ledger.py` | pendente |
| `tools/avb_info.py` | pendente |
| `tools/dt_dump.py` | ✅ feito |
| `tools/fpga_fw_to_fs.py` | ✅ feito (novo) |

## 5. Versionamento do firmware

- Baseline: **1.1.1** (tag `fw-1.1.1-baseline`).
- Hashes em `analysis/<versão>/`, binários fora do git.
- Nunca versionar payload; só metadados e hashes.
