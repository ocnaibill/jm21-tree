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

## 9. Sessao 5 (2026-10-27) — audio fora do Android, mapa do DSD e GSI medida

### 9.1 O que foi fechado

| tema | resultado |
|---|---|
| #13-B (audio no TWRP) | card `bengal-idp-snd-card` sobe; `tinymix` com 160 controles; **playback impossivel por ALSA** (ver 9.2) |
| bug do "DSD nativo por USB" | **era falso** — ver 9.3 |
| #12 (GSI) | **medida**: A13 GSI boota, vendor sobrevive, audio nao (ver 9.4) |
| #22 (termico/carga) | JEITA confirmado em campo (51 C, `health=Overheat`, carga 0 = correto) |
| mapa do fork oficial | framework/SystemUI/Settings patcheados; 18 apps; chave de plataforma e da FIIO |

### 9.2 Por que ALSA nao toca neste aparelho

O kernel do JM21 **nao tem platform component de ASoC**
(`/sys/kernel/debug/asoc/platforms` vazio; nenhum driver `*-pcm` em 264). Os PCMs
do card sao stubs. O audio real vai por outro caminho:

```
HAL -> write() em /dev/aud_pasthru_adsp (pacotes GPR, ABI extraida por REA)
    -> ADSP (APM faz o hw_params) -> I2S -> FPGA (I2C) -> cs43198
```

Capturamos os pacotes reais de playback (kprobe em `gpr_send_pkt`) e a sequencia
de setup nao aparece ao dar play — o HAL mantem o stream aberto desde o boot.

### 9.3 O bug do DSD era configuracao

`dsd256.dsf` ficava mudo no Sonata e tocava no DAC interno. Com o descritor USB
lido (`lsusb -v`): o Sonata **anuncia DSD nativo** (`alt 4`, `bmFormats
0x80000000`, banda suficiente). O que faltava era **"DSD out mode = Native"**:
o default e DoP, e DoP de DSD256 exigiria 705,6 kHz. Com Native, toca.
Licao registrada: antes de chamar de bug, variar as chaves do app.

### 9.4 GSI: o que ela provou

GSI A13 AOSP puro: boota em 35 s; kernel, modulos `vendor_dlkm`, card ALSA, HAL
QCOM, SD e charging **seguem vivos**. Mas:

- apps FiiO desaparecem (viviam em `/system`);
- o FiiOMusic (de `/data`) abre e navega, mas **nao toca**:
  `NumberFormatException: "unknown"` em `FiiOAUtils`;
- players genericos (Poweramp) tocam 0,8 s e pausam, com
  `AudioFlinger: write blocked ... 4 delayed writes` e
  `Unable to set property "mqa.audio.type" ... 0x18`.

**Conclusao:** nao basta manter o vendor. O DAP depende de um **contrato de
system**: `framework.jar`/`framework-res`/`services.jar` patcheados (que
sintetizam `fiio.current.play.device` e outras props) + apps + overlays.
Para um port fiel, **A13 e o teto** — porque A14+ nao aceita esses jars.

### 9.5 Caminho recomendado para ROM custom

1. `jadx` no `framework.jar`/`services.jar` -> diff contra AOSP 13 -> lista real
   de patches (a medir).
2. Estrategia barata: **LineageOS 20 empacotando os componentes da FIIO como
   prebuilts** (framework, framework-res, services, SystemUI, Settings + 18 apps).
3. Assinatura: reusar os jars da FIIO evita o muro da chave de plataforma.

### 9.6 Custos aprendidos (para nao repetir)

- **Trocar system com FBE exige factory reset na volta.** O userdata nao
  sobrevive; o SD nao e afetado.
- **`fastboot reboot fastboot` trava com a TWRP**: fastbootd mora no recovery
  stock. Sequencia: stock recovery -> fastbootd -> stock recovery de volta ->
  TWRP por ultimo.
- `fastboot 37` nao remenda vbmeta (`AVB_MAGIC`): editar `flags` no offset 120
  (`=3`) resolve.

### 9.7 Estado do aparelho ao fim da sessao

Stock 1.1.1, userdata limpo, TWRP `own-funcional` regravada em `recovery`,
`vbmeta` stock. Card de audio presente, boot em ~30 s.

## 10. Sessao 6 (2026-10-28) — PRIMEIRA ROM COMPILADA

