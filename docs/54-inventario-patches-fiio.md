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
