# 32 — Apps restantes (issue #7)

> APKs puxados do **próprio aparelho** (`pm path` → `adb pull`), decompilados com
> JADX 1.5.6. Manifests e código são a evidência; o que não se confirma por
> código/sysfs está marcado como hipótese.

## 1. Inventário e hashes

| Pacote | App | sharedUserId | SHA-256 (prefixo) |
|--------|-----|--------------|--------------------|
| `com.fiio.music` | FiiO Music (+ DLNA) | — | (ver docs/21) |
| `com.fiio.scrcpy` | **FiiO Cast** (projeção de tela) | — | (FiiOCast.apk) |
| `com.fiio.fiioeq` | Equalizer | — | `d845849b…` |
| `com.android.fiioroon` | FiiO Roon | — | (Roon.apk do OTA) |
| `com.fiio.ipod` | Pod Mode | **android.uid.system** | `4071fd9b…` |
| `com.fiio.tape` | Tape Mode | **android.uid.system** | `d7d7134b…` |
| `com.fiio.market` | Applications (loja) | — | `8ce51cb5…` |
| `com.android.aboutfiio` | Technical Support | — | `bc73a400…` |
| `com.android.fiioupdate` | Atualização de sistema | **android.uid.system** | `6640260c…` |
| `com.fiio.devicevendor` | Vendor Services | **android.uid.system** | `c805f467…` |
| `com.fiio.entersleep` | Tela de dormir | **android.uid.system** | `b33fce34…` |

**Cinco apps rodam com `android.uid.system`** — privilégio total. É o padrão de
DAP da FiiO, mas explica por que elas escrevem em sysfs e fazem reboot.

## 2. Equalizer (`com.fiio.fiioeq`)

- **Não** é system uid; é app comum.
- Usa o **framework de AudioEffect do Android** (157 referências a `AudioEffect`,
  22 a `Equalizer`, 11 a `BassBoost`) — ou seja, EQ **em software**, pela cadeia
  de efeitos do sistema.
- Confirmação no aparelho: `/vendor/lib/soundfx/` tem só as libs AOSP/Qualcomm
  (`bundlewrapper`, `downmix`, `reverbwrapper`, `visualizer`…), **nenhuma lib de
  efeito da FiiO**.
- Liga/desliga por `persist.sys.eq.enable` (`"1"` = ligado).
- Tem recursos de EQ automático/paramétrico (`com.fiio.fiioeq.autoeq.*`:
  curvas, filtros, `ParametricEqConfig`, `AutoFilters`).
- Limitações já medidas: EQ **bloqueado em DSD/MQA** (mensagem do app) e em
  **DLNA transmitting**.

## 3. FiiO Cast (`com.fiio.scrcpy`) — **existe, e não é DLNA**

> Correção: a primeira versão desta seção dizia que Cast era o DLNA do FiiO
> Music. O APK está em `/system/app/FiiOCast/FiiOCast.apk` e o pacote é
> `com.fiio.scrcpy`.

`[FATO]` É um app de **projeção de tela + controle remoto**, não de DLNA:

| Componente | Papel |
|------------|-------|
| `SelectionActivity` | escolha do modo |
| `RemoteActivity` | controle remoto |
| `ScreenSyncService` | captura/espelha a tela |
| `UDPBroadcastService` | descoberta/anúncio por **UDP** |
| `MediaMetaDataService` | metadados da faixa para o controle |
| `BootCompleteReceiver` | sobe no boot |
| `journeyapps.barcodescanner.CaptureActivity` | pareamento por **QR code** |

Permissões: `ACCESS_SURFACE_FLINGER` (captura de tela), `RECORD_AUDIO`,
`CAMERA`, `INTERNAL_SYSTEM_WINDOW`, `SYSTEM_ALERT_WINDOW`, `UDP`/Wi-Fi.

Texto do app: *"Project the screen of the device to a mobile phone, and allow
the phone to remotely view and control the device"*.

O **DLNA** é outra coisa: está dentro do **FiiO Music** (`DLNA receiving`,
`DLNA transmitting`, `DLNA-Empf`), com o aviso de EQ indisponível durante a
transmissão.

## 4. FiiO Roon (`com.android.fiioroon`)

- App separado, com um **plugin de saída próprio**: `com.fiio.roon.outputPlugin`
  (`AudioFocusManager`, `IAudioSystem`, `IAudioTrack`).
- Toca por **`AudioTrack`** (176 referências) — não usa caminho nativo/DSD
  exclusivo.
- Tem **configuração por SoC**: `Sdm660Config`, `Sc66Config`, `Ex7872Config` —
  o mesmo código serve vários DAPs FiiO.
- Tem `UsbAudioSupportSampleRate` (a mesma lista de taxas por USB do Music) e
  strings de DSD (55 referências), 352,8 k e 384 k.

## 5. Pod Mode (`com.fiio.ipod`) e Tape Mode (`com.fiio.tape`)

Ambos são **temas de interface**, não processamento de áudio:

| | Pod Mode | Tape Mode |
|---|---|---|
| Nome visível | "Pod Mode" / "Pod" | "Tape Mode" / "Exit Tape Mode" |
| Conteúdo grande | imagens de skin | ~60 MB de **fontes** (Source Han) |
| APIs de áudio | nenhuma (`AudioRecord`/`AudioTrack`/`AudioEffect` ausentes) | idem |
| Receptor | — | `fiio.intent.action.TAPE_SHELL_MODE` |