**Marco:** o LineageOS 20 para o JM21 **compilou pela primeira vez**, com os 16
patches da FIIO aplicados.

```
lineage-20.0-20261028-UNOFFICIAL-jm21.zip   1,1 GB
lineage_jm21-ota-eng.ocnaibill.zip          1,1 GB
boot.img 48M   dtbo.img 8M   recovery.img 58M
tempo de build: 5min34s (incremental, apos ~26 rodadas)
```

### 10.1 O que foi montado

| item | estado |
|---|---|
| árvore LineageOS 20 | `~/lineage20` (lineage-20.0, depth=1) |
| device tree | `device/fiio/jm21` + `vendor/fiio/jm21` (2675 arquivos) |
| patches framework/services | 16/16 aplicados, compilando |
| 61 flags `config_fiio_*` | em `core/res/res/values/config.xml` |
| 17 apps FIIO + `FiioDapUtils.jar` | prebuilts, `certificate: platform` |
| 41 fragmentos VINTF | `DEVICE_MANIFEST_FILE` |

### 10.2 Os ~19 erros e o que ensinaram

A contagem final: **~26 rodadas** de build. Desses erros, **13 eram meus**, e
quase todos do mesmo tipo: assumir que uma funcao do codigo decompilado da FIIO
(`sysfsRead`, `typeToString`, `isHighPackage`, `getAppName`, `mPowerInChanged`,
`mAppContext`) existia no AOSP. **O decompilado mostra o resultado da FIIO, nao
o AOSP puro.**

Os demais: ambiente (`libncurses.so.5` — resolvido com symlink no RUNPATH dos
prebuilts, porque o soong roda com `env -i`), empacotamento (particoes pequenas,
`BOARD_ROOT_EXTRA_FOLDERS` criando labels fantasma, `vendor_ramdisk` vazio) e
dados (`build.prop` do stock duplicando 46 props geradas pelo build).

### 10.3 Armadilhas de ambiente (valem para a proxima maquina)

- soong precisa de **>6 GB**; com 15 GB de RAM + zram o build era morto pelo
  `systemd-oomd`. Resolvido com **swapfile de 12 GB em btrfs** (exige NOCOW:
  `btrfs filesystem mkswapfile`).
- prebuilts do AOSP (llvm-rs-cc, clang.real) querem `libncurses.so.5`; o Arch so
  tem 6. `LD_LIBRARY_PATH` **nao funciona** (soong usa `env -i`): o symlink tem
  de ir no diretorio do **RUNPATH** do binario.
- `mka` em foreground derruba a sessao do GNOME por OOM — **sempre** em
  `systemd-run`.

### 10.4 Proximo passo

Flash da OTA e os 6 criterios de aceitacao (docs/47 §7.4): boot, audio, DAC/FPGA,
roda de teclas, SD, modo USB DAC.

### 10.5 Bring-up: os tres defeitos que impediam o boot

A ROM compila, mas ainda **nao subia**. Depuracao de 2026-10-28:

| # | defeito | evidencia | correcao |
|---|---|---|---|
| 1 | `init_boot.img` em **header v0** | nosso: `header_version=0`, `ramdisk=268468224` (lixo); stock: `v4`, `ramdisk=2005925` | `BOARD_MKBOOTIMG_INIT_ARGS := --header_version $(BOARD_BOOT_HEADER_VERSION)` |
| 2 | `vendor/etc/init/*.rc` **ausentes** (93 arquivos) | build tinha 4 `.rc`, stock tem 72; `init.qcom.rc` faltava | regenerar o `proprietary.mk` sem a remocao em lote |
| 3 | AIDs do vendor **nao declarados** | `host_init_verifier`: `Unable to find UID for 'vendor_qrtr'` | `TARGET_FS_CONFIG_GEN` com 13 AIDs (2901-2913) do `/vendor/etc/passwd` stock |

**Como o (1) foi encontrado:** comparar o header binario do nosso `boot.img`/`init_boot.img`
com o stock. O `boot.img` estava certo (v4, kernel identico ao stock, ramdisk 0); o
`init_boot` estava invalido — e por isso **nem o recovery stock** entrava em
fastbootd quando o `init_boot` do Lineage estava gravado. Esse sintoma foi o que
isolou a causa.

**Armadilha de metodo:** testar "boot stock + sistema Lineage" antes de corrigir
(2) e (3) deu falso negativo — o teste rodou com dois defeitos ainda presentes.

