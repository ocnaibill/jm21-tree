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

## 7. Próximo passo deste lado

`vmlinux-to-elf` sobre `analysis/fw-1.1.1/kernel.Image` para recuperar o
kallsyms: (a) achar os símbolos FiiO embutidos, (b) descobrir quem chama os
quatro `snd_dac_*_gpl` exportados, (c) confirmar se existe machine driver
patcheada no kernel.
