# 16 — Auditoria da pesquisa externa (JM21)

> Método: cada afirmação recebe um veredito contra o firmware 1.1.1 que temos.
> Sem "parece certo": ou há evidência no pacote, ou fica como não verificado.
>
> Legenda: **CONFIRMADO** · **REFUTADO** · **PARCIAL** · **NÃO VERIFICÁVEL**
> (precisa do aparelho ou de outro firmware).

## 1. Identificação

| Afirmação | Veredito | Evidência |
|-----------|----------|-----------|
| SM6225 / `khaje` / `bengal`, 6 nm | **CONFIRMADO** | `[DT]` compatíveis `qcom,khaje*`; `[PROP]` `ro.product.board=bengal`, device `bengal_515` |
| Android 13, `TKQ1.230110.001` | **CONFIRMADO** | `[FW]` `post-build`, `ro.build.version.incremental` |
| Kernel `5.15.41-android13-8-g9ded8564ff52-dirty` (1.1.1) | **CONFIRMADO** | `[FW]` banner no `Image` + `vermagic` dos `.ko` |
| Kernel `...-gdfab679e3463-dirty` (1.0.8) | **NÃO VERIFICÁVEL** | só temos o pacote 1.1.1 |
| Layout GKI 2.0 (`boot`+`init_boot`+`vendor_boot`+`vendor_dlkm`) | **CONFIRMADO** | `[FW]` 19 partições com exatamente essas |
| `super.img` no payload | **REFUTADO** | `[FW]` não existe partição `super`; o OTA grava nas lógicas (`system`, `vendor`, `product`, `odm`, `system_ext`, `*_dlkm`) |
| OTA `.zip` com `payload.bin`, A/B | **CONFIRMADO** | `[FW]` `ota-type=AB`, payload v2 |
| URL `jm21pack.fiio.net/beta/JM21-update-<versao>.zip` | **CONFIRMADO** | `[FW]` `Content-Length` 1 642 845 150 idêntico ao arquivo local |

## 2. Bootloader e SELinux — as duas afirmações mais perigosas

| Afirmação | Veredito | Evidência |
|-----------|----------|-----------|
| "Bootloader desbloqueado de fábrica" | **SEM EVIDÊNCIA / provavelmente falso** | `[FW]` `ro.build.type=user`, `ro.secure=1`, `ro.debuggable=0`, AVB `Flags=0` (verity + verificação **ligadas**). `ro.oem_unlock_supported=1` só diz que o desbloqueio é **permitido**, não que o aparelho sai desbloqueado. |
| "SELinux permissive por padrão" | **SEM EVIDÊNCIA / provavelmente falso** | build `user` com `ro.debuggable=0`; `CONFIG_SECURITY_SELINUX_DEVELOP=y` apenas permite permissive **se** o bootloader passar `androidboot.selinux=permissive`. Não há esse parâmetro no `boot.img` (sem bootconfig embutido). Só o aparelho responde (`getenforce`). |
| `ro.adb.secure=1` (implícito: adb autorizado) | **CONFIRMADO** | `[PROP]` |

