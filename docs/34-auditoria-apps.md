# 34 — Auditoria dos apps de sistema (issue #1)

> Inventário feito **no aparelho**: `pm list packages -f`, `pm path`,
> `sha256sum`. 95 APKs instalados a partir de partições de sistema
> (`/system`, `/product`, `/system_ext`, `/vendor`), fora APEX e apps de dados.

## 1. Apps da FiiO instalados

| Pacote | APK | SHA-256 (início) |
|---|---|---|
| `com.android.aboutfiio` | AboutFiio | `bc73a400` |
| `com.fiio.devicevendor` | DeviceVendor | `c805f467` |
| `com.fiio.entersleep` | EnterSleep | `b33fce34` |
| `com.fiio.scrcpy` | FiiOCast | `ec625f7d` |
| `com.fiio.fiioeq` | FiiOEq | `d845849b` |
| `com.fiio.ipod` | FiiOIpod | `4071fd9b` |
| `com.fiio.market` | FiiOMarket | `8ce51cb5` |
| `com.fiio.tape` | FiiOTape | `d7d7134b` |
| `com.android.fiioupdate` | FiiOUpdate | `6640260c` |
| `com.fiio.android` | ModeSelection | `2770d814` |
| `com.android.fiioroon` | Roon | `76805855` |
| `com.android.fiio.scrcpy` | Scrcpy | `3d3176a4` |


Cinco deles rodam com `android.uid.system` (ver docs/32): `com.fiio.tape`,
`com.fiio.ipod`, `com.android.fiioupdate`, `com.fiio.devicevendor`,
`com.fiio.entersleep`.

`com.fiio.music` **não** roda do `/system/app`: o aparelho usa a cópia de
`/data/app/…/com.fiio.music-…/base.apk` (atualizada por cima da de sistema).

## 2. Pré-instalados que **não** estão instalados

Existem em `/system/app` mas não aparecem em `pm list`:

`Chrome`, `Gboard`, `GoogleFiles`, `WIFI`, `CarrierDefaultApp`,
`CheckoutDevice`, **`DebugTool`**, **`EcaiTestAPP`**, **`FactoryTest`**,
`Iperf3` — e a cópia de sistema do `FiiOMusic`.

`[FATO]` `DebugTool`, `FactoryTest` e `EcaiTestAPP` são ferramentas de
fábrica/depuração que **não** rodam no aparelho de produção.

## 3. Pacotes citados no código mas **ausentes**

As allowlists de `services.jar` (docs/33) incluem nomes que não existem aqui:

| Pacote | Onde aparece | No aparelho |
|--------|--------------|-------------|
| `com.fiio.control` | `FIIO_PACKAGE_NAMES` | ausente |
| `com.fiio.dream` | `services.jar` | ausente |
| `com.alex.debugtool_player` | `OomAdjuster.cantFreezePackage` | ausente |
| `com.example.fiiotestappliction` | `DefaultPermissionGrantPolicy` | ausente |

Mais uma evidência do padrão "código compartilhado entre modelos".

## 4. ModeSelection (`com.fiio.android`)

É o app que troca o modo de operação — o mesmo `Settings.System
["system_mode_value"]` que o `PhoneWindowManager` lê para decidir entre
Android/Pure Music (`docs/33` §5.3). É a peça que faltava para a issue #8:
mudar de modo é uma escrita nesse inteiro.

## 5. Lista completa (95)

<details><summary>expandir</summary>

```
android.ext.shared
com.android.aboutfiio
com.android.bluetooth
com.android.bluetoothmidiservice
com.android.bookmarkprovider
com.android.captiveportallogin
com.android.carrierconfig
com.android.certinstaller
com.android.companiondevicemanager
com.android.cts.ctsshim
com.android.cts.priv.ctsshim
com.android.deskclock
com.android.documentsui
com.android.dreams.basic
com.android.dynsystem
com.android.externalstorage
com.android.fiio.scrcpy
com.android.fiioroon
com.android.fiioupdate
com.android.gallery3d
com.android.htmlviewer
com.android.inputdevices
com.android.inputmethod.latin
com.android.intentresolver
com.android.keychain
com.android.launcher3
com.android.location.fused
com.android.managedprovisioning
com.android.modulemetadata
com.android.mtp
com.android.networkstack
com.android.packageinstaller
com.android.providers.blockednumber
com.android.providers.downloads
com.android.providers.downloads.ui
com.android.providers.media
com.android.providers.settings
com.android.providers.userdictionary
com.android.provision
com.android.proxyhandler
com.android.remoteprovisioner
com.android.se
com.android.settings
com.android.settings.intelligence
com.android.shell
com.android.smspush
com.android.soundpicker
com.android.statementservice
com.android.storagemanager
com.android.systemui
com.android.traceur
com.android.vpndialogs
com.android.wallpaper
com.android.wallpaper.livepicker
com.android.wallpaperbackup
com.android.wallpapercropper
com.android.webview
com.fiio.android
com.fiio.devicevendor
com.fiio.entersleep
com.fiio.fiioeq
com.fiio.ipod
com.fiio.market
com.fiio.scrcpy
com.fiio.tape
com.google.android.gsf
com.google.android.syncadapters.calendar
com.google.android.syncadapters.contacts
com.qti.dpmserviceapp
com.qti.qualcomm.mstatssystemservice
com.qualcomm.location
com.qualcomm.location.XT
com.qualcomm.qti.biometrics.fingerprint.service
com.qualcomm.qti.devicestatisticsservice
com.qualcomm.qti.dynamicddsservice
com.qualcomm.qti.performancemode
com.qualcomm.qti.powersavemode
com.qualcomm.qti.qms.service.connectionsecurity
com.qualcomm.qti.server.qtiwifi
com.qualcomm.qti.services.secureui
com.qualcomm.qti.services.systemhelper
com.qualcomm.qti.xrcb
com.qualcomm.qti.xrvd.service
com.qualcomm.qtil.aptxacu
com.qualcomm.qtil.aptxals
com.qualcomm.qtil.aptxui
com.qualcomm.qtil.btdsda
com.qualcomm.timeservice
com.qualcomm.wfd.service
vendor.qti.data.txpwradmin
vendor.qti.hardware.cacert.server
vendor.qti.imsdatachannel
vendor.qti.imsrcs
vendor.qti.iwlan
vendor.qti.qesdk.sysservice
```
</details>
