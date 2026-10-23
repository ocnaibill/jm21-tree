# 02 — Firmware, partições e integridade

> Tudo aqui foi obtido do pacote `JM21-update-1.1.1` sem o aparelho.

## 1. O pacote OTA

`fw/JM21-update-1.1.1.zip` — 1 642 845 150 bytes.

Estrutura (offsets vêm de `META-INF/com/android/metadata`, campo
`ota-property-files`):

| Arquivo | Offset | Tamanho | Papel |
|---------|--------|---------|-------|
| `META-INF/com/android/metadata` | — | 698 | chave/valor do OTA |
| `META-INF/com/android/metadata.pb` | 835 | 1 412 | metadados protobuf |
| `META-INF/com/android/otacert` | — | — | certificado do pacote |
| `payload_metadata.bin` | 3 239 | 130 946 | manifesto isolado (para streaming) |
| `payload.bin` | 3 239 | 1 642 838 532 | manifesto + dados |
| `payload_properties.txt` | 1 642 841 829 | 177 | hashes/tamanho do payload |
| `apex_info.pb` | 2 295 | **0** | vazio (sem APEX neste OTA) |
| `care_map.pb` | 2 342 | 850 | ranges + fingerprint por partição |

`[FW]` O zip já vinha extraído em `fw/JM21-update-1.1.1/` — mas **sem**
`payload_metadata.bin`; esse arquivo existe dentro do zip (offset acima). Não é
necessário para extrair, porque o manifesto está embutido no `payload.bin`.

### Identidade `[FW]`

```ini
FILE_SIZE=1642838532
METADATA_SIZE=130679
MODEL_NAME=FiiO JM21
FILE_HASH=kzkSRbXKAhGWdGQVgGpiVMrtYE41mb4/MEouJZfYPXE=
METADATA_HASH=zF/jTxnVkCr1xHXRa4ciZ28XY10raju9jJmhlMQJXz4=
```

### Metadados do OTA `[FW]`

```ini
ota-type=AB
pre-device=bengal_515
post-sdk-level=33
post-security-patch-level=2023-02-05
post-build=qti/bengal_515/bengal_515:13/TKQ1.230110.001/eng.fiio.20260428.144644:user/dev-keys
post-build-incremental=eng.fiio.20260428.144644
post-timestamp=1777358737
ota-required-cache=0
```

Leituras importantes:

- **A/B** → dois slots, `boot_a/boot_b`, atualização em segundo plano.
- **`user` + `dev-keys`**: build de usuário assinado com **chaves de
  desenvolvimento**, não `release-keys`. Isso é atípico em produto de consumo e
  muda a estratégia de AVB (ver §5).
- **`eng.fiio.<data>`** no incremental: build marcado como *eng*.
- Patch de segurança de **2023-02-05** mesmo com build de 2026 → base congelada
  em `TKQ1.230110.001` (Qualcomm), sem rebase de segurança.
- `post-timestamp` 1 777 358 737 ≈ **2026-04-28**.

### `payload.bin` `[FW]`

- Formato de payload **v2**, manifesto 130 655 bytes, assinatura 267 bytes.
- `apex_info.pb` vazio → nenhum APEX atualizado/embutido neste pacote.

## 2. Tabela de partições (extraída de fato)

`payload-dumper-go -l`:

| Partição | Tamanho | Observação |
|----------|---------|------------|
| `abl` | 217 kB | Android bootloader (aboot) |
| `xbl` | 3,2 MB | eXtensible Bootloader |
| `xbl_config` | 45 kB | configuração do XBL |
| `rpm` | 229 kB | firmware do RPM (resource power manager) |
| `modem` | 36 MB | firmware do modem |
| `boot` | 101 MB | kernel + ramdisk genérico |
| `init_boot` | 8,4 MB | ramdisk de `init` (padrão Android 13) |
| `vendor_boot` | 101 MB | ramdisk vendor + DTBs |
| `recovery` | 101 MB | recovery (imagem separada, A/B) |
| `dtbo` | 8,4 MB | **42 overlays**, inclui o do JM21 |
| `vbmeta` | 8,2 kB | AVB do topo |
| `vbmeta_system` | 4,1 kB | AVB de `system`/`system_ext`/`product` |
| `odm` | 1,2 MB | quase vazio |
| `product` | 244 MB | apps de produto |
| `system` | 2,2 GB | inclui a raiz (`system-as-root`) |
| `system_ext` | 530 MB | extensões AOSP/QTI |
| `vendor` | 652 MB | HALs, blobs, configs de áudio |
| `system_dlkm` | 434 kB | módulos GKI |
| `vendor_dlkm` | 752 MB | **todos os `.ko`** (ver §4) |

