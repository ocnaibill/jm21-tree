# 05 — Framework, aplicativos e camada Java

## 1. O que a FiiO modificou no sistema

`[FW]` **Não existe** `fiio-framework.jar` (a primeira versão do dossiê supunha
isso). As modificações estão **dentro** dos jars padrão:

| Arquivo | Tamanho | Modificado? |
|---------|---------|-------------|
| `/system/framework/framework.jar` | 38 395 887 | `[HIP]` sim (não diffado ainda) |
| `/system/framework/services.jar` | 17 647 302 | **sim** — confirmado |
| `/system/framework/framework-res.apk` | 67 544 683 | `[HIP]` sim (temas/strings) |

### Evidência direta em `services.jar` `[FW]`

`strings` nos `classes*.dex` de `services.jar` revelam:

```
FIIO_PACKAGE_NAMES
AMS fiio check package
CE fiio check package
com.android.systemui.action.FIIO_POWER_KEY_DIALOG
fiio.test.show_power_key_view
sys.fiio.home_disabled
fiio.current.play.device
fiio.intent.action.ACTION_EXTERNAL_CHARGING
fiio.intent.action.ACTION_EXTERNAL_DISCHARGING
fiio.intent.action.KEY.EVENT
fiio.intent.action.USB_AUDIO_DEVICE_CHANGE
```

Leitura:

- **`FIIO_PACKAGE_NAMES` + "AMS/CE fiio check package"**: o ActivityManager (AMS)
  e o package manager (CE = credential-encrypted?) têm uma lista branca/negra de
  pacotes FiiO. É um gancho de framework, não um app.
- **`fiio.intent.action.KEY.EVENT`**: eventos de botão físico (o JM21 tem teclas
  de transporte) são repassados como broadcast global.
- **`USB_AUDIO_DEVICE_CHANGE`**: notificação de entrada/saída de DAC USB.
- **`home_disabled`**: modo quiosque / Pure Music desliga o launcher.
- **`FIIO_POWER_KEY_DIALOG`**: substituição do diálogo de power do SystemUI.

### Pacotes FiiO conhecidos `[FW]`

```
com.fiio.music          → FiiOMusic
com.fiio.tape           → FiiOTape
com.fiio.market         → FiiOMarket
com.fiio.control
com.fiio.devicevendor   → DeviceVendor
com.fiio.dream          → BasicDreams? (screensaver)
com.fiio.scrcpy         → Scrcpy
com.android.aboutfiio   → AboutFiio
com.android.fiioupdate  → FiiOUpdate
com.android.fiioroon    → Roon
com.example.fiiotestappliction   ← app de teste esquecido no build
```

`[?]` `com.fiio.control` e `com.fiio.devicevendor` são os mais interessantes:
provavelmente donos de parte dos canais de controle de hardware.

## 2. Inventário de apps de sistema

`/system/app` `[FW]` — só os relevantes para o laboratório:

| App | APK | Papel provável |
|-----|-----|----------------|
| **FiiOMusic** | 117 195 976 | player principal (líder de áudio) |
| **FiiOTape** | 132 943 469 | app de cassete/efeito (o maior APK do sistema) |
| **AboutFiio** | 26 659 365 | info do dispositivo/serial |
| **ModeSelection** | 18 869 383 | **Android × Pure Music** |
| **FiiOUpdate** | 16 752 682 | cliente de OTA (`jm21pack.fiio.net`) |
| **FiiOCast** | 13 456 868 | AirPlay/Cast |
| **EnterSleep** | 13 353 959 | modo sono/desligamento |
| **DeviceVendor** | 13 464 746 | vendor app (tem `lib/`) |
| **Roon** | 9 463 707 | endpoint Roon (`fiio.roon.enabled`) |
| **FiiOIpod** | 7 690 247 | suporte iPod/USB host |
| **FiiOEq** | 6 867 645 | equalizador |
| **Scrcpy** | 4 864 334 | espelhamento de tela |
| **FactoryTest** | 4 180 450 | teste de fábrica |
| **FiiOMarket** | 4 045 254 | loja de apps |
| **DebugTool** | 2 956 408 | ferramenta de diagnóstico |
| **EcaiTestAPP** | 2 013 337 | teste (E-CAI?) |

`[?]` `EcaiTestAPP` e `com.example.fiiotestappliction` indicam que o build de
produção carrega artefatos de teste. Vale inspecionar: podem expor intents ou
serviços sem proteção.

## 3. Bibliotecas nativas do player

`FiiOMusic.apk` → `lib/arm64-v8a/` `[FW]`:

| Lib | Tamanho | Papel |
|-----|---------|-------|
| `libhello-jni.so` | 9 235 104 | nome genérico de projeto de exemplo; provavelmente o *core* do player |
| `libijkffmpeg.so` | 10 365 192 | ijkplayer/FFmpeg (decode) |
| `libffmpegAPI.so` | 26 000 | ponte FFmpeg |
| `libUsbAudio.so` | 141 152 | UAC (DAC USB / host) |
| `libfiioa-jni.so` | 234 824 | JNI de áudio FiiO |
| `libfiioac-jni.so` | 234 696 | JNI de "AC" (?) |
| `libfiiocd-jni.so` | 126 344 | JNI de "CD" (?) |
| `libeqLib.so` | 63 240 | DSP do equalizador |
| `libfilterAPI.so` | 17 808 | filtros |
| `libm3u.so` | 955 232 | playlists |
| `liblhdc.so` | 92 056 | codec Bluetooth LHDC |
| `libRSSupport.so`, `librsjni*.so` | — | RenderScript |

`libhello-jni.so` com 9 MB é um cheiro forte: nome de template Android NDK
usado para um binário grande e proprietário. `[?]` Confirmar se contém o
decodificador DSD/MQA.

## 4. Ordem de análise sugerida (fase Java)

1. **`FiiOMusic`** — o app que fala com a HAL. Procurar:
   - uso de `fiio.current.play.device`, `persist.sys.fiio.*`;
   - binding a serviços de `com.fiio.control`/`com.fiio.devicevendor`;
   - chamadas JNI (`libfiioa-jni`) e o que passam para `FiiOAudioConfigParams`.
2. **`ModeSelection`** (18,9 MB) — como o modo "Pure Music" é ativado e o que ele
   desliga (`sys.fiio.home_disabled`, `fiio.use.kernel.play`).
3. **`DeviceVendor`** — vendor app, costuma concentrar HALs Java e permissões.
4. **`FiiOEq`** (pequeno) — liga a UI aos parâmetros de `libeqLib` e ao
   `fiio_adev_set_eq_param`.
5. **`DebugTool` / `FactoryTest`** — podem expor comandos privilegiados e
   revelar nomes de nós/sysfs de teste.
6. **`services.jar` diff vs AOSP** — achar exatamente onde estão os ganchos.

### Como fazer o diff de jars

```bash
# 1. baixar o qssi-13 / Android 13 correspondente (TKQ1.230110.001)
# 2. extrair classes.dex de cada jar
unzip -o analysis/fw-1.1.1/framework/services.jar 'classes*.dex' -d /tmp/svc
# 3. comparar listas de classes com a referência
#    (jadx ou dexdump/baksmali; nenhum instalado ainda)
```

Sem JADX, o caminho barato é: `strings` + `dexdump` (do Android SDK build-tools)
para listar classes/métodos e comparar nomes. `[?]` `dexdump` não verificado no
host.

## 5. OTA e atualização

`[FW]` `FiiOUpdate.apk` usa:

```
ro.product.ota.host=jm21pack.fiio.net
ro.product.ota.package_name=JM21-ota-1.1.1.zip
ro.product.version=1.1.1
ro.product.version.update_log=log_1.1.1.txt
```

`[?]` `log_1.1.1.txt` não foi localizado nas partições do payload (provavelmente
baixado do servidor junto com o pacote). Próximo passo: recuperar o changelog
oficial e anexar resumido aqui.

## 6. Outros artefatos curiosos

| Arquivo | Tamanho | Nota |
|---------|---------|------|
| `/system/etc/fiio_mtp_driver.iso` | 34 406 400 | "driver MTP" em formato ISO — `[?]` provavelmente instalador para Windows exposto via USB |
| `/system/etc/audio_effects.conf` | 5 668 | efeitos legados |
| `/system/app/Traceur` | — | app de traces do AOSP |
| `/system/app/Iperf3` | — | teste de rede |

## 7. Perguntas abertas

1. `[?]` Conteúdo de `fiio_mtp_driver.iso` (é executável de Windows? assinado?).
2. `[?]` Quais serviços exportados por `DebugTool`, `FactoryTest`,
   `EcaiTestAPP` e `com.example.fiiotestappliction` (risco de segurança).
3. `[?]` O que `com.fiio.control` expõe (binder/AIDL?).
4. `[?]` `libhello-jni.so` contém decodificador DSD/MQA proprietário?
5. `[?]` Lista real em `FIIO_PACKAGE_NAMES` (extrair do dex).
6. `[?]` Diff exato de `framework.jar` e `services.jar` contra AOSP-13.
