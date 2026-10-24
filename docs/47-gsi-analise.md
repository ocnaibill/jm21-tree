# 47 — GSI / ROM própria: o que quebra no áudio (issue #12)

> Análise baseada no que já foi medido (HAL, framework, módulos, partições).
> Pontos marcados `[?]` precisam de confirmação no aparelho.

## 1. O que uma GSI substitui e o que preserva

| Particionamento | Conteúdo |
|-----------------|----------|
| `super` (dinâmico, 5,37 GB) | `system`, `system_ext`, `product`, `vendor`, `odm` |
| `boot` / `init_boot` / `dtbo` / `vendor_boot` | kernel, ramdisk genérico (Magisk), DTB, vendor ramdisk |
| `vendor_dlkm` | os módulos (FiiO + Qualcomm) |

Uma GSI Android 13 (SDK 33) substitui **`system`/`system_ext`/`product`**; o
`vendor` (HAL proprietária) e o kernel ficam. É o cenário "Treble clássico".

`[?]` Espaço livre em `super` para acomodar a GSI (o super tem 5,37 GB; se não
couber, é preciso apagar uma partição lógica — destrutivo).

## 2. O que a GSI perde (e é crítico no JM21)

Tudo isto está **no `system`** e desaparece com a GSI:

1. **Enum de codec params da FiiO** (`AudioSystem`, 0–22: `FIIO_MQA`,
   `ALLTODSD`, `DAC_MASTER_TRIM`, `DAC_MUTE`, `HIFI_BOOST`…). Os apps FiiO
   chamam isso por reflexão/JNI; sem o enum, os controles de áudio do app
   deixam de existir.
2. **`AudioSystem.setMasterVolumeDac`** (nativo) — o caminho de volume "master
   DAC" some; resta o `DAC Playback Volume` da HAL.
3. **Formatos DSD** (`AUDIO_FORMAT_DSD_16/32_BIT`, `0x1a000002`). O FiiO Music
   abre um `AudioTrack` nesse formato para DSD nativo; uma GSI o rejeita →
   **DSD nativo quebra** (o DoP continuaria, porque é PCM).
4. **`FIIO_PACKAGE_NAMES`/`isHighPackage`/freezer exemption** — os apps FiiO
   deixam de ser persistentes/imunes ao freezer; podem ser mortos.
5. **Modo de sistema** (`system_mode_value` continua em Settings, mas o
   `PhoneWindowManager`/`ModeSelection` da FiiO não existem) — Pure Music e
   companhia perdem o comportamento.

## 3. O que a GSI mantém

- **HAL de áudio** `audio.primary.bengal.so` (HIDL 7.0) + `libfiioaudio` +
  `libfiioaqm` — em `/vendor`; a GSI fala com ela pelo contrato padrão.
- **`audio_policy_configuration.xml`** do vendor (`direct_pcm`,
  `hifi_playback`) — caminho bit-perfect preservado, **se** a GSI respeitar a
  política do vendor.
- **Kernel + módulos** (`cs43198`, `dac_core`, `anolog_board`, `gw-fpga`) e o
  sysfs `soc:fiio_attr`.
- **Magisk** no `init_boot`.

`[HIP]` O áudio básico (PCM até 384 k, pela HAL) deve funcionar; o que quebra é
o **controle fino** (params FiiO, volume master) e o **DSD nativo**.

## 4. Caminho de teste

1. Backup pronto (`docs/42`).
2. `fastboot reboot fastboot` (fastbootd) → `fastboot flash system gsi.img`
   (se couber) ou apagar `product` antes (destrutivo).
3. Verificar AVB: bootloader destravado (`orange`), vbmeta do vendor; pode ser
   preciso `--disable-verification`.
4. Testar: boot, áudio PCM (tom 44,1 k), DSD (esperado falhar), kcontrols
   (`tinymix`), apps FiiO (esperado falhar em parte).
5. Rollback: `fastbootd` + imagens do OTA (`system`, `vendor`, `product`,
   `system_ext`, `odm`) ou o `super.img` do backup (clone a quente — `fsck`).

## 5. Veredito preliminar

`[HIP]` GSI é **viável para áudio PCM**, mas **não é** o caminho para "controle
total do som" (o objetivo do projeto): sem o `framework.jar` da FiiO, os
recursos que mapeamos (codec params, MQA, DSD nativo) somem. Para controle
total, a ROM própria teria de **levar os patches da FiiO** para o framework.
