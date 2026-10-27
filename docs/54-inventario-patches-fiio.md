# 54 — Inventário dos patches da FiiO (para o port de ROM)

Objetivo: transformar "quanto custa trazer a experiência DAP para uma ROM custom"
em **número**, em vez de achismo.

Método: `jadx` 1.5.6 sobre cada artefato stock (`framework.jar`, `services.jar`,
`SystemUI.apk`, `Settings.apk`), buscando as classes que referenciam `fiio`.

```
~/tools/jadx/bin/jadx -d /tmp/jadx-XX --no-res --no-debug-info <artefato>
grep -rl -i fiio /tmp/jadx-XX/sources --include=*.java | wc -l
```

## 1. `framework.jar` — o mais profundo, e o menor

5699 classes decompiladas. Apenas **7 arquivos** mencionam `fiio`, dos quais
**2 são `R.java`** (ids de recurso). Ou seja: **5 classes de código**.

| classe | patch |
|---|---|
| `android/media/MediaRouter.java` | **seta `fiio.current.play.device`** para `"A2DP"`, `"USB"` ou `typeToString(mainType)`; e `fiio.media.router.change` |
| `android/media/AudioTrack.java` | `SystemProperties.set("fiio.cur.session.id", mSessionId)` no construtor |
| `com/android/internal/os/PowerProfile.java` | lê `/sys/devices/platform/soc/soc:fiio_attr/cw_batt_capacity` |
| `android/media/AudioSystem.java` | constante `CODEC_PARAM_FIIO_MQA = 9` |
| `android/content/ContentProvider.java` | casos especiais de pacote (`com.fiio.music`, `com.android.music`, `com.android.dreams.phototable`) |

Mais os **62 recursos `config_fiio_*`** declarados em `framework-res.apk`
(valores default no próprio framework-res; o overlay do device **não** os
contém — ver docs/05).

`[FATO]` Essa é a razão medida de a GSI A13 quebrar o FiiOMusic: sem o patch do
`MediaRouter`, `fiio.current.play.device` fica vazio; o app recebe `"unknown"`,
`Integer.parseInt` estoura e o playback morre (docs/47 §9.4).

## 2. `services.jar` — 11 classes, patches de 1 a 5 linhas

| classe | patch |
|---|---|
| `am/ActivityManagerService.java` | array `FIIO_PACKAGE_NAMES` + helper |
| `pm/PackageManagerService.java` | idem (lista um pouco maior) |
| `pm/ComputerEngine.java` | idem |
| `am/OomAdjuster.java` | idem (inclui `com.alex.debugtool_player`) |
| `pm/permission/DefaultPermissionGrantPolicy.java` | concede permissões a `com.fiio.music` |
| `am/ContentProviderHelper.java` | `if (appName.contains("fiio"))` |
| `audio/AudioService.java` | lê `fiio.current.play.device` e o setting `usb_vol_ctl` |
| `usb/UsbAlsaManager.java` | broadcast `fiio.intent.action.USB_AUDIO_DEVICE_CHANGE` |
| `power/PowerManagerService.java` | intents `ACTION_EXTERNAL_CHARGING/DISCHARGING` |
| `policy/PhoneWindowManager.java` | `sys.fiio.home_disabled`, `fiio.test.show_power_key_view`, intent `fiio.intent.action.KEY.EVENT` |
| `statusbar/StatusBarManagerService.java` | caso especial `com.android.fiioupdate` |

**Leitura:** nada aqui é arquitetural. São listas de pacotes, broadcasts e
leituras de properties — reimplementável em uma tarde por classe.

## 3. `SystemUI.apk` — 51 classes, com pacote próprio

3463 classes decompiladas; **51** tocam `fiio`, incluindo um pacote inteiro:

```
com/android/systemui/fiio/FiioPowerKeyModeAdapter.java
com/android/systemui/fiio/tiles/BalSettingTile.java
com/android/systemui/fiio/tiles/DigitalFilterTile.java
...
```

Além de toques em `power/PowerUI.java`, `battery/BatteryMeterView.java`,
`qs/QSFactoryImpl.java`, `qs/FooterActionsController.java` (tiles do painel
rápido para balanço e filtro do DAC).

