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

`[FW]` `vbmeta.img` e `vbmeta_system.img` presentes; build assinado com
`dev-keys`.

Implicações práticas:

1. **Não há chave de release no caminho.** Recompilar `boot`/`vendor_boot` e
   assinar com chave própria é viável **se** o bootloader estiver desbloqueado.
2. `[?]` Se o JM21 permite `fastboot flashing unlock`. Não há evidência no
   firmware; depende do aparelho.
3. `[?]` Rollback index e flags do `vbmeta` não foram lidos (falta `avbtool`).
   Próximo passo: `avbtool info_image --image vbmeta.img`.
4. `[?]` Presença de dm-verity/AVB em `system`/`vendor` deve ser confirmada nos
   descriptors dos `vbmeta`.
5. **Regra do laboratório**: nenhum flash antes de ter (a) dump completo via
   `adb pull`, (b) imagem de `fiioconfig` e persist, (c) caminho de recuperação
   validado (§`07-riscos-e-recuperacao.md`).

## 6. Atualização e canal

`[PROP]`:

```
ro.product.ota.host=jm21pack.fiio.net
ro.product.ota.package_name=JM21-ota-1.1.1.zip
ro.product.version=1.1.1
ro.product.version.update_log=log_1.1.1.txt
```

- O host `jm21pack.fiio.net` é o canal de OTA. `[?]` Não foi sondado; sondar
  depois (com cautela, apenas HEAD/GET de metadados públicos) para descobrir
  versões disponíveis e permitir *downgrade* controlado.
- `FiiOUpdate.apk` (16,7 MB) é o cliente de atualização `[FW]`.
- `[HIP]` O pacote aceita instalação por recovery/sideload A/B
  (`update_engine`), e o `payload.bin` é auto-suficiente.

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
