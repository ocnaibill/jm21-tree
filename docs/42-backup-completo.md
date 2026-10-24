# 42 — Backup completo do aparelho (fase F2)

> Feito em 2026-10-24, via **adb USB** (MAIS estável que Wi-Fi), com root.
> Tudo em `device-baseline/backup/` (**fora do git**), com `SHA256SUMS`.

## 1. O que foi dumpado

**Estado único** (não existe no OTA) — `SHA256SUMS.unique.txt`, 21 arquivos,
258 MB:

| Partição | Tamanho | Por que importa |
|----------|---------|-----------------|
| `persist` | 32 MB | calibração (sensores, MAC, touch) |
| `modemst1`/`modemst2` | 2 MB cada | calibração de modem/rádio |
| `fsg` | 2 MB | FSG (rádio) |
| `fiioconfig` | 10 MB | SN, NB, MasterTrim, contador de wear (`docs/26`) |
| `nvdata1`/`nvdata2` | 1,5 MB cada | persistência de vendor |
| `qpdata1`/`qpdata2` | 64/10 MB | dados de QP |
| `secdata`, `storsec`, `keystore`, `frp` | pequenos | estado de segurança/FRP |
| `devinfo`, `misc`, `limits`, `dip`, `apdp`, `ddr`, `uefivarstore` | pequenos | estado de boot/EFI |
| `splash` | **134 MB** | imagem de boot (a partição é bem maior que os ~3 MB úteis) |

**Cadeia de boot dos dois slots** — `SHA256SUMS.boot.txt`, 14 arquivos (~650 MB):
`boot`, `init_boot`, `dtbo`, `vendor_boot`, `vbmeta`, `vbmeta_system`,
`recovery` (A e B).

**Fora do backup de propósito:** `userdata` (dados), `super`/`system`/`vendor` e
as imagens de firmware — todas cobertas pelo OTA 1.1.1, que é byte-idêntico
(verificado por AVB 5/5).

## 2. Verificação contra o OTA (prefixo)

Comparando o **prefixo** do dump com o tamanho da imagem do OTA (a partição é
maior que a imagem e o resto é zero):

| Partição (slot A) | Resultado |
|-------------------|-----------|
| `boot` | **IGUAL** ao OTA |
| `init_boot` | **DIFERENTE** — é o patch do Magisk (`de0c6dea…`) |
| `dtbo`, `vendor_boot`, `vbmeta`, `vbmeta_system`, `recovery` | **IGUAIS** |

`[FATO]` O slot A está byte-idêntico ao 1.1.1 **exceto** `init_boot_a`. O root
não tocou em mais nada.

Slot B: `boot`, `init_boot` e `vbmeta` **diferem** do OTA e do slot A — confirma
que é um **build anterior** (não usar como fallback).

## 3. Como restaurar

### Partições de estado (por `dd`)
```bash
adb push bk_fiioconfig.img /data/local/tmp/
adb shell su -c "dd if=/data/local/tmp/bk_fiioconfig.img of=/dev/block/by-name/fiioconfig bs=1M"
adb shell su -c "sync"
```
Vale para `persist`, `fiioconfig`, `misc`, `devinfo`, `modemst1/2`, `fsg`,
`nvdata1/2`, `qpdata1/2`, `splash` etc.

### Cadeia de boot (por fastboot)
```bash
fastboot flash boot_a  bk_boot_a.img
fastboot flash init_boot_a bk_init_boot_a.img
fastboot flash dtbo_a  bk_dtbo_a.img
fastboot flash vendor_boot_a bk_vendor_boot_a.img
fastboot flash vbmeta_a bk_vbmeta_a.img
```
- `bk_init_boot_a.img` **mantém o root** (Magisk).
- Para voltar ao **stock**, usar o `init_boot.img` do OTA
  (`858655e7…`, `dumps/fw-1.1.1/init_boot.img`).
- **Nunca** usar as imagens do slot B (build antigo).

### Recuperação de soft-brick
1. `fastboot flash` das imagens do OTA 1.1.1 (`boot`, `init_boot`, `dtbo`,
   `vendor_boot`, `vbmeta`, `vbmeta_system`).
2. Restaurar `persist` e `fiioconfig` do backup, se necessário.
3. Se o aparelho não entrar em fastboot, aí sim é caso de EDL — e não temos
   firehose (`docs/35`).

## 4. Teste de restauração (feito)

Teste escolhido: **`fiioconfig`**, escrevendo de volta o próprio dump (mesmos
bytes). Antes: partição não montada e hash da partição **igual** ao dump
(`005b7233…`).

```
dd if=/data/local/tmp/bk_fiioconfig.img of=/dev/block/by-name/fiioconfig bs=1M
10485760 bytes copied, 0.092 s, 108 MB/s
sha256sum /dev/block/by-name/fiioconfig
005b7233c2e0633615a2a95cbff012df7a09a5374aa6f1a5b396e4bdf00165d2
```

`[FATO]` Hash **idêntico antes e depois** e o SN continua legível
(`sys.fiio.sn_num = 20070008442701`). O caminho de restauração por `dd` está
validado numa partição de estado real, sem alterar o conteúdo.

## 6. Clone completo (2026-10-24)

Além do backup seletivo, foi feito um **clone integral** com
`tools/full-clone.sh` (streaming `adb exec-out dd`, sem ocupar `/data`):

| Conjunto | Conteúdo | Tamanho |
|----------|----------|---------|
| `device-baseline/clone-full/` | **94 partições** + `mmcblk0` (disco inteiro, 31,26 GB) + `userdata` | **~52 GB** |
| `device-baseline/clone/` | as mesmas 92 partições, **sem** `userdata` e sem `mmcblk0` (hardlinks) | 6,8 GB (sem espaço extra) |

Cada partição tem tamanho conferido (`blockdev --getsize64`) e SHA-256 em
`MANIFEST.txt` + `SHA256SUMS`.

Referências: `userdata` = 23 681 416 704 B; `super` = 5 371 461 632 B;
`mmcblk0` = 31 268 536 320 B.

`[!]` Imagens tiradas a quente (sistema rodando): firmware e partições pequenas
são exatas; `super`/`userdata` podem exigir `fsck` na restauração. É a
salvaguarda para atacar a #11 (recovery), não a substitui.
