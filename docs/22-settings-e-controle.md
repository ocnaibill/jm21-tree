# 22 — Plano de controle: Settings, Scrcpy e a ponte `setCodecParam`

> Fonte: `Settings.apk` (`com.android.settings.fiio.*`, 4 846 classes) e
> `Scrcpy.apk` (`com.android.fiio.scrcpy`) decompilados com JADX, mais
> `framework.jar`. Fecha o elo que faltava: **quem escreve as propriedades**.

## 1. A ponte Java → HAL

`[FW]` `framework.jar` expõe duas APIs ocultas que o HAL implementa:

```java
AudioSystem.setMasterVolumeDac(int volume)          // volume (docs/19 §3)
AudioSystem.setCodecParam(int type, int value)      // controle (tabela abaixo)
```

`setCodecParam` chega em `fiio_adev_set_codec_param(adev, type, v1, v2, v3)`
(docs/19 §2). Agora temos os **chamadores reais**:

| `type` | Controle | Quem chama |
|--------|----------|-----------|
| 1 | `DAC LR Balance` | `EqControlService` |
| 2 | `DAC PO Gain` | `GainPreferenceController` |
| 3 | `DAC Digital Filter Mode` | `DigitalFilterPreferenceController` |
| 7 | (abort delay) | `AudioSettingManager` (Scrcpy) |
| 19 | (flag de play config) | `EqControlService` |
| 100 | (broadcast de params) | — |

## 2. Settings — o painel real

O menu FiiO vive em `com.android.settings.fiio`:

| Classe | O que faz |
|--------|-----------|
| `audio/AllToDsdPreferenceController` | escreve `persist.sys.all.to.dsd` e `all2dsd_ctl_value` |
| `audio/GainPreferenceController` | `setCodecParam(2, i)` + `po_bah_gain` / `po_bah_gain_backup` |
| `audio/DigitalFilterPreferenceController` | `setCodecParam(3, i)` |
| `audio/EqControlService` | `setCodecParam(1, i)` (balanço) e `setCodecParam(19, ...)` |
| `audio/SpdifOutSwitchPreferenceController` | `persist.sys.audio.output.select` = `2` (SPDIF) ou `0` |
| `audio/SpdifOutFormatPreferenceController`, `SpdifInputModePreferenceController` | formato/entrada SPDIF |
| `audio/DRESwitchPreferenceController` | DRE |
| `audio/LineOutVolumePreferenceController`, `UsbAudioVolumePreferenceController` | volumes de LO e USB |
| `audio/THDC2PreferenceController` + `THDC2FragmentPreferenceController` | THD C2 |
| `audio/BalancePreferenceController`, `DacBalanceDialogFragment` | balanço L/R |
| `audio/NoHeadphoneAutoPauseController` | pausa automática sem fone |
| `audio/HeadSetPreferenceController` | tipo de fone |
| `audio/Bluetooth*PreferenceController` | encoder, qualidade, LDAC, LHDC, volume absoluto |
| `led/ledControlService` | LEDs (observa `system_mode_value`) |
| `deviceinfo/aboutphone/FiiODeviceInfo*` | tela "sobre" (usa `config_sn`/`config_nb`) |
| `RemoteUpdateSettingService` | aplica ajustes vindos de controle remoto |

`[FW]` `SettingsReceiver` também escreve `persist.sys.audio.output.select` —
ou seja, a propriedade tem dois escritores (preferência e receiver).

## 3. Scrcpy — não é só espelhamento

O app `com.android.fiio.scrcpy` é um **serviço de controle remoto**
(protocolo scrcpy): `ScrcpyService` recebe `controlMessage` e injeta eventos.

```java
injectSettingEvent(type, value)          // AudioSettingManager
  type 2 (ALLTODSD): setAudioAbortDelay(); set prop; putInt("all2dsd_ctl_value")
  type 1 (GAIN)    : putInt("po_bah_gain"); AudioSystem.setCodecParam(2, value)
  type 3 (MODE)    : broadcast de troca de modo
```

Ou seja: o mesmo ajuste pode ser feito **localmente (Settings)** ou
**remotamente (Scrcpy/FiiO Link)** — os dois terminam no mesmo estado.

## 4. Modos de operação (enum do app)

```java
ANDROID_MODE   = 0     PUREMUSIC_MODE = 1
AIRPLAY_MODE   = 2     USBDAC_MODE    = 3
BTSINK_MODE    = 4     SPDIF_RX_MODE  = 5
ROON_MODE      = 6     OPT_IN_MODE    = 7
```

Intenções usadas:

```
fiio.intent.action.SYSTEM_MODE_CHOOSE
fiio.intent.action.POWER_KEY_CHANGE_MODE
com.android.intent.action.SOUND_SETTING_UPDATE
android.media.AUDIO_BECOMING_NOISY
```

E a propriedade `fiio.roon.enabled` é ligada/desligada junto com o modo Roon
(`stopApp("com.android.fiioroon")`).

## 5. Chaves em `Settings.System`

| Chave | Uso |
|-------|-----|
| `po_bah_gain` / `po_bah_gain_backup` | ganho PO atual/anterior |
| `system_mode_value` | modo de operação (0–7) |
| `all2dsd_ctl_value` | estado do ALL TO DSD (espelho da propriedade) |

## 6. Diagrama final do plano de controle

```
Settings (UI)  ─┐
                ├─→ AudioSystem.setCodecParam(type, v) ─→ HAL ─→ kcontrol ─→ dac_core ─→ cs43198
Scrcpy (remoto) ┘                                          (2=PO Gain, 3=Filter, 1=Balance…)

Settings (AllToDsd) ─┐
Scrcpy (ALLTODSD)   ─┼─→ persist.sys.all.to.dsd / audio.output.select ─→ HAL (match_audio_process_mode)
Roon (leitura)      ─┘

Settings (àudio) ─→ Sysfs soc:fiio_attr/*  (LED, FPGA, headset, config_sn…)
```

`[?]` Falta apenas saber se alguma dessas chaves é escrita por **serviço do
sistema** além dos apps — o `RemoteUpdateSettingService` sugere que sim, mas o
caminho remoto passa pelo Scrcpy.

## 7. Consequência prática

Para reproduzir qualquer ajuste **sem a interface**, há três caminhos, em ordem
de segurança:

1. `AudioSystem.setCodecParam(type, valor)` — o caminho oficial do framework.
2. `setprop persist.sys.…` — usado por ALL TO DSD e saída SPDIF.
3. `echo valor > /sys/devices/platform/soc/soc:fiio_attr/…` — só para o que não
   tem kcontrol (FPGA, LED, config).

Isso é o que qualquer app de controle precisa usar — e é o que a issue #2
(FiiOMusic) não fazia: ele só lê o estado.

## 8. Segurança (para a issue #1)

- `AudioSystem.setCodecParam` é API **oculta**: só apps com assinatura de
  plataforma (Settings, Scrcpy) conseguem chamar.
- As propriedades `persist.sys.all.to.dsd` e `persist.sys.audio.output.select`
  são globais: **qualquer app** com permissão de `setprop` de `persist.*`
  (geralmente apps de sistema) muda o caminho de áudio do aparelho inteiro.
- Já os nós `fiio_attr` são `0666` (docs/18 §7) — o SELinux é a única barreira.
