# 33 — Framework e services modificados pela FiiO (issue #3)

> Artefatos puxados do aparelho. Comparação feita por **conteúdo e símbolos**
> contra o AOSP 13 (não por diff linha a linha de fonte): procuramos o que a
> FiiO acrescentou e onde.

| Arquivo | SHA-256 |
|---------|---------|
| `framework.jar` | `72d585fa…` |
| `services.jar` | `bbd090df…` |
| `framework-res.apk` | `97b67228…` |
| `FrameworksResTarget_Vendor_JM21.apk` | `674558d8…` |
| `libandroid_runtime.so` | `4ae0a15d…` |
| `libfiioaudio.so` | `239563f8…` |

## 1. `AudioSystem`: o enum de parâmetros FiiO

O framework tem constantes novas em `android.media.AudioSystem`:

| # | Constante |
|---|-----------|
| 0 | `CODEC_PARAM_LINE_VOLUME_CONTROL` |
| 1 | `CODEC_PARAM_LRBALANCE_SETTING` |
| 2 | `CODEC_PARAM_PO_GAIN` |
| 3 | `CODEC_PARAM_DIGITAL_FILTER` |
| 4 | `CODEC_PARAM_PLAYBACK_VOLUME` |
| 5 | `CODEC_PARAM_AUDIO_POLO_MODE` |
| 6 | `CODEC_PARAM_AUDIO_HEADSET_TYPE` |
| 7 | `CODEC_PARAM_AUDIO_ABORT_DELAY` |
| 8 | `CODEC_PARAM_ALLTODSD` |
| 9 | `CODEC_PARAM_FIIO_MQA` |
| 10 | `CODEC_PARAM_SPDIF_ENABLE` |
| 11 | `CODEC_PARAM_RESAMPLE_ENABLE` |
| 12 | `CODEC_PARAM_RESAMPLE_RATE` |
| 13 | `CODEC_PARAM_START_PLAY` |
| 14 | `CODEC_PARAM_ALLTODSD_PRIORITY` |
| 15 | `CODEC_PARAM_AUTO_CONFIG` |
| 16 | `CODEC_PARAM_DAC_MASTER_TRIM_L` |
| 17 | `CODEC_PARAM_DAC_MASTER_TRIM_R` |
| 18 | `CODEC_PARAM_DAC_THD_C2` |
| 20 | `CODEC_PARAM_DAC_MUTE` |
| 21 | `CODEC_PARAM_HIFI_BOOST_MODE` |
| 22 | `CODEC_PARAM_GET_VU_PROPERTY` |

(19 não existe.) Isso **completa** a tabela da HAL do `docs/19`: os tipos 0–6 e
16–21 já eram conhecidos; 7–15 e 22 são novos. Explica por que só parte dos
controles aparecia no JM21: o enum é compartilhado entre modelos.

Também há novos formatos: `AUDIO_FORMAT_DSD_16_BIT`, `AUDIO_FORMAT_DSD_32_BIT`
(o `0x1A000002` que medimos no DSD).

## 2. `setMasterVolumeDac` — volume do DAC pelo framework

`AudioSystem` ganhou um **método nativo**:

```java
public static native int setMasterVolumeDac(int i);
```

Implementado em `libandroid_runtime.so`
(`android_media_AudioSystem_setMasterVolumeDac` →
`android::AudioSystem::setMasterVolumeDac(uint32_t)`), que cai na HAL em
`libfiioaudio.so`:

```
fiio_adev_set_master_volume_dac
```

`AudioService` chama isso quando o stream é música e o device tem o bit `0x2`:

```java
if (mStreamType == 3 && (device & 2) != 0) AudioSystem.setMasterVolumeDac(index);
```

`[FATO]` Existe um **segundo ponto de entrada** de volume — o "master DAC" —,
mas a medição (abaixo) mostra que ele **não é um caminho independente**.

### Medição dos dois caminhos (N2, resolvida)

