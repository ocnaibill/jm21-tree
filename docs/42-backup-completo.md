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

## 4. Pendência

- **Teste de restauração real**: escrever de volta uma partição de estado
  (candidata: `fiioconfig`, com o próprio dump) e conferir o hash na leitura.
  É um write — só com aprovação explícita.