### 10.6 Ferramenta de progresso

`tools/lineage-status.sh` (+ `tools/lineage-live.py`): painel com fase, % do
ninja, conflitos, blobs, patches, disco/memoria e artefatos. O live serve a
mesma pagina por HTTP com auto-refresh 8 s (usado via tailnet durante a sessao).

### 10.7 CAUSA RAIZ do nao-boot: falta o `snapuserd` no init_boot

Depuracao offline (sem aparelho): desempacotar os dois `init_boot.img` e comparar o
ramdisk arquivo por arquivo (`tools/unpack-boot.py`).

```
stock:  ramdisk = 2.005.925 bytes, lz4  ->  16 entradas
nosso:  ramdisk = 1.355.295 bytes, gzip ->  12 entradas
```

Diferenca (so no stock):

```
system/bin/snapuserd
system/etc/init/snapuserd.rc
```

`snaperuserd` e o daemon de **snapshot** — o aparelho e **Virtual A/B**
(`Header flags: virtual_ab_device` no lpdump). Sem ele, o `init` de primeira fase
nao consegue montar as particoes dinamicas e o boot morre **antes de levantar o
USB** — exatamente o sintoma observado (tela preta com backlight, zero
enumeracao).

**Por que faltou:** o produto nao herdava `build/make/target/product/generic_ramdisk.mk`,
que e quem adiciona `snapuserd.ramdisk` ao ramdisk generico.

Tentativa 1: herdar `generic_ramdisk.mk` -> quebra o soong
(`generated_kernel_includes` usa `$(PATH_OVERRIDE_SOONG)`, que so existe com
fonte de kernel; usamos kernel prebuilt).

**Correcao adotada:** adicionar **apenas** `snapuserd.ramdisk` a
`PRODUCT_PACKAGES` em `device.mk`, sem herdar o `generic_ramdisk.mk`.

### 10.8 Metodo que faltou nas primeiras rodadas

Os dois artefatos que falhavam (`boot.img`, `init_boot.img`) tinham header e
kernel **corretos** — o build nao reclamava. O que os denunciou foi **comparar
binario com binario** contra o stock: header (`header_version`), tamanho do
ramdisk e, por fim, a **lista de arquivos** do ramdisk. Nenhuma dessas coisas
aparece em log de build.

Regra para a proxima: antes de flashar, `cmp`/parse do artefato contra o stock.

### 10.9 Onde o bring-up parou (e um erro de metodo)

Estado ao fim da sessao 6, com o aparelho **restaurado ao stock**:

| item | estado |
|---|---|
| build | OK (1,1 GB), 16 patches, 61 flags, 17 apps |
| `boot.img` | header v4, kernel identico ao stock |
| `init_boot.img` | header v4, ramdisk com **as mesmas 16 entradas** do stock (inclui `snapuserd`) |
| `system.img` | estrutura correta (`/system/bin/init` 2,09 MB, `init.rc`, `build.prop`) |
| fastbootd | **sobe** com os nossos `boot`+`init_boot` |
| boot normal | **nao** sobe: para no logo da FIIO |

**Erro de metodo que invalidou uma rodada inteira:** para bisectar eu revertí
`system` e `vendor` ao stock mas deixei `system_ext`, `product`, `odm`,
`vendor_dlkm` e `system_dlkm` do Lineage. Um sistema *hibrido* nao boota por
motivo obvio, e a conclusao tirada dali ("o problema e o boot/init_boot") nao
vale.

### 10.10 Roteiro correto de bisseccao (proxima sessao)

Sempre com **todo o resto em stock**, um artefato por vez, e wipe so quando o
conjunto muda:

1. tudo stock -> confirma que boota (baseline);
2. so o `init_boot` nosso -> se falhar, e ele;
3. so o `boot` nosso (init_boot stock) -> se falhar, e ele;
4. depois as logicas, uma por vez: `system` primeiro (e a que monta), depois
   `vendor`, depois `system_ext`/`product`/`odm`/`*_dlkm`.

Hipoteses ainda nao testadas, em ordem de custo:

- `fstab` de primeira fase: o stock vem do `vendor_boot`; comparar com o que o
  nosso build gera;
- `vendor_boot` do nosso build (32 KB, so 3 modulos, sem DTB) — provavelmente
  inutilizavel, mas explica a diferenca de 96 MB;
