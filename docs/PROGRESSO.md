# Progresso do laboratório JM21

> Atualizado em 2026-10-25, após a sessão 4 (TWRP próprio + Q20).
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
| Apps (`FiiOMusic`, `Settings`, `Scrcpy`) | ✅ | — (issue #7 fechada, inclui Q20) |
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
| ~~Q20~~ | ~~Apps expõem superfície insegura?~~ | **respondida**: 24 componentes exportados sem permissão, todos de UI/modo; `Tape` é skin (127 MB de imagem); nenhum app toca no DAC. `docs/32` §11 | ✅ |
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

**352,8 e 384 kHz tocam (issue #9 fechada):** HAL `halRate 352800`/`384000`,
FPGA `0x48`/`0x88`, e `0x1000B` medido em **7** e **8**. Com o 176,4 k (índice
**5**, FPGA `0x44`), a tabela `SP_SRATE` do cs43198 está **medida em todos os
índices** (1–8), sem valor derivado. A recusa só existe no caminho de intent.

**DSD128 mapeado:** `BYPASS`, `0x1A000002`, `srcRate 176400`, FPGA `0x44`.
`0x1000B` no DSD **não é escrito**: teste decisivo (384 k → DSD128) mostrou que
continuou **8** durante o DSD128. Em DSD, a taxa vive no FPGA (`0x02`) e no
`0x70004`.

**DoP validado:** `reg 0x01 = 0x4E` na saída SPDIF, depois volta a `0x2F`
(DSD nativo) — confere com as duas tabelas do `fpga_config()`.

**EQ em DSD/MQA:** bloqueado pelo próprio app (mensagem no `resources.arsc`),
coerente com o `BYPASS` medido.

**Plano B provado (issues #19 e #21):** kernel compilado numa árvore pública
(5.15.180 + config do aparelho + vermagic forçado) **bootou no JM21** por
`fastboot boot`, carregou **todos** os módulos FiiO e tocou áudio (44,1 k, 384 k
e DSD64). ABI compatível: zero CRC divergente. Ver `docs/45`.

**Ganho analógico (P2) medido:** as três curvas de volume (ganho 0/1/2) foram
varridas com tom tocando e batem **exatamente** com as tabelas do driver
(vol 20: 145/133/113; 30: 125/113/93; 60: 84/72/60; 100: 44/32/20).
Registradores analógicos não mudam → o ganho é **atenuação digital** no DAC.
Ver `docs/38`.

**Modos de operação (issue #8 fechada, resultado negativo):** Pure Music
(`system_mode_value=1`) tem os **mesmos 160 kcontrols** do modo Android. Causa:
o módulo de kernel `mode_select` **não existe** no firmware — `dac_core` e
`anolog_board` logam "get mode_select module failed!" e `system_work_mode` fica
0 sempre. Ver `docs/37`.

**FiiO Music / JNI (issue #2 fechada):** decoder é ffmpeg estático
(`libhello-jni`), SACD/DST em `libsacd`, UAC host próprio em `libUsbAudio`;
`XSeriesConfig` (`t1.i`) dá DSD 88200/7, 176400/8, 352800/9 com
`decoderFormat=1` — igual ao medido. `fiioConfigALLTODSD` não existe no
framework (reflexão morta). Ver `docs/36`.

**Framework/services (issue #3 fechada):** enum completo dos codec params
(0–22), `setMasterVolumeDac` nativo até a HAL, 64 flags `config_fiio_*` com
valores reais (`uac_kernel=false`, `tape_mode_auto_det_sw=false`), allowlists e
broadcasts da FiiO, `system_mode_value`. Ver `docs/33`.

**Auditoria de apps (issue #1 fechada):** 95 APKs de sistema, 12 da FiiO com
hash, `DebugTool`/`FactoryTest`/`EcaiTestAPP` não instalados. Ver `docs/34`.

**ISO do MTP e QFIL/EDL (issues #6 e #5 fechadas):** ISO existe mas os configs
que a expõem estão comentados; não há firehose no OTA — recuperação é por
fastboot. Ver `docs/35`.

**Apps restantes (issue #7 fechada):** EQ é `AudioEffect` do AOSP (sem lib
FiiO em `/vendor/lib/soundfx`); Cast = DLNA dentro do Music; Pod/Tape são
skins; Roon tem plugin próprio; nenhum app fala com o DAC; nós `tape_*` não
existem no JM21; OTA = `jm21pack.fiio.net/JM21-updateCN.zip`. Ver `docs/32`.

**FPGA decodificado (issue #4 fechada):** `tools/fpga_fw_to_fs.py` converte o
`.fw` (RLE `0xDB`, 274 frames de 160 B) para `.fs`; netlist: 803 LUT4, 337 DFF,
52 ALU, 18 `RAM16SDP4`, `IDES10`/`IDDRC` na entrada, `ODDR`/`ELVDS_OBUF` na
saída, `OSCZ` `FREQ_DIV=2`, 11 pinos. É **re-clock + roteamento + clock**, sem
DSP (zero `MULT*`/BSRAM). Ver `docs/31`.

**DSD256 mapeado:** `BYPASS`, `srcRate 352800`, FPGA **`0x68`** (a tabela DSD do
`fpga_config()` soma `0x20` a partir de 352,8 k), `0x70004 = 0x1B` — previsão
confirmada. Escada DSD completa: 64/128/256.

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

---

## 8. Sessão 4 (2026-10-25) — TWRP próprio e Q20

### 8.1 O que foi provado

1. **TWRP próprio compila e sobe** (12.1). Causa raiz do "trava na logo":
   `/system/bin/recovery` não linkava porque `libresetprop.so` nunca entrava no
   ramdisk (`TW_OVERRIDE_SYSTEM_PROPS` liga `TW_INCLUDE_LIBRESETPROP`).
   Correção: `recovery: true` no `Android.bp` do `magisk-prebuilt/resetprop`.
2. **Tela/cores**: `TW_MAX_BRIGHTNESS` 2047→255 e `TW_DEFAULT_BRIGHTNESS`
   1024→128 (painel aceita 0–255; com o valor antigo ficava em 0 = preto).
   `TARGET_RECOVERY_PIXEL_FORMAT` `ABGR_8888`→`RGBX_8888` (Hovatek usa
   `DRM_FORMAT_XBGR8888`; antes vermelho e azul trocavam).
3. **fstab**: o parser do TWRP trata linha iniciada por `/` como formato TWRP;
   o nosso estava em formato AOSP → `Unknown File System` em tudo.
4. **Empacotamento**: ramdisk em **LZ4 legacy** + `mkbootimg` do sistema (o do
   AOSP injeta 4096 bytes de assinatura AVB zerada).
5. **Q20 fechada** (`docs/32` §11): 24 componentes exportados sem permissão,
   nenhum de áudio/hardware; `Tape` é skin de fita (127 MB de imagem).

### 8.2 O que NÃO foi possível

`/data` continua sem montar. Diagnosticado até o fim (`docs/51` §17):
o TWRP 12.1 conversa com `keystore2`, que no Android 13 fala **KeyMint (AIDL)**
e depende do modelo de *lazy AIDL service* do `init` do 13. Cinco bloqueios
intermediários foram resolvidos (VINTF 5.0, `/odm`, libs NDK, keymint como
root), mas o `init` do 12.1 não faz a ponte.

Rota C (AOSP 14 / `twrp-14`) tentada e **bloqueada no build system**: o manifest
do TWRP mistura forks de snapshots diferentes do AOSP (`build/make` 14.1 ×
`build/soong` android-14) e nenhuma das três combinações testadas monta
(`docs/51` §19).

### 8.3 Artefatos

- `~/jm21-artifacts/twrp-jm21-build-own-funcional.img` (sobe, crypto off)
- `~/jm21-artifacts/twrp-jm21-crypto-experimental.img` (rota A, trava no splash)
- `device-tree/fiio/jm21/` no repo = build reproduzível
- `tools/audit-exported.py` = auditoria Q20
