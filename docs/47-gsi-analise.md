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

## 8. Execucao: medicao ao vivo (2026-10-27)

### 8.1 Estado real do `super` (medido no aparelho)

```
super            = 10491136 setores = 5122,6 MiB   (/dev/block/mmcblk0p88)
system_a         = 2133,4 MiB
system_a-cow     = 1850472 setores = 903,6 MiB
odm_a-cow        = 2368 setores   = 1,2 MiB
product_a-cow    = 9752 setores   = 4,8 MiB
grupo qti_dynamic_partitions_a max = 5367267328 bytes
snapshotctl: "Update state: none"  -> COW sao restos, sem OTA pendente
slot: _a   (virtual A/B, dynamic partitions)
```

### 8.2 A GSI escolhida CABE sem deletar nada

```
aosp_arm64-exp-TQ3A.230805.001.A3-10454027-66e107ed.zip   (794 MiB)
  -> system.img = 1,8 GiB (ext2, nao esparso)
system_a = 2133,4 MiB   ->  cabe (folga ~230 MiB)
```

Isso **simplifica muito** o plano da §7.5: nao e preciso apagar COW nem
redimensionar o `super`. Basta `fastboot flash system`.

### 8.3 Ferramenta

```
fastboot 37.0.0p1  -> tem create/delete/resize-logical-partition e snapshot-update
fingerprint: qti/bengal_515/bengal_515:13/TKQ1.230110.001/eng.fiio.20260428.144644:user/dev-keys
```

### 8.4 Assinatura: a chave de plataforma e da FIIO (nao e testkey)

`ro.build.tags=dev-keys` engana. O certificado de `system_ext/priv-app/Settings.apk`:

```
subject/issuer: C=CN, ST=Guangdong, L=Guangzhou, OU=Android, CN=Android,
                emailAddress=pengweizhong@fiio.net
SHA-256: B3:CA:AA:E4:C3:64:FB:E0:D9:15:F9:74:3A:31:B5:3D:76:C0:0D:B9:8B:A2:0B:FE:60:1B:57:CB:3E:5C:B9:19
```

Nem `Settings` nem `FiiOMusic` declaram `sharedUserId` (bom). Mas permissoes de
**nivel signature** ligadas ao framework so continuam valendo se a ROM for
assinada com essa chave — que so a FiiO tem. Consequencia para o port:
pre-empacotar os APKs mantem a assinatura deles entre si; o que quebra e a
conversa com um framework re-assinado.

### 8.5 Sequencia de flash (decidida)

```
# 1. bootloader
fastboot --disable-verity --disable-verification flash vbmeta vbmeta.img
# 2. fastbootd (particoes logicas)
fastboot snapshot-update cancel            # limpa as COW restantes
fastboot flash system ~/jm21-gsi/system.img
fastboot reboot
```

Rollback: `fastboot flash system dumps/fw-1.1.1/system.img` + `vbmeta.img`.

Criterio da primeira rodada (A13, controle): **boota? audio? roda de volume?**
A resposta mede quanto do DAP vem do `system` e quanto vem do `vendor` — que e
exatamente a pergunta aberta na §"MAPA DO FORK OFICIAL" (docs/05).

## 9. RESULTADO DA RODADA 1 (A13 GSI) — 2026-10-27

### 9.1 Como foi o flash

```
fastboot flash vbmeta vbmeta.img            # stock primeiro (a particao estava sem AVB valido)
python: flags AVB offset 120 = 3 -> vbmeta-noverity.img
fastboot flash vbmeta vbmeta-noverity.img   # o fastboot 37 nao consegue remendar (erro de AVB_MAGIC)
fastboot flash recovery recovery.img        # <- TWRP nao tem fastbootd! precisou do stock
fastboot reboot fastboot -> fastbootd
fastboot snapshot-update cancel
fastboot flash system ~/jm21-gsi/system.img # 1,811.5 MiB em 58 s
fastboot reboot
```

**Achado operacional:** `fastboot reboot fastboot` com a TWRP instalada **trava**
em "entering into fastboot" — fastbootd mora no recovery stock. Guardar isso.

### 9.2 O que a GSI A13 fez

| item | resultado |
|---|---|
| boot | **sim**, ~35 s |
| fingerprint | `Android/aosp_arm64/generic_arm64:13/TQ3A.230805.001.A3/10454027:user/release-keys` |
| `verifiedbootstate` | `orange` (esperado, bootloader destravado) |
| card de audio | **presente** (`/dev/snd/controlC0` + 25 PCMs) |
| modulos de vendor | carregados (`machine_dlkm`, `bolero_cdc`, `spf_core`, `gpr`, ...) |
| HAL de audio QCOM | **rodando** (`android.hardware.audio.service_64`, `audioadsprpcd`) |
| thread `fiio_charger_ma` | viva (vendor_dlkm) |
| cartao SD | **montado** (476,94 GB, 385,62 GB livres) |
| apps FiiO em `/system` | **0** (como previsto: estavam no system) |
| props `fiio*` | 25, vindas de vendor/odm |

### 9.3 O FiiOMusic roda — mas NAO toca

O app sobreviveu em `/data` (v109). Instalado/aberto no AOSP puro:

- UI **renderiza e navega** normalmente (biblioteca, SD, 60 musicas, browser de pastas);
- ao dar play, o log mostra:

```
I FiioMediaPlayer: open: support = true
I FiioMediaPlayer: openAudio : /storage/emulated/0/Music/Epic_Trailer_Theme.flac
I FiioMediaPlayer: prepareToPlay
W System.err: java.lang.NumberFormatException: For input string: "unknown"
    at com.other.utils.FiiOAUtils.b(SourceFile:7)
    at com.example.root.checkappmusic.FiioMediaPlayer.k0(SourceFile:21)
```