`[FW]` Não existe partição `super` no payload: o OTA grava diretamente nas
partições lógicas. Também não vêm `userdata`, `metadata`, `misc`, `persist`,
`fsg`, `modemst*`, `devinfo` — nada disso é entregue por OTA.

### Tipo de filesystem

Todas as imagens de partição lógica são **ext4** (`file(1)` reporta
`Linux rev 1.0 ext2 filesystem data, UUID=...`; `debugfs 1.47.4` abre todas).
Isso é o que permite inspecionar tudo **sem root e sem mount**.

### `system.img` é *system-as-root*

A raiz de `system.img` contém `/system`, `/vendor`, `/product`, `/system_ext`,
`/odm`, `/init`, `*.rc` — não apenas `/system`. Os aplicativos FiiO estão em
`/system/app` **dentro** da imagem `system.img` (não em `/app`). Quem procura
`/priv-app` na raiz da imagem não encontra nada.

## 3. `care_map.pb`

Protobuf `CareMap` com uma entrada por partição lógica: `odm`, `product`,
`system`, `system_dlkm`, `system_ext`, `vendor`, `vendor_dlkm`. Cada entrada tem
ranges de blocos + `ro.<partição>.build.fingerprint`:

```
odm          → qti/bengal_515/bengal_515:13/TKQ1.230110.001/fiio04281544:user/dev-keys
product      → qti/qssi/qssi:13/TKQ1.230110.001/fiio04281445:user/dev-keys
system       → qti/qssi/qssi:13/...
system_dlkm  → qti/bengal_515/bengal_515:13/...
system_ext   → qti/qssi/qssi:13/...
vendor       → qti/bengal_515/bengal_515:13/...
vendor_dlkm  → qti/bengal_515/bengal_515:13/...
```

Duas árvores convivem: `qssi` (system/system_ext/product) e `bengal_515`
(vendor/odm/dlkm) — arquitetura QSSI padrão da Qualcomm.

`[?]` O `care_map` serve para verificação pós-instalação; não é usado aqui para
nada além de confirmar nomes e fingerprints.

## 4. `vendor_dlkm` — onde está o ouro

752 MB, mas o conteúdo é dominado por *drivers que não interessam*:

| Módulo | Tamanho |
|--------|---------|
| `qca_cld3_wlan.ko` | **451 MB** |
| `msm_drm.ko` | 39,7 MB |
| `msm_kgsl.ko` | 33,2 MB |
| `ipam.ko` | 25,7 MB |
| `camera.ko` | 31,9 MB |

Módulos FiiO/áudio (os alvos):

| Módulo | Tamanho | Papel |
|--------|---------|-------|
| `cs43198.ko` | 402 kB | driver do DAC |
| `dac_core_module.ko` | 614 kB | núcleo do subsistema de áudio FiiO (ioctls) |
| `anolog_board_jm21.ko` | 441 kB | placa: GPIOs, energia, MCLK |
| `fiio_primary_modules.ko` | 1,4 MB | conjunto principal FiiO |
| `fiio_underlay_modules.ko` | 658 kB | conjunto de base |
| `fiio_snd_soc_dummy_dai.ko` | 330 kB | DAI "dummy" para o caminho Android |
| `fiio_headset_jack.ko` | 410 kB | detecção de fone e proteções |
| `fiio_config.ko` | 342 kB | configuração persistida (`/dev/block/by-name/fiioconfig`) |
| `gw-fpga.ko` | 523 kB | driver do FPGA Gowin |
| `fpga_audio_interface.ko` | 407 kB | interface de áudio do FPGA |
| `fpga_interface.ko` | 417 kB | interface genérica do FPGA |
| `fiio-charger-manager.ko` | 662 kB | carga |
| `fiio_wakeup.ko`, `fiio_gpio_debug_module.ko` | — | suporte |

`[DRV]` `fiio_config.ko` referencia `/dev/block/by-name/fiioconfig` — existe uma
partição de configuração FiiO que **não** vem no OTA (`[?]` conteúdo desconhecido;
só acessível no aparelho).

