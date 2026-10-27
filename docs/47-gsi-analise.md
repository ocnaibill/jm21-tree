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

## 6. Super lotado (medido no `super.img` do clone)

`lpdump` no clone (`device-baseline/clone-full/super.img`):

| Partição lógica | Tamanho |
|-----------------|---------|
| `system_a` | 2133,4 MiB |
| `vendor_dlkm_a` | 717,2 MiB |
| `vendor_a` | 621,7 MiB |
| `system_ext_a` | 505,1 MiB |
| `product_a` | 233,2 MiB |
| `odm_a` | 1,2 MiB |
| `system_dlkm_a` | 0,4 MiB |
| `system_a-cow` | **903,6 MiB** |
| `product_a-cow` / `odm_a-cow` | 4,8 / 1,2 MiB |

`[FATO]` `super` = **5122,6 MiB**, usado **5121,6 MiB** → **~1 MiB livre**.

**Implicação:** uma GSI (~1–2 GB) **não cabe** sem liberar espaço. Opções:
1. **Remover as COW** de Virtual A/B (`system_a-cow` 903 MB) — depende do estado
   do snapshot (`snapshotctl`/merge); `[?]` se o aparelho permite apagar com
   segurança.
2. **Apagar uma partição lógica** (ex.: `product`, 233 MB) — não chega.
3. **Redimensionar o `super`** (o GPT tem folga? `[?]`).

Ou seja: a GSI exige planejamento de espaço, não é só `fastboot flash system`.

## 7. Plano de medicao da GSI (preparado em 2026-10-27)

O objetivo desta medicao **nao** e "ter uma GSI": e descobrir empiricamente **ate
que versao de Android o vendor A13 do JM21 continua conversando**. Isso decide
se a ROM custom pode ir para A14/A15 ou se o teto pratico e o A13.

### 7.1 O que ja esta medido

| item | valor | fonte |
|---|---|---|
| `super` | 5122,6 MiB, **~1 MiB livre** | `super.img` do dump |
| `system_a` | 2133,4 MiB | idem |
| `system_a-cow` | 903,6 MiB (snapshot Virtual A/B) | idem |
| kernel | 5.15.41-android13 | `uname -r` ao vivo |
| `board.api_level` / `vendor.api_level` / `vndk` | **33 / 33 / 33** | `getprop` ao vivo |
| treble | true | idem |

Consequencia: a GSI **nao cabe com o `super` como esta**. Antes de qualquer
flash e preciso liberar espaco (cancelar o snapshot e apagar as `-cow`) ou
redimensionar o `super`.

### 7.2 Rede de seguranca (ja existe no repo)

`dumps/fw-1.1.1/` tem o conjunto **completo** do firmware stock (4,5 GB):

```
abl boot dtbo init_boot modem odm product recovery rpm
system (2,1G) system_dlkm system_ext (506M) vbmeta vbmeta_system
vendor (622M) vendor_boot vendor_dlkm (718M) xbl xbl_config
```

Rollback = `fastboot flash` dessas imagens. Nao ha risco de brick
irreversivel enquanto esse diretorio existir.

### 7.3 Ordem dos testes (cada um responde uma pergunta)

1. **GSI A13 (controle)** — "uma system limpa boota neste vendor?". Se falhar
   aqui, o problema e de metodo/compatibilidade, nao de versao, e nada mais
   adianta.
2. **GSI A14** — a primeira pergunta real: o vendor 33 continua funcionando?
3. **GSI A15 / A16** — ate onde vai.

### 7.4 Criterios de sucesso/falha (por subsistema)

| subsistema | como verificar | leitura |
|---|---|---|
| boot | tela inicial + `adb` responde | binario |
| audio | tocar musica | a HAL do vendor continua? |
| DAC/FPGA | `tinymix` lista `DAC Playback Volume`; volume/filtro mudam | vendor intacto |
| roda de volume / teclas | girar e ver volume mudar | hook de framework presente? |
| SD | montar e ler | vendor ok |
| modo USB DAC | plugar no PC e aparecer como DAC | FPGA + app FiiO |

O item **roda de volume** e o que mais provavelmente falha: e o unico que parece
estar em *framework*, nao em vendor. Se falhar so ele, a ROM custom e viavel
(porta-se o hook). Se falharem audio e DAC, a resposta e "vendor nao conversa".

### 7.5 Comandos previstos (quando for executar)

```
# 1. cancelar snapshot e liberar COW
fastboot snapshot-update cancel
fastboot delete-logical-partition system_a-cow

# 2. desabilitar verificacao (guardar o vbmeta stock para voltar)
fastboot --disable-verity --disable-verification flash vbmeta vbmeta.img

# 3. gravar a GSI
fastboot flash system <gsi>.img

# 4. voltar ao stock (rollback)
fastboot --disable-verity --disable-verification flash vbmeta vbmeta.img
fastboot flash system system.img
```

`[?]` Confirmar em campo se o `fastboot` desta versao aceita
`snapshot-update cancel` e `delete-logical-partition` antes de depender deles.