**O caso do Tape Mode:** o `com.fiio.devicevendor` escreve em
`soc:fiio_attr/tape_auto_detect` e `soc:fiio_attr/send_tape_type` (controlado por
`persist.tape.mode.auto.detect`). **Esses nós não existem no JM21** (verificado:
leitura vazia), então as escritas falham em silêncio. É o mesmo padrão dos
controles "fantasma" da HAL: código compartilhado com outros modelos.

## 6. Applications — a loja (`com.fiio.market`)

- Baixa metadados de APK de:
  `https://fiiomarket.oss-cn-shanghai.aliyuncs.com/new_apkinfos_{cn,en,0_manager}.txt`
  (bucket Alibaba OSS).
- Permissões: `INSTALL_PACKAGES`, `QUERY_ALL_PACKAGES`, `REQUEST_INSTALL_PACKAGES`
  — instala apps sozinha.

## 7. Technical Support (`com.android.aboutfiio`)

- App de "sobre/suporte": textos de ajuda, instruções de atualização, e
  permissões **`REBOOT`**, `WRITE_SECURE_SETTINGS`, `ACCESS_MTP`.
- Lê `sys.fiio.sn_num` (número de série).
- Fala com `47.90.93.62` (IP na Alibaba Cloud).

## 8. Atualização de sistema (`com.android.fiioupdate`) — **URL confirmada**

`Conts.java` monta a URL a partir de `ro.product.model`
(`"FiiO JM21"` no aparelho):

```java
// versão
String.format("http://%spack.fiio.net/versionCN.txt",
              modelName.toLowerCase().split("fiio")[1].trim());
// pacote
String.format("http://%spack.fiio.net/%s-updateCN.zip",
              modelName.toLowerCase().split("fiio")[1].trim(),
              modelName.toUpperCase().split("FIIO")[1].trim());
```

Para o JM21 isso dá:

```
http://jm21pack.fiio.net/versionCN.txt      (ou versionEN.txt)
http://jm21pack.fiio.net/JM21-updateCN.zip  (ou updateEN.zip)
http://jm21pack.fiio.net/inc/patchCN.txt    (incremental)
```

`[CORREÇÃO — segunda tentativa]` Eu havia dito que o caminho do pacote era
`JM21-updateCN.zip` (montado por `getCNUpdatePackagePath`). **O servidor
desmente:** o fluxo real começa no manifesto

```
http://jm21pack.fiio.net/beta/patchCN.txt   (e /inc/patchCN.txt)
```

que aponta para

```
PatchUrl="http://jm21pack.fiio.net/beta/JM21-update-1.1.1.zip"
```

ou seja, **exatamente o padrão do relatório externo**
(`/beta/JM21-update-<ver>.zip`). `JM21-updateCN.zip` dá **404**. As funções
`get*UpdatePackagePath()` do `Conts.java` são um caminho legado/alternativo que
não é servido para este modelo.

Consequência prática: **a versão mais nova é a 1.1.1** (a nossa) — não há
firmware posterior onde o módulo `mode_select` pudesse existir.

Detalhe de modelo: para JM21 o updater usa **barra de progresso em duas
metades** (50 % + 50 %), tratamento específico de `isJM21 && SDK==33`.

Há também envio de log para `pack.fiio.net/log{CN,EN}_<modelo>.txt`.

## 9. Vendor Services (`com.fiio.devicevendor`)

System uid; serviços `VendorServices`, `WifiMonitor`, listener de notificações.
Escreve direto em sysfs:

| Nó | Uso |
|----|-----|
| `active_wakeup` | `SCREEN_OFF_OPEN` / `SCREEN_OFF_CLOSE` / `RELEASE` |
| `screen_state` | `ON` |
| `ts_screen_off` | desliga o touch junto com a tela |
| `send_charge_type` | tipo de carregador |
| `i2c_test_get_failed_count` | contador de falhas de I²C (o nó "fantasma" `i2c_test_*`) |
| `tape_auto_detect`, `send_tape_type` | **inexistentes no JM21** |

Também abre a `EnterSleep` (`com.fiio.entersleep.EnterSleep`) em vez de dormir
pelo framework.

## 10. Conclusões

1. **Nenhum app escreve no DAC.** Volume, filtros e mute continuam exclusivos da
   HAL (`libfiioaudio.so`) → `dac_core` → I²C. Os apps só mexem em propriedades
   e sysfs de plataforma.
2. **EQ é software** (AudioEffect do AOSP). Não há efeito no FPGA nem no DAC
   para EQ.
3. **Cast, Pod e Tape não são features de áudio**: Cast é **projeção de tela +
   controle remoto** (app próprio, `com.fiio.scrcpy`); o DLNA está no Music;
   Pod e Tape são skins.
4. Vários apps são **compartilhados entre modelos** e escrevem em nós que o
   JM21 não tem — o mesmo padrão dos controles fantasma da HAL.
5. A URL de OTA é **derivada do modelo** (`ro.product.model`), e o caminho do
   pacote é `JM21-updateCN.zip`, não `update-<ver>.zip`.