## 4. `Settings.apk`

Em processamento na hora em que este documento foi escrito; o número entra na
§4.1. Sabe-se que contém `handleAllToDSD`, `updateAllToDsdStatus`,
`all2dsd_ctl_value` e a aba de áudio (ver docs/05).

### 4.1 Resultado

3306 classes decompiladas; **104** tocam `fiio`. A distribuição mostra que o
fork e **auto-contido**, nao espalhado:

```
36  com/android/settings/fiio/general
26  com/android/settings/fiio/audio      <- a aba de audio
 8  com/android/settings/fiio/system
 7  com/android/settings/fiio/led
 6  com/android/settings/fiio            (raiz)
 5  com/android/settings/fiio/deviceinfo/aboutphone
 2  com/android/settings/fiio/network
 2  com/android/settings/fiio/fuelgauge
12  fora do pacote (hooks em Settings/SettingsLib/homepage)
```

Ou seja: ~92 classes dentro de `com.android.settings.fiio.*` e apenas 12
intervencoes no Settings do AOSP. O trabalho de "trazer o Settings" e,
na pratica, **trazer um pacote inteiro** — o que reforca a estrategia de
**prebuilt** em vez de reimplementar.

## 5. Consequência para o plano

O medo era ter de reimplementar "o framework". A medição mostra outra coisa:

| artefato | tamanho do fork | estratégia |
|---|---|---|
| `framework.jar` | **5 classes** + 62 recursos | **reimplementar** (patch pequeno) ou empacotar como prebuilt |
| `services.jar` | **11 classes**, patches triviais | **reimplementar** |
| `SystemUI.apk` | 51 classes (1 pacote próprio) | **prebuilt** (é app) |
| `Settings.apk` | a medir | **prebuilt** (é app) |
| apps OEM (18) | — | **prebuilt** |

Ponto de atenção que sobra: **assinatura**. SystemUI/Settings usam a chave de
plataforma da FIIO (docs/47 §8.4); numa ROM assinada com outra chave eles
precisam ser **re-assinados com a chave da ROM**. Isso é mecânico (`apksigner`),
mas implica que todos os apps FiiO sejam re-assinados juntos, para continuarem
se reconhecendo entre si.

## 6. Próximos passos concretos

1. fechar o número do `Settings.apk`;
2. extrair os **valores** dos 62 `config_fiio_*` do `framework-res.apk` stock
   (são as flags que ligam cada feature do DAP);
3. escrever os patches de `framework.jar`/`services.jar` como **diff contra o
   AOSP 13** (temos a árvore em `~/twrp13`);
4. montar o device tree de LineageOS 20 com: patches + prebuilts + overlays +
   `property_contexts`/sepolicy da FIIO.

## 7. As 62 flags `config_fiio_*` — o mapa de features do JM21

Extraidas do `framework-res.apk` stock (jadx `-e`, `res/values/bools.xml` e
`integers.xml`). Total **61** recursos: **28 ligados**, **32 desligados**, **1 inteiro**.

### 7.1 Ligadas (28) — o que ESTE aparelho tem

| flag | |
|---|---|
| `config_fiio_35mm_multiplexing_spdif_enabled` | ✅ |
| `config_fiio_bal_po_lo_select_enabled` | ✅ |
| `config_fiio_battery_charger_optimize_available` | ✅ |
| `config_fiio_battery_disable_charger_setting_available` | ✅ |
| `config_fiio_bluetooth_absolute_volume_enabled` | ✅ |
| `config_fiio_bluetooth_audio_encoder_enabled` | ✅ |
| `config_fiio_bt_ldac_enabled` | ✅ |
| `config_fiio_bt_lhdc_enabled` | ✅ |
| `config_fiio_custom_key_enabled` | ✅ |
| `config_fiio_custom_screen_saver_enabled` | ✅ |
| `config_fiio_dac_balance_enabled` | ✅ |
| `config_fiio_dac_thdc2_enabled` | ✅ |
| `config_fiio_digital_filter_enabled` | ✅ |
| `config_fiio_lineout_vol_adjust_enabled` | ✅ |
| `config_fiio_noheadset_auto_pause_enabled` | ✅ |
| `config_fiio_output_gain_enabled` | ✅ |
| `config_fiio_p2d_enabled` | ✅ |
| `config_fiio_po_lo_spdif_select_enabled` | ✅ |
| `config_fiio_roon_enabled` | ✅ |
| `config_fiio_soft_hold_in_enable` | ✅ |
| `config_fiio_spdif_output_mode_enabled` | ✅ |
| `config_fiio_system_suspend_wifi_connect_enabled` | ✅ |
| `config_fiio_tape_mode_enabled` | ✅ |
| `config_fiio_temp_manage_enabled` | ✅ |
| `config_fiio_touch_panel_gesture_wakeup_enabled` | ✅ |
| `config_fiio_usb_boot_enabled` | ✅ |
| `config_fiio_usbaudio_vol_adjust_enabled` | ✅ |
| `config_fiio_vehicle_mode_enabled` | ✅ |