- `lpdump` no aparelho apos gravar as logicas: conferir se os tamanhos
  (system 2133 MiB, vendor 700 MiB, product 512 MiB) cabem no metadata do `super`.

### 10.11 Ganhos concretos desta sessao (para nao parecer zero)

- o build **passa** e e reproduzivel (device tree versionado, patches reais);
- os tres defeitos de empacotamento foram encontrados **por comparacao binaria
  com o stock**, nao por tentativa: sepolicy dirs, `init_boot` v0, `snapuserd`;
- `tools/unpack-boot.py` deixa essa comparacao repetivel;
- o painel (`lineage-status.sh` / `lineage-live.py`) e o `gen-vendor-mk.py`
  ficam para as proximas rodadas.

## 11. Sessao 7 (2026-10-29) — os quatro defeitos de empacotamento

Ontem a ROM compilava mas nao subia. Hoje o problema foi **fechado por completo**
com comparacao binaria contra o stock, e o aparelho bootou com os nossos
artefatos de boot. Os quatro defeitos, todos de embalagem:

| # | defeito | como apareceu | correcao |
|---|---|---|---|
| 1 | ramdisk em **gzip** (stock usa **lz4**) | comparar o magic do ramdisk | `BOARD_RAMDISK_USE_LZ4 := true` |
| 2 | imagem **sem AVB footer** e sem padding | `AVBf` ausente; 1,8 MB vs 8 MB | `BOARD_AVB_ENABLE := true` (testkey rsa2048) |
| 3 | DTB **fora** do vendor_boot | stock tinha FDT em 7,3 MB; o nosso nao | renomear `prebuilt/dtb` -> `bengal-jm21.dtb` (o AOSP busca `*.dtb`) |
| 4 | vendor_boot com **3 modulos** (stock: 251) e sem `first_stage_ramdisk/fstab.*` | comparar o ramdisk do vendor_boot | copiar a arvore stock; `BOARD_VENDOR_RAMDISK_KERNEL_MODULES(_LOAD)` + copy do fstab |

**Provado em campo (o que cada combinacao faz):**

| boot | init_boot | vendor_boot | vbmeta | sistema | resultado |
|---|---|---|---|---|---|
| stock | **nosso** | stock | stock | stock | **boota em 25 s** |
| **nosso** | **nosso** | stock | stock | stock | **boota** |
| nosso | nosso | nosso | nosso | stock | nao boota (outro defeito) |
| nosso | nosso | stock | remendado | **nosso** | tela preta |

### 11.1 Metodo que funcionou

Tudo saiu de **comparar artefato com artefato**: magic de compressao, tamanho,
offset do footer AVB, presenca de FDT, lista de arquivos do ramdisk, tamanho de
cada arquivo. Nenhuma dessas diferencas aparece em log de build — e todas as
quatro passaram despercebidas por varias rodadas.

### 11.2 O que falta

O boot funciona com o **sistema stock**. Quando entra o nosso `system` (com
`vbmeta` remendado), trava com tela preta. Restam **duas** variaveis juntas, o
que e exatamente o erro de metodo que ja custou uma rodada:

- proximo teste: **system nosso** com boot/init_boot/vendor_boot/**vbmeta todos
  stock** — se falhar, o problema e o `system.img`; se bootar, e o `vendor_boot`
  do build ou o `vbmeta`.

Ferramentas novas: `tools/unpack-boot.py` (parser de boot/vendor_boot) e
`tools/gen-vendor-mk.py`.

## 12. Sessao 8 (2026-10-30) — recovery e sistema: mais duas camadas

### 12.1 O recovery deste aparelho e KERNEL-LESS

Comparando as tres imagens de recovery (`tools/unpack-boot.py`):

| imagem | kernel | ramdisk | resultado |
|---|---|---|---|
| stock | **0** | 14.534.532 (lz4) | funciona |
| TWRP nossa | **0** | 27.001.056 (lz4) | funciona |
| Lineage (do build) | **49.646.080** | 11.825.229 | **nao sobe** |

O kernel vive no `boot`; o `recovery` e so ramdisk. **O nosso build embute o
kernel no recovery** — e o bootloader recusa. O script da TWRP ja fazia certo:
`mkbootimg --ramdisk ... --header_version 4` **sem `--kernel`**.

### 12.2 Mas kernel-less nao basta: o formato AVB do recovery e diferente

Teste A/B:

1. ramdisk **stock** repackado kernel-less (14 MB) -> **nao sobe**;
2. o mesmo + AVB footer + padding ate 100.663.296 -> **nao sobe**.

Ou seja: nao e o conteudo do ramdisk do Lineage. O stock tem, logo **depois do
ramdisk**, um **vbmeta embutido** (`AVB0`), e nao apenas um footer — formato
proprio que ainda nao reproduzimos. Proximo passo e offline: comparar a estrutura
AVB das duas imagens.

### 12.3 O sistema falha antes de tudo, e nao e SELinux

- nosso `system` + tudo stock + `vbmeta` flags=3 -> cai no fastbootd;
- o mesmo com `androidboot.selinux=permissive` -> **igual**: nao e politica;
- o **GSI** (A13 de fora) no mesmo cenario **bootava** -> o vendor esta bom e o
  problema e especifico do nosso `system`;
- o hash da plat policy difere (`011a0d45` stock vs `012c15e6` nosso), mas o GSI
  prova que essa diferenca **nao e fatal**.

### 12.4 Estado

Aparelho **stock, bootado**, userdata limpo. Nada pendente na placa.

Pendencias da proxima sessao, em ordem:
1. comparar a estrutura AVB do recovery stock (offline) e reproduzir -> ganhamos
   `adb` em recovery, que destrava o diagnostico do sistema;
2. com recovery funcionando: montar `/system` na mao e ver o erro real;
3. revisar o achado de hardware (docs/12) antes de sessoes longas.

## 13. Sessao 9 (2026-10-30) — o CONTRATO do firmware (e dois achados grandes)

### 13.1 O recovery do Lineage boota (era o formato AVB)

Sequencia que fechou:
1. recovery deste aparelho e **kernel-less** (kernel vive no `boot`);
2. ramdisk em **lz4**;
3. vbmeta AVB **NAO ASSINADO** embutido — `avbtool add_hash_footer --algorithm NONE`
   (eu vinha assinando com testkey, o que muda `auth`/`alg` e o bootloader recusa);
4. preenchida ate o tamanho da particao.

Com isso o recovery sobe, mostra a UI e — depois de trazermos
`recovery/root/init.recovery.qcom.rc` da arvore do TWRP — **levanta USB e adb root**.

Empacotamento reproduzivel: `tools/make-recovery.sh`.

### 13.2 O fstab do firmware diz o que cada particao exige

Extraido de `dumps/fw-1.1.1/vendor_boot.img` -> `first_stage_ramdisk/fstab.default`:

```
system        /system    ... wait,slotselect,avb=vbmeta_system,logical,first_stage_mount,
                              avb_keys=/avb/q-gsi.avbpubkey:/avb/r-gsi.avbpubkey:/avb/s-gsi.avbpubkey
system_ext    ... avb=vbmeta_system,logical
product       ... avb=vbmeta_system,logical
vendor        ... avb,logical
vendor_dlkm   ... avb,logical
system_dlkm   ... avb,logical
odm           ... avb,logical
```

**Consequencia:** `system`/`system_ext`/`product` sao verificados contra
**`vbmeta_system`**. O nosso build **nunca gerou `vbmeta_system.img`** (so o
`vbmeta.img`), e a particao `vbmeta_system_a` continuava com o do stock —
descrevendo o hashtree do sistema **stock**. Portanto `/system` nao monta e o
boot morre depois do logo, exatamente como vinhamos vendo.

**E explica o GSI:** o fstab aceita as chaves `q/r/s-gsi.avbpubkey` — o GSI e
assinado com elas, por isso bootou no mesmo aparelho.

Correcao minima: `avbtool make_vbmeta_image --flags 3` -> `vbmeta_system` com
HASHTREE_DISABLED, gravado na particao. (Para um build "de verdade", o caminho
e `BOARD_AVB_VBMETA_SYSTEM := system system_ext product` + chave.)

### 13.3 Licao de metodo (a que custou 3 dias)

O contrato estava no **dump do firmware** desde o primeiro dia: o fstab do
vendor_boot, os descritores do vbmeta, os manifestos VINTF. Eu passei dois dias
investigando o *nosso* build (header, ramdisk, politica SELinux) sem nunca ler o
que o **aparelho** exige.

**Regra:** antes de gerar imagem, ler o contrato do firmware — `fstab.*` do
vendor_boot, `vbmeta.img` (descritores), `/vendor/etc/vintf/`. E o equivalente a
ler a interface antes de implementar.