## 5. Integridade, AVB e assinatura

Lido com `avbtool 1.3.0` (AOSP `external/avb`). Saídas completas em
`analysis/fw-1.1.1/avb-vbmeta.txt` e `avb-vbmeta_system.txt`.

### 5.1 `vbmeta.img` (topo) `[FW]`

| Campo | Valor |
|-------|-------|
| Algoritmo | `SHA256_RSA4096` |
| Chave pública (sha1) | `2597c218aae470a130f61162feaae70afd97f011` |
| **Rollback Index** | **0** |
| Rollback Index Location | 0 |
| **Flags** | **0** (verity e verificação **ligadas**) |
| Release string | `avbtool 1.2.0` |
| Header / Auth / Aux | 256 / 576 / 5 952 bytes |

Descritores: *chain partition* para `vbmeta_system` (chave
`cdbb77177f731920bbe0a0f94f84d9038ae0617d`, rollback location 2),
`boot`, `dtbo`, `init_boot`, `recovery`, `vendor_boot` como **hash
descriptors**, e `odm`, `system_dlkm`, `vendor`, `vendor_dlkm` como
**hashtree** (dm-verity v1, FEC 2 roots, blocos 4096).

### 5.2 `vbmeta_system.img` `[FW]`

| Campo | Valor |
|-------|-------|
| Algoritmo | `SHA256_RSA2048` |
| Chave pública (sha1) | `cdbb77177f731920bbe0a0f94f84d9038ae0617d` |
| **Rollback Index** | **1 675 555 200** (= 2023-02-05 00:00 UTC) |
| Flags | 0 |
| Descritores | hashtree de `product`, `system`, `system_ext` |

O rollback index é literalmente **a data do patch de segurança em epoch** —
padrão Qualcomm. Isso significa que um firmware com patch mais antigo tem
rollback index menor e **deve** ser rejeitado por um bootloader com
anti-rollback ativo `[HIP]`.

### 5.3 Verificação das imagens extraídas (feita)

Recalculando `SHA256(salt || imagem[0:image_size])` de cada hash descriptor:

| Partição | Tamanho AVB | Resultado |
|----------|-------------|-----------|
| `boot` | 49 651 712 | **OK** |
| `dtbo` | 2 752 406 | **OK** |
| `init_boot` | 2 011 136 | **OK** |
| `recovery` | 14 540 800 | **OK** |
| `vendor_boot` | 8 323 072 | **OK** |

5/5 batem com os digests do `vbmeta` → a extração do `payload.bin` é
**byte-idêntica** ao que o dispositivo verifica. Esse é o atestado de qualidade
do dump.

Observação: o descritor de `boot` cobre 49,65 MB, mas a partição tem 96 MB —
o resto é padding. O mesmo vale para `init_boot`/`recovery`/`vendor_boot`.
`dtbo` é o único em que tamanho AVB = tamanho real do blob (2 752 406 bytes,
idêntico ao header DTBO).

### 5.4 Certificado do pacote OTA `[FW]`

`META-INF/com/android/otacert` (PEM, 1 407 bytes):

```
subject/issuer: C=CN, ST=Guangdong, L=Guangzhou, OU=Android, CN=Android,
                emailAddress=pengweizhong@fiio.net
notBefore: 2024-07-15 12:00:04 GMT
notAfter:  2051-12-01 12:00:04 GMT
serial:    228A5E6ADE54E1F8D5015C8D98446B8DA4881EC7
SHA-256:   4B:B8:80:EE:C6:16:FE:28:E4:3C:0C:1F:F3:F3:D1:B7:
           E8:EE:F8:54:82:CD:F1:B9:07:33:9C:D2:D1:86:41:5E
```

Autoassinado, e-mail de um engenheiro da FiiO — consistente com build `dev-keys`.
Não confundir com a chave AVB (`2597c218…`): são chaves distintas (pacote OTA ×
verificação de boot).

### 5.5 Implicações práticas

1. **Não há chave de release no caminho.** Recompilar `boot`/`vendor_boot` e
   assinar com chave própria é viável **se** o bootloader estiver desbloqueado.
2. `[?]` Se o JM21 permite `fastboot flashing unlock` — só o aparelho responde.
3. `[?]` Anti-rollback do bootloader (`xbl`) não é visível no `vbmeta`; o
   rollback index 0 no topo sugere folga, mas não prova nada sobre o XBL.