Com um tom de 48 kHz tocando e leitura de `0x90001`/`0x90002` a cada passo:

1. **Volume pelo keyevent** (`input keyevent 24/25` → AudioService → HAL):
   cada passo muda **só** `0x90001/2`, seguindo a tabela `h[]`
   (ex.: 84 → 83 em um passo = `h[36]` → `h[37]`). Nenhum outro registrador
   mudou (`0x90000`, `0x80000/1/2`, `0x20000`, `0x70000`, `0x1000B` ficaram
   idênticos).
2. **Escrita direta no kcontrol** (`tinymix "DAC Playback Volume" 40`) com o
   stream ativo: **ignorada** — o registro continuou em 83. O framework
   reaplica o seu valor; a HAL não aceita volume "por fora".

`[FATO]` Conclusão: há **um** efeito (o volume do DAC em `0x90001/2`), com
**duas portas de entrada** (AudioService/`setMasterVolumeDac` e o kcontrol), e
o **framework é autoritativo** — a porta da HAL só funciona quando é ele quem
manda. Sem stream ativo, o registro nem é reescrito.

## 3. A HAL tem EQ próprio (não usado pelo app)

`libfiioaudio.so` exporta:

```
fiio_adev_set_eq_param
FiiOAudioSetEqParams(unsigned, unsigned, float, float, unsigned)
FiiOAudioConfigParams
fiio_adev_get_codec_param
```

Ou seja, a HAL **sabe** aplicar EQ por parâmetros — mas o app Equalizer usa
`AudioEffect` do AOSP (docs/32). `[?]` Quem usa `FiiOAudioSetEqParams` neste
modelo? Nenhum app que examinamos chama isso diretamente.

## 4. Feature flags `config_fiio_*` — valores reais

Lidas de `framework-res.apk` (o overlay do JM21 só redefine 4 flags gerais).
São **64 flags**; as que importam para o hardware:

| Flag | Valor |
|------|-------|
| `config_fiio_35mm_multiplexing_spdif_enabled` | **true** |
| `config_fiio_po_lo_spdif_select_enabled` | **true** |
| `config_fiio_spdif_out_switch_enabled` | false |
| `config_fiio_spdif_output_mode_enabled` | true |
| `config_fiio_spdif_input_mode_enabled` | false |
| `config_fiio_spdif_decode_enabled` | false |
| `config_fiio_aes_in_enabled` | false |
| `config_fiio_hdmi_in_enabled` | false |
| `config_fiio_hdmi_out_arc_enabled` | false |
| `config_fiio_xmos_in_enabled` | **false** |
| `config_fiio_uac_kernel_enabled` | **false** |
| `config_fiio_usb_boot_enabled` | true |
| `config_fiio_usbaudio_vol_adjust_enabled` | true |
| `config_fiio_bal_po_lo_select_enabled` | true |
| `config_fiio_output_gain_enabled` | true |
| `config_fiio_over_gain_enabled` | false |
| `config_fiio_super_over_gain_enabled` | false |
| `config_fiio_p2d_enabled` | **true** |
| `config_fiio_dac_balance_enabled` | true |
| `config_fiio_dac_thdc2_enabled` | true |
| `config_fiio_dac_config_enabled` | false |
| `config_fiio_digital_filter_enabled` | true |
| `config_fiio_EQ_enabled` | true |
| `config_fiio_roon_enabled` | true |
| `config_fiio_tape_mode_enabled` | true |
| `config_fiio_tape_mode_auto_det_sw` | **false** |
| `config_fiio_vehicle_mode_enabled` | true |
| `config_fiio_device_no_battery` | false |
| `config_fiio_temp_manage_enabled` | true |
| `config_fiio_noheadset_auto_pause_enabled` | true |
| `config_fiio_lineout_vol_adjust_enabled` | true |
| `config_fiio_custom_key_enabled` | true |
| `config_fiio_soft_hold_in_enable` | true |
| `config_fiio_sw_hold_in_enable` | false |
| `config_fiio_sw_hold_special_node` | false |
| `config_fiio_gsensor_in_enable` | false |
| `config_fiio_touch_panel_gesture_wakeup_enabled` | true |
| todos `config_fiio_leds_*` | false |
| `config_fiio_audio_vol_default` | **60** |