### 7.2 Desligadas (32) — modelos/features que o JM21 nao usa

`config_fiio_aes_in_enabled`, `config_fiio_bluetooth_playback_quality_enabled`, `config_fiio_control_double_leds_enabled`, `config_fiio_dac_config_enabled`, `config_fiio_desktop_mode_available`, `config_fiio_device_no_battery`, `config_fiio_gsensor_in_enable`, `config_fiio_hdmi_in_enabled`, `config_fiio_hdmi_out_arc_enabled`, `config_fiio_led_aw22xxx_in_enable`, `config_fiio_leds_breath_enabled`, `config_fiio_leds_fixed_brightness_enabled`, `config_fiio_leds_fixed_charge_style_enabled`, `config_fiio_leds_fixed_color_enabled`, `config_fiio_leds_rhythm_enabled`, `config_fiio_leds_strip_enabled`, `config_fiio_multi_button_in_enable`, `config_fiio_opt_decode_enabled`, `config_fiio_over_gain_enabled`, `config_fiio_project_members_enable`, `config_fiio_qcc_bt_enabled`, `config_fiio_spdif_decode_enabled`, `config_fiio_spdif_input_mode_enabled`, `config_fiio_spdif_out_switch_enabled`, `config_fiio_status_bar_cutout_enabled`, `config_fiio_super_over_gain_enabled`, `config_fiio_sw_hold_in_enable`, `config_fiio_sw_hold_special_node`, `config_fiio_tape_mode_auto_det_sw`, `config_fiio_touch_bar_max_volume_enabled`, `config_fiio_uac_kernel_enabled`, `config_fiio_xmos_in_enabled`

### 7.3 Inteiros

| flag | valor |
|---|---|
| `config_fiio_audio_vol_default` | 60 |

### 7.4 Leitura

O conjunto ligado descreve o JM21 com precisao:

- **saida**: `bal_po_lo_select` (balanceado / PO / line-out), `po_lo_spdif_select`,
  `lineout_vol_adjust`, `output_gain`, `usbaudio_vol_adjust`,
  `spdif_output_mode`, `35mm_multiplexing_spdif` -> o aparelho tem **multiplas
  saidas selecionaveis**, coerente com 3,5 / 4,4 / LO / SPDIF.
- **DAC**: `digital_filter`, `dac_balance`, `dac_thdc2`, `p2d` (**PCM->DSD**),
  `EQ` -> e a base da aba de audio e do "All To DSD".
- **DAP**: `tape_mode`, `vehicle_mode`, `custom_key`, `custom_screen_saver`,
  `noheadset_auto_pause`, `usb_boot`.
- **energia**: `battery_charger_optimize`, `battery_disable_charger_setting`,
  `temp_manage` -> liga o `fiio-charger-manager` e o JEITA.
- **sem fio**: `bt_ldac`, `bt_lhdc`, `bluetooth_absolute_volume`,
  `bluetooth_audio_encoder`, `system_suspend_wifi_connect`, `roon`.

Desligadas que valem notar: `hdmi_in/out_arc`, `xmos_in`, `aes_in`, `spdif_in`,
`opt_decode`, `leds_*` (todas), `qsensor`, `uac_kernel`, `desktop_mode`,
`project_members` — features de **outros modelos** da linha FiiO.