4. **Regra do laboratório**: nenhum flash antes de ter (a) dump completo via
   `adb pull`, (b) `fiioconfig`, `persist` e `modemst*`, (c) caminho de
   recuperação validado (`07-riscos-e-recuperacao.md`).

## 6. Atualização, canal e procedência do arquivo

`[PROP]`:

```
ro.product.ota.host=jm21pack.fiio.net
ro.product.ota.package_name=JM21-ota-1.1.1.zip
ro.product.version=1.1.1
ro.product.version.update_log=log_1.1.1.txt
```

### 6.1 Dois pacotes, nomes parecidos

O changelog oficial (fórum FiiO) publica **dois** arquivos por versão:

| Tipo | URL oficial | Tamanho |
|------|-------------|---------|
| **Completo** | `jm21pack.fiio.net/beta/JM21-update-1.1.1.zip` | **1 642 845 150** |
| **Incremental** | `jm21pack.fiio.net/1.1.0/JM21-ota-1.1.1.zip` | 92 668 277 |

`[FW]` O arquivo em `fw/JM21-update-1.1.1.zip` tem **exatamente**
1 642 845 150 bytes → é o **pacote completo** (`beta/`), confirmado por
`Content-Length` do servidor oficial (Last-Modified 2026-04-29 03:33 UTC).

O nome em `ro.product.ota.package_name` (`JM21-ota-1.1.1.zip`) corresponde ao
**incremental** — detalhe que confunde na hora de baixar. Nome do pacote de OTA
não indica "completo".

`[?]` O incremental (92,7 MB) não foi baixado. Ele descreve o delta 1.1.0 → 1.1.1
e é útil para provar o que mudou entre versões, mas não é necessário para o
laboratório agora.

### 6.2 Diretório e disponibilidade

- `jm21pack.fiio.net` é Alibaba OSS atrás de CDN (`Tengine`, `x-oss-cdn-auth`).
- Listagem de diretório é **403**; só URLs completas funcionam.
- A estrutura de pastas segue o padrão `/beta/` (pacote completo) e
  `/1.0.8/`, `/1.1.0/` (incremental a partir da versão anterior).

### 6.3 Downgrade

O fórum oficial diz: *"If you would like to get the download link of the old
firmware, please provide the SN code of your device to support@fiio.com"*.

Ou seja: **links antigos não são públicos**. Qualquer plano de downgrade passa
por (a) suporte da FiiO com o SN, ou (b) aplicar um rollback index menor e
depender do estado do anti-rollback — que ainda é `[?]`.

### 6.4 Cliente de atualização

- `FiiOUpdate.apk` (16,7 MB) é o cliente de OTA `[FW]`, exposto em
  *Technical Support → Firmware Upgrade → Local Upgrade*.
- `[HIP]` O pacote aceita instalação por `update_engine` (A/B) e o `payload.bin`
  é auto-suficiente.

## 7. Hashes de referência

`analysis/fw-1.1.1/SHA256SUMS.txt` (prefixos):

| Arquivo | SHA-256 (16 primeiros) |
|---------|------------------------|
| `JM21-update-1.1.1.zip` | `7ce7dd28432418b7` |
| `payload.bin` | `93391245b5ca0211` |
| `boot.img` | `03bad0f3afbe483e` |
| `dtbo.img` | `1365314e11acedda` |
| `init_boot.img` | `858655e7e516224a` |
| `vendor_boot.img` | `11773988182f1cc1` |
| `vbmeta.img` | `f6edbdda2329d102` |
| `vendor.img` | `0ee49b29574c42a9` |
| `system.img` | `21deb5634ae36296` |
| `cs43198.ko` | `ad32570b9dda2e93` |
| `libfiioaudio.so` | `239563f80098f265` |
| `audio.primary.bengal.so` | `ebe7f0c282a359d4` |

## 8. Layout recomendado de trabalho

```
fw/                     pacote original (não versionado)
dumps/fw-1.1.1/         imagens extraídas (não versionado)
analysis/fw-1.1.1/      recortes: props, xml, .so, .ko, DTS (binários fora do git)
tools/                  scripts versionados (dt_dump.py, ...)
tools/bin/              binários de ferramenta (não versionado)
docs/                   este dossiê
```

Regra: `dumps/` é sempre reconstruível a partir de `fw/` + `tools/bin`.
Nada em `dumps/` deve ser editado à mão.
