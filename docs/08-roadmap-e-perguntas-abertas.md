# 08 — Roadmap, portões de decisão e perguntas abertas

## 1. Fases

### F0 — Análise offline do firmware ✅ concluída

- OTA inventariado, 19 partições extraídas.
- Kernel, DTBO, HAL, configs de áudio, módulos FiiO, apps e framework mapeados.
- Ferramentas: `payload-dumper-go`, `tools/dt_dump.py`.
- **Saída:** este dossiê.

### F1 — Dispositivo conectado, somente leitura

Objetivo: reconciliar o dossiê com a realidade do aparelho, sem escrever nada.

- Baseline de `getprop`/`dumpsys`/`procfs`/`sysfs` (`docs/06` §2).
- Resolver: bus I2C, endereços dos DACs, DTB aplicada, `mixer_paths` carregado.
- Confirmar: controles `DAC ...` existem em `tinymix`.
- **Portão:** toda a §2 de perguntas abertas respondida ou explicitamente
  bloqueada.

### F2 — Dump próprio e backup

- Dump de `persist`, `fiioconfig`, `modemst*`, `devinfo`, `misc`, `boot`,
  `dtbo`, `vbmeta` (ambos os slots).
- Comparação de hash com o OTA.
- **Portão:** recuperação documentada e testável (`docs/07` §8 completo).

### F3 — RE estática da camada de usuário

- `libfiioaudio.so`, `libfiioaqm.so`, `audio.primary.bengal.so` em Ghidra.
- `FiiOMusic.apk` + JNI em JADX.
- Diff de `framework.jar`/`services.jar` contra AOSP-13.
- **Portão:** contrato `FiiOAudioConfigParams` e lista `FIIO_PACKAGE_NAMES`
  recuperados.

### F4 — RE do kernel

- `cs43198.ko`: mapa de registradores, `volume_table`, filtros, MCLK.
- `dac_core_module.ko`: ioctls e máquina de estados.
- `anolog_board_jm21.ko`: `gain_table`, sequência de energia.
- `gw-fpga.ko`: protocolo SPI e bitstream.
- **Portão:** modelo de dados SoC→FPGA→DAC reproduzível em diagrama.

### F5 — Reconstrução

- Device tree própria + árvore `msm-5.15`.
- Kernel com os drivers FiiO (binários ou reimplementados).
- Avaliação de LineageOS/AOSP-13 com os blobs originais.
- **Portão:** decisão go/no-go baseada em F3/F4, não em entusiasmo.

## 2. Perguntas abertas consolidadas

### 2.1 Bloqueiam todo o resto

| # | Pergunta | Doc |
|---|----------|-----|
| Q1 | Qual barramento I2C hospeda `cs43198@0x30/0x33` e `fpga@0x36`? | 01, 04 |
| Q2 | Qual das 5 DTB base é aplicada no JM21? | 04 |
| Q3 | O bootloader é desbloqueável? Qual o `rollback_index`? | 07 |
| Q4 | Existe pacote QFIL/EDL com `prog_firehose` para o khaje/JM21? | 07 |
| Q5 | O que o FPGA faz no caminho de dados? | 01, 03 |

### 2.2 Áudio (fim técnico)

| # | Pergunta | Doc |
|---|----------|-----|
| Q6 | Dual DAC = mono por chip ou estéreo paralelo somado? | 01, 03 |
| Q7 | DSD nativo sai por I2S do CS43198 ou o FPGA serializa? | 03 |
| Q8 | O FPGA reamostra? O bit-perfect vai até o DAC? | 03 |
| Q9 | `fiio.use.kernel.play` desvia do PAL para o dummy DAI? | 03 |
| Q10 | Qual `mixer_paths_*` é carregado e por qual regra? | 03 |
| Q11 | Qual gatilho troca para `audio_policy_configuration_gaming.xml`? | 03 |
| Q12 | Faixa e passo de `volume_table`, `pogain`, `gain_table` | 01, 03 |
| Q13 | Quantos degraus de ganho a UI expõe (5 no driver) | 01 |
| Q14 | MQA é decode completo ou só core? | 03 |
| Q15 | O aparelho tem captura (mic) ativa? Qual codec? | 01 |
| Q16 | O que há na partição `fiioconfig`? | 02, 04 |

### 2.3 Software

| # | Pergunta | Doc |
|---|----------|-----|
| Q17 | Lista real em `FIIO_PACKAGE_NAMES` | 05 |
| Q18 | O que `com.fiio.control` expõe (AIDL/binder)? | 05 |
| Q19 | `libhello-jni.so` contém o decoder DSD/MQA? | 05 |
| Q20 | Serviços expostos por `DebugTool`/`FactoryTest`/`EcaiTestAPP` | 05 |
| Q21 | Diff exato de `framework.jar`/`services.jar` vs AOSP-13 | 05 |
| Q22 | Conteúdo de `fiio_mtp_driver.iso` | 05 |
| Q23 | Changelog oficial (`log_1.1.1.txt`) | 05 |

### 2.4 Já respondidas (registro)

| Pergunta original do dossiê v1 | Resposta | Evidência |
|--------------------------------|----------|-----------|
| Kernel é 5.4? | **Não: 5.15.41** (`-dirty`) | `[DRV]` |
| HAL é `audio.primary.sm6225.so`? | **Não: `audio.primary.bengal.so`** | `[FW]` |
| Existe `mixer_paths.xml`? | **Não: 4 variantes `bengal_*/scuba*`** | `[FW]` |
| DAC usa I2C ou SPI? | **I2C** (0x30 e 0x33), FPGA usa SPI e I2C | `[DT]` |
| Existe `fiio-framework.jar`? | **Não**, patches em `framework.jar`/`services.jar` | `[FW]` |
| Partições são `boot`/`vendor`/`dtbo`? | A/B com `init_boot`/`vendor_boot` + lógicas | `[FW]` |
| Há bypass de SRC? | Existe caminho `direct_pcm`/`hifi_playback`; extensão real pendente | `[FW]` |

## 3. Backlog de ferramentas

| Item | Por quê |
|------|---------|
| `tools/payload_info.py` | ler `payload.bin` sem Go (manifest protobuf) |
| `tools/img_ls.py` | wrapper `debugfs` para listar/extrair por padrão |
| `tools/props_diff.py` | diff de `build.prop` entre versões de firmware |
| `tools/evidence_ledger.py` | gerar tabela de hashes/arquivos automaticamente |
| `tools/avb_info.py` | ler `vbmeta` sem `avbtool` |

## 4. Versionamento do firmware

- Baseline atual: **1.1.1**.
- Sugestão: uma tag/release por firmware analisado, com hashes em
  `analysis/<versão>/SHA256SUMS.txt`.
- Nunca versionar o payload; versionar só metadados e hashes.
