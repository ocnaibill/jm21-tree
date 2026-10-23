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

## 5. Histórico de firmware e changelog oficial

Fonte: tópico oficial de firmware do JM21 no fórum da FiiO (atualizado
2026-04-29) —
[forum.fiio.com/note/showNoteContent.do?id=202412181641298410115](https://forum.fiio.com/note/showNoteContent.do?id=202412181641298410115&tid=17)
— e o anúncio oficial [fiio.com/newsinfo/1128867.html](https://www.fiio.com/newsinfo/1128867.html).
Os itens abaixo são os que **tocam áudio** — e cada um casa com um caminho de
código que já vimos no firmware.

| Versão | Data | Item de changelog | Correlação no binário |
|--------|------|-------------------|-----------------------|
| 1.0.2 | 2024-11-18 | corrige ruído/volume em saída USB em apps de terceiros; ruído em DSD via Bluetooth | caminho USB (`audio.usb.bengal.so`) |
| 1.0.3 | 2024-12-31 | compatibilidade de USB Audio | idem |
| 1.0.4 | 2025-01-09 | corrige crash na reprodução em Pure Music | `ModeSelection`/Pure Music |
| 1.0.5 | 2025-01-20 | double tap to wake | — |
| **1.0.6** | 2025-04-21 | **PEQ do sistema**, **ALL TO DSD**, **MQA**, **DoP em USB DAC**, decode de iPhone no modo USB DAC | `init_pcm2dsd`/shaper, `libfiioaqm.so`, DoP, UAC |
| 1.0.7 | 2025-06-05 | modo cassete, volume da saída USB do sistema ajustável, remote control | `FiiOTape` |
| **1.0.8** | 2025-09-26 | **switch do DAC DRE**, temas de VU/spectrum, carga otimizada | `anolog_board_dac_dre_store`, `board_dac_dre_switch`, `dre_setting` |
| **1.1.0** | 2025-12-23 | car mode, AUTO EQ, **corrige "pop" na primeira reprodução e na troca de faixa** | `volume_fade_in`, `pre_write_zero_size`, `get_dsd_write_zero_mark` |
| **1.1.1** | 2026-04-29 | RETRO BOX por Bluetooth, compartilhamento de EQ, tema Pod Mode, temas de cassete; corrige reboot em loop ao carregar após desligamento por bateria baixa, anormalidade em transmissão BT, corrente de carga baixa | — |

Leituras:

- **"ALL TO DSD"** é o `init_pcm2dsd` + *noise shaping* que a `libfiioaudio.so`
  carrega. É uma função de **upsampling para DSD**, não reprodução nativa.
- **"DAC DRE"** é *Dynamic Range Enhancement* do CS43198 — confirma que
  `dre_setting` é uma opção exposta ao usuário e persistida.
- A correção de "pop" da 1.1.0 é exatamente a razão de existirem as rotinas de
  silêncio inicial (`get_pcm*_pre_write_zero_size`) e `volume_fade_in`.
- **MQA** e **DoP em USB DAC** chegaram juntos na 1.0.6 → coerente com
  `libfiioaqm.so` e com os modos UAC.

`[?]` O texto do changelog não é idêntico ao `log_1.1.1.txt` referenciado na
propriedade `ro.product.version.update_log` (esse arquivo vem do servidor junto
do pacote, não do firmware).

## 6. OTA e atualização

`[FW]` `FiiOUpdate.apk` usa:

```
ro.product.ota.host=jm21pack.fiio.net
ro.product.ota.package_name=JM21-ota-1.1.1.zip
ro.product.version=1.1.1
ro.product.version.update_log=log_1.1.1.txt
```

Links oficiais e distinção completo × incremental estão em
`02-firmware-e-particionamento.md` §6. Resumo: o arquivo local é o **completo**
(`beta/JM21-update-1.1.1.zip`, 1 642 845 150 bytes); o nome `JM21-ota-…` é o
**incremental** (92 668 277 bytes).

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