Duas leituras importantes:

1. **`uac_kernel_enabled = false`** — o modo USB DAC **não** é um gadget UAC do
   kernel neste build. Isso muda o plano do teste USB: o caminho é de
   usuário (`UsbAlsa`/`libusb`/`configfs`), não o `f_uac2` do kernel.
2. **`tape_mode_auto_det_sw = false`** — é por isso que os nós `tape_auto_detect`
   e `send_tape_type` não existem no JM21: o recurso está desligado.

## 5. `services.jar`: o que foi especial-cased

### 5.1 Allowlists de pacotes

```java
// ActivityManagerService
FIIO_PACKAGE_NAMES = { com.fiio.music, com.android.aboutfiio, com.fiio.control,
  com.fiio.android, com.fiio.devicevendor, com.android.fiioupdate,
  com.android.fiio.scrcpy, com.fiio.market };
isHighPackage(pkg)  → usado em addAppLocked()
```

- `PackageManagerService`/`ComputerEngine`: esses pacotes entram em
  `getPersistentApplications()` — tratados como **persistentes**.
- `OomAdjuster.cantFreezePackage()`: eles **nunca** são congelados pelo freezer
  de apps em cache. A lista inclui também **`com.alex.debugtool_player`** — um
  app de depuração de terceiros que ficou no código.

### 5.2 Broadcasts próprios

| Ação | Quem envia | Uso |
|------|-----------|-----|
| `fiio.intent.action.KEY.EVENT` | `PhoneWindowManager` | repassa `keyCode`/`keyAction` para os apps |
| `fiio.intent.action.USB_AUDIO_DEVICE_CHANGE` | `UsbAlsaManager` | `EXTRA_ACTION=1` insert, `0` remove |
| `fiio.intent.action.ACTION_EXTERNAL_CHARGING` | `PowerManagerService` | detecta carregador externo |
| `fiio.intent.action.ACTION_EXTERNAL_DISCHARGING` | idem | descarga externa |
| `com.android.systemui.action.FIIO_POWER_KEY_DIALOG` | SystemUI | diálogo do botão de power |

### 5.3 Modo de operação e volume USB

```java
// PhoneWindowManager
isAndroidOrPuremusicMode() → Settings.System "system_mode_value" <= 1
```

Ou seja, o **modo** (Android / Pure Music / …) é um inteiro em
`Settings.System["system_mode_value"]`. É a chave para a issue #8 (kcontrols
que aparecem só em certos modos).

```java
// AudioService
if (Settings.System["usb_vol_ctl"] == 0 &&
    SystemProperties.get("fiio.current.play.device","HEADPHONES").equals("USB"))
    index = MAX_STREAM_VOLUME[stream];
```

Quando o volume USB está desligado e a saída é USB, o framework **força o
volume máximo** e deixa o controle para o dispositivo USB.

### 5.4 Permissão pré-concedida a app de teste

`DefaultPermissionGrantPolicy` concede permissões a
`com.example.fiiotestappliction` (sic, com o typo). O pacote **não está
instalado** no aparelho — é resíduo de build.

## 6. O que isso muda no dossiê

1. O modo de operação tem **nome e endereço**: `Settings.System["system_mode_value"]`.
2. O volume tem **dois caminhos** (DAC master vs. HAL playback) — precisa de um
   teste que separe os dois.
3. O USB DAC **não** é UAC de kernel (`uac_kernel_enabled=false`) — o teste de
   384 kHz por USB tem de ser feito por outro mecanismo (host enviando para o
   gadget de usuário), ou o caminho nem existe neste build.
4. O enum de codec params está **completo** (0–22), o que fecha a tabela da HAL.
