# 37 — Modos de operação: mapa, mecânica e o que testar (issue #8, parte offline)

> Fonte: `com.android.settings.fiio.ModeChooseFragment` e
> `com.fiio.android.ModeChooseService`/`ModeSelection`, decompilados do
> `Settings.apk` e do `ModeSelection.apk` (`com.fiio.android`).

## 1. O mapa de valores

`Settings.System["system_mode_value"]`:

| Valor | Modo | Disponível no JM21? |
|-------|------|---------------------|
| **0** | Android | ✅ (valor atual, medido) |
| **1** | Pure Music | ✅ |
| **2** | AirPlay | ✅ |
| **3** | USB DAC | ✅ |
| **4** | BT receiving (sink) | ✅ |
| **5** | SPDIF RX (coaxial) | ❌ `config_fiio_spdif_input_mode_enabled=false` |
| **6** | **Roon** | ✅ (tratado no serviço; não aparece no rádio) |
| 7 | OPT IN | ❌ `isOptInModeEnabled` |
| 8 | HDMI IN | ❌ `config_fiio_hdmi_in_enabled=false` |
| 9 | HDMI OUT ARC | ❌ `config_fiio_hdmi_out_arc_enabled=false` |

O `ModeChooseFragment` esconde 5, 7, 8 e 9 consultando as flags do framework
(`docs/33` §4). O valor **6** (Roon) não está no rádio, mas o
`ModeChooseService` o trata.

## 2. A mecânica da troca

```
UI (ModeChooseFragment) --broadcast--> ModeChooseService
   Intent("fiio.intent.action.SYSTEM_MODE_CHOOSE", extra "mode"=N)
```

`ModeChooseService.modeChooseAction(mode)`:

| Modo | O que faz |
|------|-----------|
| 0 | `setSystemMode(0)` |
| 1 (Pure Music) | `setSystemMode(1)`, fecha tarefas recentes, pausa áudio, abre `com.fiio.music/.activity.SplashActivity`, esconde a status bar; se a tela estiver bloqueada, destranca antes (delay 100 ms) |
| 6 (Roon) | `setSystemMode(6)`, `fiio.roon.enabled=1`, abre `com.android.fiioroon/.MainActivity` e **volta o valor para 0** |
| 2,3,4,5,7,8,9 | `gotoModeSelection(mode)` → abre `com.fiio.android/.ModeSelection` com `targetMode` |

Dentro do `ModeSelection`:

| `targetMode` | Ação |
|--------------|------|
| 1 | `setModeSelectCtrl(1)` + `setSystemMode(1)` + inicia Pure Music |
| 3 (USB DAC) | `setSystemMode(3)`; o gadget UAC sobe pelo serviço |
| 4 (BT sink) | `setSystemMode(4)` + `startInitMode(4)` |
| 5 / 7 | `setSystemMode(5)` ou `(7)` (SPDIF/OPT in) |
| 8 / 9 | HDMI in / ARC (indisponíveis no JM21) |

Ao entrar em qualquer modo, o app também escreve:

```
SystemProperties.set("sys.fiio.home_disabled", "true");
SystemProperties.set("sda660.mode.selection", "true");
```

`sys.fiio.home_disabled` é o mesmo que o `PhoneWindowManager` lê para desligar
a tecla Home (`docs/33` §5.3).

## 3. Saída do USB DAC (importante para o teste)

`ModeChooseService.resetUsbDac()`:

```java
if (fiio.uac.active == "true") {
    SystemProperties.set("sys.usb.config", isUserDebug() ? "mtp,adb" : "mtp");
    SystemProperties.set("fiio.stop.uac.user", "0");
    SystemProperties.set("fiio.uac.active", "false");
}
```

`[FATO]` Em build **userdebug** (é o caso: `ro.debuggable` já foi visto no
aparelho), sair do modo USB DAC **devolve `mtp,adb`** — ou seja, o adb volta
sozinho. O modo USB DAC continua sendo o mais arriscado da lista, mas a saída
é conhecida.

## 4. Por que isso importa para a issue #8

Os kcontrols que faltam no JM21 (`DAC MUTE`, `MasterTrim L/R`, `Hifi Boost
Mode`, `Audio Headset Type`) são criados pela HAL a partir do **modo**. Já
sabemos que:

- o modo é um inteiro em `Settings.System` (fácil de trocar e observar);
- a troca mexe em `sys.fiio.home_disabled` e `sda660.mode.selection`;
- o `dac_core` registrou no boot: `get mode_select module failed!` — o módulo
  `mode_select` **não** foi encontrado, o que pode explicar controles ausentes.

## 5. Ordem de teste proposta (do mais seguro ao mais arriscado)

| # | Modo | Risco | O que ganhamos |
|---|------|-------|----------------|
| 1 | **Pure Music (1)** | nenhum (adb fica) | primeiro teste da hipótese "modo expõe kcontrols" |
| 2 | BT receiving (4) | baixo | modo de entrada, mas sem USB |
| 3 | AirPlay (2) | baixo | entrada de rede |
| 4 | USB DAC (3) | **adb cai** | último; saída documentada acima |

Procedimento por modo: trocar pelo menu (Ajustes → Modo, ou o diálogo de modo),
rodar `tinymix -D 0` (ou o coletor de kcontrols) e comparar com o baseline. O
baseline de 44,1 k já está em `docs/19`.

**Não testar** 5, 7, 8, 9: as flags dizem que não existem neste modelo.

## 6. Resultado medido — Pure Music **não** muda os kcontrols

Teste em 2026-10-24, com o aparelho no modo Android e depois em Pure Music:

| Estado | `system_mode_value` | Controles ALSA | Controles FiiO |
|--------|---------------------|----------------|----------------|
| Android | 0 | **160** | 6 |
| Pure Music | **1** | **160** | 6 |

`diff` das duas listas: **vazio**. Os quatro controles ausentes (`DAC MUTE`,
`MasterTrim L/R`, `Hifi Boost Mode`, `Audio Headset Type`) continuam ausentes.

### A causa raiz apareceu no kernel

`dmesg`, no boot:

```
[dac_core]:      get mode_select module failed!
[anolog_board]:  get mode_select module failed!
```

E nas mensagens de `snd_dac_startup`:

```
new_output_type: single po, ..., system_mode_old: 0, system_work_mode: 0
```

`system_work_mode` fica **0 sempre**. O motivo: os dois módulos procuram um
módulo `mode_select` que **não existe** no aparelho — não está em
`/vendor_dlkm/lib/modules/`, não está em `modules.load` e nunca aparece no
`dmesg` de carga. `dac_core` e `anolog_board_jm21` têm o enum
(`SYSTEM_MODE_MTP`, `SYSTEM_MODE_SOC_BT`, `SYSTEM_MODE_SOC_UAC`,
`SYSTEM_MODE_BT_UPDATE`, `fpga_work_mode`…), mas sem o módulo provedor o valor
nunca chega.

`[FATO]` Portanto: **não é o modo do app que controla os kcontrols** — é um
módulo de kernel que a FiiO não embarca neste firmware. Trocar para BT sink,
AirPlay ou USB DAC não vai expor os controles que faltam; o HAL registra o
mesmo conjunto na inicialização.

`[HYP]` Os quatro controles ausentes dependem desse caminho (`mode_select` →
`system_work_mode`) para serem registrados. Sem o módulo, o HAL não os cria —
o que explica por que os nomes aparecem só em `libfiioaudio.so`, e em nenhum
`.ko`.