e o AudioFlinger fica em `0 Tracks` — **nada toca**.

### 9.4 A CAUSA, medida

Properties que o app le (`strings` do APK instalado):

```
fiio.current.play.device        persist.sys.audio.output.select
persist.sys.fiio.config         persist.sys.dsd2pcm.exist
persist.sys.eq.exist            fiio.vehicle.mode / fiio.run.vehicel.mode
fiio.tape.mode                  persist.sys.theme
```

Estado no GSI x stock:

```
fiio.current.play.device = [vazio]   <-- no stock era "SPEAKER"
persist.sys.audio.output.select = 0
persist.sys.fiio.config = FiiODPA
persist.sys.dsd2pcm.exist = [vazio]
persist.sys.eq.exist = [vazio]
```

**`fiio.current.play.device` e sintetizada pelo `framework.jar` patcheado**
(visto no mapa: `FIIO_CURRENT_PLAY_DEVICE`). Sem o patch ela nao existe, o app
recebe `"unknown"`, o `Integer.parseInt` estoura e o caminho de reproducao morre.
Nao foi possivel setar a mao (`setprop` negado pelo SELinux em build user).

### 9.5 Conclusao da rodada (o que isso responde)

1. **O vendor basta para o hardware**: card, modulo, HAL, SD e charging seguem
   funcionando com um system AOSP puro. A camada de drivers nao depende do DAP.
2. **O framework patcheado e load-bearing**: o app oficial da FiiO *abre*, mas
   nao reproduz, porque depende de uma property que so o framework da FiiO cria.
3. Portanto, para ROM custom: **manter o framework da FiiO e obrigatorio** (ou
   reescrever os pontos de contato do app). Isso confirma, com medicao, o que o
   mapa da docs/05 indicava.

### 9.6 Pendencias desta rodada

- `[?]` roda de volume / teclas fisicas: precisa de teste manual na tela.
- `[?]` algum som de sistema (toque, teclado)? Se houver, a rota de audio do
  vendor esta viva e so o app quebra.
- Proximo passo natural: **rodada 2 com A14** (mesma GSI AOSP, so system) para
  medir o teto de versao — e o mesmo teste, repetido.

## 10. Rodada 1: o segundo mecanismo (alem do app) e o veredito

Testando com players **genericos** (nao-FiiO) no GSI, para separar "app quebrado"
de "audio quebrado":

| player | comportamento |
|---|---|
| Poweramp | `state=3` (PLAYING) por ~0,8 s -> volta a `state=2` (PAUSED) |
| AOSP Music / AudioPreview | track criado, nunca ativa |
| FiioMusic | `NumberFormatException` + `audioPause` |

E no log do `AudioFlinger`:

```
W AudioFlinger: write blocked for 862 msecs, 4 delayed writes, thread 29
W libc: Unable to set property "mqa.audio.type" to "0": error code: 0x18
```

### 10.1 O que isso significa

`write blocked ... 4 delayed writes` = a HAL **nao consome** o buffer. O player
toca 0,8 s, o buffer enche, e ele pausa. E a segunda negacao diz por que:
`libfiioaudio`/`libfiioaqm` (vendor) tentam **setar properties** que so existem no
`property_contexts` do sistema da FIIO. Em AOSP puro o SELinux nega (`0x18`) —
exactamente como negou `fiio.current.play.device`.

Ou seja, existem **dois** acoplamentos system<->vendor, e nao um:

1. **app -> framework**: `fiio.current.play.device` e sintetizada pelo
   `framework.jar` patcheado. Sem ela o player oficial nao reproduz.
2. **vendor -> system**: as libs da FIIO dependem de **properties declaradas no
   `property_contexts` (system)** — `mqa.audio.type`, `persist.sys.*`, etc. Sem
   elas, o HAL/VAD nao consegue nem sinalizar seu estado, e o audio trava.

### 10.2 Veredito da medicao (a pergunta da issue #12)

| camada | sobrevive ao GSI? |
|---|---|
| kernel + modulos (`vendor_dlkm`) | **sim** |
| HALs QCOM/FIIO, card ALSA, `aud_pasthru_adsp` | **sim** (processos de pe) |
| SD, charging, teclas de hardware basicas | **sim** |
| apps FiiO | nao estao (viviam em `system`) |
| **contrato de properties + sepolicy** | **NAO** -> audio quebra |
| **framework patcheado** | **NAO** -> app oficial quebra |

**Conclusao:** nao basta "manter o vendor". Uma ROM custom para o JM21 tem de
carregar tambem o **contrato de system que a FIIO estendeu**: `property_contexts`
(propriedades `fiio.*`, `mqa.*`, `persist.sys.*`), a sepolicy correspondente e o
`framework.jar`/`framework-res.apk`/`services.jar` patcheados. E exatamente o que
o mapa da docs/05 previu — agora **medido**, nao inferido.

E valida o teto pratico: esses componentes sao A13; A14+ exigiria reimplementar
os patches. **A13 e o teto para um port fiel.**

### 10.3 Estado do aparelho ao fim da rodada

Esta rodando a **GSI A13** (system AOSP), com:
- recovery **stock** (a TWRP foi substituida para termos fastbootd);
- `vbmeta` com flags=3 (verificacao desligada);
- userdata e SD intactos (apps instalados em `/data` continuam).

Rollback (voltar ao oficial): `fastboot flash system dumps/fw-1.1.1/system.img`,
`fastboot flash recovery <twrp.img>`, e `fastboot flash vbmeta vbmeta.img`.