**Consequência prática:** o plano de root do texto ("já vem desbloqueado, então é
só `fastboot flash init_boot`") **não pode ser executado às cegas**. Com AVB
ligado e bootloader travado, o flash falha — ou, pior, se o unlock for feito sem
backup, o `userdata` é apagado. A ordem correta é: confirmar
`fastboot getvar unlocked` → só então decidir.

Outro ponto: `fastboot boot <img>` **não é universal** em Qualcomm; muitos
bootloaders recusam. Testar isso antes de contar com o "root sem gravar".

## 3. Partições, root e splash

| Afirmação | Veredito | Evidência |
|-----------|----------|-----------|
| Root via `init_boot` (GKI 5.15 / A13) | **CONFIRMADO** | `[FW]` `init_boot.img` existe (2 011 136 bytes de conteúdo AVB) |
| `vendor_boot`/`dtbo` trazem o DT do JM21 | **CONFIRMADO** | `[FW]` `vendor_boot` carrega 5 DTBs base; `dtbo` tem 42 overlays (o do JM21 é o 40) |
| `vendor_dlkm` tem os `.ko` da FiiO | **CONFIRMADO** | `[FW]` 12 módulos FiiO/Gowin + `cs43198.ko` |
| "Partição `/dev/block/by-name/splash`" | **REFUTADO** | `[FW]` não há `splash` no fstab nem no payload. O logo é **`/vendor/firmware/splash.img`** |
| "BMP 24-bit 750×1334 em offset 16384" | **CONFIRMADO (como arquivo)** | `[FW]` em `splash.img`, offset `0x4000`: `BM`, 750×1334, 24 bpp, 3 004 224 bytes |
| "Tamanho exato de 3 MB" | **PARCIAL** | 3 004 224 bytes é o **primeiro** BMP; o arquivo tem **34 238 520 bytes e 4 BMPs** (mais três 720×1280) |
| "`super.img` separado" | **REFUTADO** | ver §1 |

Detalhe do `splash.img` que ninguém citou: são **quatro** imagens — uma
750×1334 (logo) e três 720×1280 (provavelmente animação de carga). Trocar só a
primeira mantém as outras.

## 4. Memória e swap

| Afirmação | Veredito | Evidência |
|-----------|----------|-----------|
| zram0 + swapfile em `/data/vendor/swap/swapfile` | **CONFIRMADO** | `[FW]` script em `vendor.img`: cria swapfile de **512 MB** (`dd ... bs=1m count=512`), `mkswap`, `swapon -p 32758` |
| zram com lz4 | **CONFIRMADO** | `[FW]` `echo lz4 > /sys/block/zram0/comp_algorithm` |
| "Usar zstd no zram" | **SUGESTÃO, não padrão** | o firmware escreve **lz4** |
| lmkd agressivo / `low_ram` | **CONFIRMADO (indício)** | `[PROP]` `persist.device_config.lmkd_native.low_ram=true`; `init.svc_debug.no_fatal.lmkd=1` |
| Kernel com MGLRU | **CONFIRMADO** | `[FW]` `CONFIG_LRU_GEN=y` (é built-in, não "ajuste de módulo") |
| `ro.vendor.qti.config.swap=true` | **CONFIRMADO** | `[PROP]` |
| "FiiOat / WheresWaldo" | **NÃO VERIFICÁVEL** | módulo externo; nada no firmware |

## 5. O que a pesquisa acerta e vale adotar

1. Confirmar **`init_boot`** como alvo do Magisk — é o mesmo caminho que o
   layout GKI 2.0 que extraímos indica.
2. **`vmlinux-to-elf` no `Image`** — é exatamente o próximo passo planejado
   aqui (extraí o `kernel.Image` cru, 49 646 080 bytes; não está comprimido).
3. A leitura do **`splash.img`** com `dd ... bs=1 seek=16384 conv=notrunc` está
   certa em formato e offset — só erra o caminho (arquivo, não partição).
4. Os comandos de `adb` para I2C/GPIO/DT são úteis e batem com os que já estão
   em `06-playbooks-adb.md`.

## 6. Correções que a auditoria impõe ao plano de root

1. **Não** assumir bootloader desbloqueado. Verificar antes.
2. **Não** assumir SELinux permissive. `getenforce` decide.
3. **Não** procurar partição `super` nem `splash` no payload.
4. Backup de `persist`, `fiioconfig`, `modemst*`, `devinfo`, `misc` **antes** de
   qualquer unlock (ver `07-riscos-e-recuperacao.md`).
5. Sem `prog_firehose` público, um erro no bootloader é assistência técnica.

## 8. Anexo — auditoria do PDF "Dossiê CS43198 / SGM8262-2 / SM6225"

Arquivo: `dossie_engenharia_reversa_cs43198_sm6225.pdf` (11 páginas).
Veredito por afirmação verificável:

### 8.1 Confirmado

| Afirmação | Como confere |
|-----------|--------------|
| Register map: `0x20000` default `0xFE`, `0x20052` default `0x04`, `0x80000` default `0x30`, `0x90000` default `0x02`, volume `0x90001/2` default `0x78` | datasheet DS1156F2 + nosso init (escreve exatamente `0xFE`, `0x90000=0x02`, `0x80000=0x30`) |
| `0x80000`: `OUT_FS[5:4]` + `+1dB_EN` (bit 0) | datasheet §7.5.1; nosso `set_volume_db` liga o bit 0 |
| `0x90000`: bits 7/6/5 = SLOW_FASTB / PHCOMP / **NOS** | datasheet §7.5.2; nossos presets `0x82`, `0x42`, `0xC2`, `0x22` |
| Tabela dos 5 filtros (`0x02`, `0x42`, `0x82`, `0xC2`, `0x22`) | bate com os 6 valores do nosso driver (o sexto é `0x03`) |
| I2C `0x30` + `0x33` (variante) | nosso DT: `reg = 0x30` e `0x33` |
| Volume 0,5 dB/LSB, `0x00`=0 dB, `0xFF`=mute | datasheet §7.5.3 (já corrigimos o dossiê com isso) |
| MCLK externo chaveado (22,5792/24,576 etc.) | nós provamos que o **FPGA** gera o MCLK (`fpga_set_mclk`) |
| PAL/AudioReach, backends MI2S/TDM, `resourcemanager_bengal_idp.xml` existe | `[FW]` arquivo presente; `MI2S-LPAIF_VA-RX-PRIMARY` no backend de fone |
| Regras `on property:` no init | `[FW]` existem (`fiio.handle.files`, `fiio.start.uac.service`) |

### 8.2 Refutado

| Afirmação | Evidência contrária |
|-----------|---------------------|
| "`resourcemanager_bengal_idp.xml` fixa `192000`/32 bits na saída wired" | `[FW]` o arquivo **não contém `192000`** (só 8000, 16000, 44100, 48000). O bloco `PAL_DEVICE_OUT_WIRED_HEADPHONE` não tem `<samplerate>` e declara **`fractional_sr=1`** — ou seja, taxa nativa |
| "O driver ajusta `OUT_FS[5:4]` entre 1,0/1,7/2,0 Vrms" | `[FW]` `OUT_FS` é escrito **uma única vez** (`0x80000 = 0x30`) nos dois ramos do `config_dac`; não existe símbolo `set_performance_mode` no `cs43198.ko`; só o bit 0 muda |
| "Bit 4 = DEEMPH; bits 3:1 = WIDEBAND_FLAT" em `0x90000` | datasheet §7.5.2: **bit 2 = PCM_WBF_EN**, **bit 1 = HIGH_PASS (default 1)**, **bit 0 = DEEMP_ON**, bits 4:3 reservados |
| "`0x90004` tem os bits de Master Mute (`MUTE_A/B`)" | datasheet §7.5.6: `0x90004` = INV_A(3), INV_B(2), SWAP(1), COPY(0). Mute fica em `0x90003` |
| "Cada SGM8262-2 por canal, somando 4 amps em BTL" | não refutado, mas **sem suporte** no firmware; o que sabemos é par diferencial entre chips (2 amps por saída), não 4 amps por canal |

### 8.3 Não verificável aqui

Kernel `gdfab679e3463` (seria do FW 1.0.8 — só temos o 1.1.1); `REV_ID 0xA1`
(o probe do `cs43198.ko` não compara ID); repositórios `FiiOat`,
`FiiO_Kernel_OpenSource` e `HioneOS`; suposto bug de máscara `0xC0` vs `0xE0`
no NOS (nosso driver escreve o byte inteiro via `dac_dual_regmap_write`, então
**não** tem esse bug).

### 8.4 O que o PDF acerta e vale incorporar

1. **Bit 2 (`PCM_WBF_EN`)** existe e só deve ser usado a 192 kHz, com `PDN_HP`
   ligado — não usamos hoje; é um alvo se aparecer filtro wideband.
2. A organização dos 5 filtros por combinação de bits 7/6/5 — já incorporada.
3. A referência ao driver upstream `cs43130.c` para conferir semântica de
   registrador — já usada.

### 8.5 O que muda no nosso modelo

- Ganho **não** é `OUT_FS` neste firmware (refutado). Continua valendo: digital
  + `+1dB_EN` no volume máximo.
- A alegação de SRC forçado a 192 kHz **cai**: a config PAL do JM21 suporta
  taxa fracionária (`fractional_sr=1`) e não fixa 192 kHz no fone.
- Continua em aberto (e é o único jeito de fechar): medir. Ver
  `15-conflitos-e-metodo-de-prova.md`.

## 9. Próximo passo deste lado

1. `vmlinux-to-elf` sobre `analysis/fw-1.1.1/kernel.Image` — **feito** (152 139
   símbolos; zero `fiio_*`/`snd_dac_*`).
2. Comparar o `resourcemanager_bengal_idp.xml` com o do `qrd` para ver o que a
   FiiO mudou no roteamento (dois backends distintos para headset e headphone).
3. Medir: protocolo de bancada em `15-conflitos-e-metodo-de-prova.md` §4.

## 10. Como usar material externo daqui pra frente

Regra prática adotada: **toda afirmação de terceiro entra como `[EXT]` e só
sobe para fato depois de cruzar com uma destas fontes** — datasheet oficial,
arquivo do firmware, decompilação ou medição. O que não cruzar fica marcado
como não verificado, mesmo que pareça razoável.

