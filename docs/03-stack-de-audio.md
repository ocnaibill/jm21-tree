# 03 — Stack de áudio (software)

> O documento mais importante do dossiê. Descreve como o som sai do Android e
> chega nos dois CS43198, e onde a FiiO rompeu o caminho padrão.

## 1. Camadas

```
┌────────────────────────────────────────────────────────────┐
│ FiiOMusic.apk / apps de terceiros                          │
│   libfiioa-jni.so  libfiioac-jni.so  libfiiocd-jni.so      │
│   libeqLib.so  libfilterAPI.so  libUsbAudio.so             │
├────────────────────────────────────────────────────────────┤
│ AudioFlinger (system) → "hifi_playback" / "direct_pcm"     │
├────────────────────────────────────────────────────────────┤
│ HIDL audio HAL 7.0                                         │
│   /vendor/lib64/hw/audio.primary.bengal.so                 │
│   ├─ libfiioaudio.so     (DPA: DSD, EQ, volume, params)    │
│   ├─ libfiioaqm.so       (MQA)                             │
│   ├─ libqc2audio_* / PAL (Qualcomm Platform Audio Layer)   │
│   └─ libtinyalsa.so      (ALSA userspace)                  │
├────────────────────────────────────────────────────────────┤
│ Kernel ALSA                                                │
│   mixer_paths_bengal_*.xml  (controles e rotas)            │
│   fiio_snd_soc_dummy_dai.ko  ← DAI do caminho Android      │
│   dac_core_module.ko        ← orquestra modo/energia/mute  │
│   anolog_board_jm21.ko      ← GPIOs, MCLK, energia         │
│   gw-fpga.ko / fpga_audio_interface.ko                     │
│   cs43198.ko (I2C 0x33 / 0x30)                             │
└────────────────────────────────────────────────────────────┘
```

## 2. A HAL de áudio

`[FW]` Arquivos presentes em `/vendor/lib64/hw/`:

| Arquivo | Tamanho | Nota |
|---------|---------|------|
| `audio.primary.bengal.so` | 513 kB | **HAL primária** (nome real) |
| `audio.usb.bengal.so` | 50 kB | HAL de áudio USB |
| `audio.bluetooth.default.so`, `audio.bluetooth_qti.default.so` | — | A2DP |
| `audio.r_submix.default.so` | 33 kB | remote submix (captura de tela etc.) |
| `android.hardware.audio@7.0-impl.so` | 272 kB | implementação do HIDL 7.0 |
| `android.hardware.audio.effect@7.0-impl.so` | 389 kB | efeitos |

`[FW]` O serviço é HIDL, não AIDL:
`/vendor/etc/init/android.hardware.audio.service_64.rc`. Em Android 13 ambos
existem; este aparelho ficou no HIDL 7.0 (última versão HIDL).

### Símbolos FiiO exportados pela HAL `[FW]`

A FiiO não fez uma HAL separada: **enxertou** funções na HAL da Qualcomm. São
símbolos com linkagem C++ visíveis na tabela do `.so`:

```
FiiOAudioInit(unsigned, unsigned, unsigned, unsigned, unsigned, unsigned, unsigned*)
FiiOAudioDeinit()
FiiOAudioProcess(char*, unsigned, unsigned, unsigned, unsigned, unsigned*, ...)
FiiOAudioGetParams(unsigned*, ...)
FiiOAudioConfigParams(unsigned, unsigned, unsigned, ...)
FiiOAudioGetTrackMode()
FiiOIsUSBDevice()
FiiOIsA2DPDevice()
fiio_adev_set_master_volume_dac(audio_hw_device*, int)
fiio_adev_set_hardware_audio_format(...)
fiio_adev_set_codec_param(audio_hw_device*, unsigned, unsigned, unsigned, unsigned)
fiio_adev_get_codec_param(...)
fiio_adev_set_output_state(audio_hw_device*, unsigned, unsigned)
fiio_adev_get_output_state(...)
fiio_adev_set_eq_param(audio_hw_device*, unsigned, float, float, unsigned)
fiio_adev_set_eq_master_gain(audio_hw_device*, float)
fiio_adev_set_eq_audio_effect(audio_hw_device*, unsigned, unsigned)
StreamOutPrimary::fiiOConfigurePalOutputStream()
```

Leitura: o ponto de injeção é o **PAL** (Platform Audio Layer, camada de
abstração de stream da Qualcomm). Ao configurar o stream de saída, a FiiO troca
o `audio_output_flags`/formato para obter o caminho *direct/hi-fi*. O EQ é
aplicado no `adev` (device), não por app.

`[?]` A assinatura exata e a ordem dos parâmetros só saem com decompilação.

## 3. `libfiioaudio.so` — o cérebro proprietário

135 576 bytes. `[FW]` Superfície observada via strings:

### 3.1 Controles de hardware (ALSA kcontrols)

```
DAC Playback Volume
DAC line Out Volume
DAC Digital Filter Mode
DAC LR Balance
DAC PO Gain
Can't get %s mixer!
Can't get volume control mixer!
Failed to set volume!
```

Ou seja: volume, filtro digital, balanço e ganho de saída são ajustados por
mixer controls — o mesmo caminho que qualquer `tinymix` usaria.

### 3.2 Conversões DSD ↔ PCM

```
dsd_convert_platform          dsd8_convert_to_dsd16
DSDTOPCM                      dsd16_convert_32bit
init_pcm2dsd                  get_pcm2dsd_level
get_pcm2dsd_data              get_pcm2dsd_delta_gain
get_pcm2dsd_shaper_coeffs     init_dsd2pcm_params
get_dsd2pcm_config            get_dsdtopcm_data
get_dsd_write_zero_mark       get_pcm44p1_pre_write_zero_size
get_pcm_pre_write_zero_size   get_current_sample_rate_from_dsdlevel
```

Isto descreve **três** coisas distintas:

1. **DoP/DSD nativo**: `dsd8_convert_to_dsd16`, `dsd16_convert_32bit` —
   empacotamento de DSD em palavras maiores (é assim que DSD nativo é enviado
   por I2S: 1 bit por canal vira 8/16/32 bits por amostra).
2. **DSD→PCM** (`DSDTOPCM`, `dsd2pcm`): decodificação para tocar em modo
   "compatível" (quando a cadeia não aceita DSD nativo).
3. **PCM→DSD** (`init_pcm2dsd`, `noise shaper coeffs`, `delta_gain`): a FiiO
   oferece conversão **para cima** com *noise shaping* — é a função "DSD
   remaster/upsample" da UI.

`get_pcm*_pre_write_zero_size` + `get_dsd_write_zero_mark`: escrita de silêncio
inicial para evitar *pop*/clique na troca de formato. Detalhe de qualidade
relevante e raro.

### 3.3 MQA

`libfiioaqm.so` (177 776 bytes) + módulo MQA dentro de `libfiioaudio.so`:

```
get_mqa_bit_depth   get_mqa_current_rate   get_mqa_original_rate
get_mqa_data        get_mqa_stream_type    get_mqa_ui_state
get_fiio_mqa_process_rate   match_mqa_sample_rate
get_hw_audio_params_is_mqa  is_first_mqa
```

Leitura: renderização MQA (decodificação + *rendering*) no dispositivo, com
estado exposto para a UI (`get_mqa_ui_state`). `[?]` Se é MQA completo ou apenas
"core decode".

### 3.4 Propriedades que a lib consulta/publica `[FW]`

| Propriedade | Uso |
|-------------|-----|
| `fiio.use.kernel.play` | escolhe se a reprodução passa pelo DAI do kernel |
| `fiio.current.play.device` | dispositivo de reprodução corrente |
| `fiioprocess` / `fiio_audio_debug_init` | entrada de processo/serviço |
| `fiioeq` | EQ |
| `fiiomixer`, `g_device_mixer`, `fiiodevice` | handles internos |
| `fiio.harmonic.switch.enable`, `fiio.harmonic.config.value` | ajuste harmônico |
| `fiio.roon.enabled` | integração Roon (RAAT) |
| `fiio.uac.active`, `fiio.usb.host.audio` | modo USB DAC / host |
| `fiio.a2dp.sink.active` | papel A2DP sink |
| `fiio.sys.audio.dummy.flag` | flag do caminho dummy |
| `FiiO Audio Params Change` / `FiiOAudioProcess` | mensagens de log |

## 4. O contrato com o kernel (`dac_core_module.ko`) `[DRV]`

Eventos/ioctls observados nas mensagens do módulo:

| Evento | Significado provável |
|--------|----------------------|
| `PLAYER_STARTUP` | início de reprodução |
| `PLAYER_SHUTDOWN`, `PLAYER_SHUTDOWN_NOW` | fim de reprodução (com variante imediata) |
| `PLAYER_MODE_CHANGE` | troca de modo (Android ↔ Pure Music, ganho etc.) |
| `PLAYER_MUTE`, `PLAYER_SW_MUTE` | mute de hardware × mute de software |
| `PLAYER_CONFIG_PARAMS` | entrega de parâmetros (taxa, formato, bits) |
| `NOTIFY_EVENT_OUTPUT_MODE_CONFIG` | reconfiguração de modo de saída |
| `HEADSET_STATE_CHANGE` | fone inserido/removido |
| `HEADSET_OUTPUT_TYPE_CHANGE` | mudou 3,5 ↔ 4,4 ↔ balanço |
| `HIGH_TEMP_ERROR`, `OVERLOAD_ERROR`, `DC_ERROR` | proteções |

Módulos auxiliares que o `dac_core` procura no boot `[DRV]`:

```
get anolog_board module failed!
get dac_dai module failed!
get headset_jack module failed!
get mode_select module failed!
get volume module failed!
get xmos module failed!     ← receptor USB (XMOS)
get aw22xxx module failed!  ← driver de LEDs
```

Arquitetura: `dac_core` é o **orquestrador**; cada função é um módulo
(`anolog_board`, `dac_dai`, `headset_jack`, `mode_select`, `volume`, `xmos`).
Isso explica o tamanho da pilha FiiO e facilita o RE: dá para analisar por
função em vez de tudo de uma vez.

`[?]` Node de dispositivo usado pela HAL para esses ioctls não apareceu como
`/dev/...` literal nas strings (só `fiioconfig` no bloco). Pode ser `sysfs`,
`/proc` ou nome montado em runtime. Confirmar no aparelho:
`ls -l /dev | grep -i -E "dac|fiio"` e `ls /sys/class | grep -i dac`.

## 5. Política de áudio

Dois arquivos em `/vendor/etc/audio/`:

| Arquivo | Tamanho | Uso |
|---------|---------|-----|
| `audio_policy_configuration.xml` | 36 871 | modo normal (FiiO, estendido) |
| `audio_policy_configuration_gaming.xml` | 30 827 | variante "gaming" |

E existe também o `/vendor/etc/audio_policy_configuration.xml` (16 971) da
Qualcomm — versão base. `[?]` Qual é carregado em qual cenário: o caminho em
`/etc/audio/` sugere troca em runtime (o diretório tem só esses dois arquivos).

### `mixPorts` no modo normal `[FW]`

| mixPort | Flags / formato | Papel |
|---------|-----------------|-------|
| `primary output` | `FAST`, `PRIMARY` | saída padrão |
| `raw` | — | PCM sem mixer |
| `deep_buffer` | — | buffer profundo (economia) |
| `mmap_no_irq_out` | `DIRECT`, `MMAP_NOIRQ` | baixa latência sem IRQ |
| `hifi_playback` | — | **caminho hi-fi da FiiO** |
| `direct_pcm` | `DIRECT` | PCM direto, taxa nativa |
| `compress_passthrough` | offload | FLAC, ALAC, APE, AAC, DTS/HD, WMA/Pro, Vorbis |
| `hifi_input` | — | captura hi-fi |
| `usb_surround_sound`, `usb_accessory output` | — | USB |
| `voice_tx`, `voip_rx` | — | voz (provável legado QTI) |

Formatos de `direct_pcm` `[FW]`: `PCM_16`, `PCM_8_24`, `PCM_24_BIT_PACKED`,
`PCM_32`, **`DSD_16_BIT`**, **`DSD_32_BIT`**.

Taxas declaradas incluem até **705 600 / 768 000 Hz** em perfis específicos, e a
série completa `44 100 … 384 000` na maioria dos portes `[FW]`.

`[PROP]` `persist.sys.fiio.config.pcm.sample=768000` e
`persist.sys.fiio.config.dsd.native=256` confirmam a intenção: **PCM até 768 kHz
e DSD nativo até DSD256**.

### Variante "gaming" `[FW]`

Diff contra o modo normal:

| Só no normal | Só no gaming |
|--------------|--------------|
| `hifi_playback`, `hifi_input` | `haptics output` |
| `usb_surround_sound`, `usb_accessory output` | |
| portas de dispositivo USB (Device/Headset Out/In), `Echo Reference` | |
| `compress-input` | |

Ou seja: o modo gaming **remove o caminho hi-fi e todo o áudio USB**, e adiciona
saída de haptics. `[HIP]` É o modo usado quando o usuário quer latência baixa
em jogos, abrindo mão de DSD/hi-res e de DAC USB.

## 6. `mixer_paths` — quatro variantes `[FW]`

| Arquivo | Tamanho | Controles `DAC` |
|---------|---------|-----------------|
| `mixer_paths_bengal_idp.xml` | 131 970 | 14 |
| `mixer_paths_bengal_qrd.xml` | 126 660 | 14 |
| `mixer_paths_scubaidp.xml` | 129 739 | 16 |
| `mixer_paths_scubaqrd.xml` | 126 599 | 16 |

Não existe `mixer_paths.xml` genérico. `[?]` Qual variante é carregada no JM21 —
depende do id de plataforma/`ro.board.platform` detectado pela HAL. Confirmar no
aparelho: `logcat | grep -i mixer_paths` e `ls /vendor/etc/mixer_paths*.xml`.

Nenhuma das variantes cita `cs43198` literalmente, mas todas contêm controles
`DAC ...` — o casamento é por **nome de controle ALSA**, o que explica por que a
`libfiioaudio.so` busca mixers por string.

## 7. Volume, ganho e balanço

Há **três** domínios de volume distintos `[FW]` `[DRV]`:

1. **Volume Android** (stream) — `audio_policy_volumes.xml`, tabelas por
   `devicePort`/`mixPort`.
2. **Volume do DAC** — `DAC Playback Volume`, `DAC line Out Volume`, em dB
   (`cs43198_set_volume_db`, `volumeL_DB`/`volumeR_DB`, `volume_table`).
3. **Ganho de saída** — `DAC PO Gain` / `pogain` + degraus `GAIN_L/M/H/
   OVER_EAR/SUPER_OVER_EAR`.

Efeitos colaterais observados `[DRV]`: `volume_fade_in` (rampa para evitar
clique), `gain_pwr_update` (troca de ganho força reconfiguração de energia).

`[?]` Faixa em dB e passo da tabela não foram extraídos — alvo de decompilação
de `cs43198.ko`/`dac_core_module.ko`.

## 8. EQ e filtros

| Componente | Onde | Nota |
|------------|------|------|
| `FiiOEq.apk` (6,9 MB) | `/system/app` | UI do equalizador |
| `libeqLib.so` (63 kB) | dentro do APK | DSP do EQ |
| `libfilterAPI.so` (18 kB) | dentro do APK | filtros |
| `fiio_adev_set_eq_param` | HAL | EQ aplicado no device |
| `fiio_adev_set_eq_master_gain` | HAL | ganho mestre do EQ |
| `DAC Digital Filter Mode` | kcontrol | filtro digital do CS43198 |

São **dois** EQs independentes: o de software (libeqLib, com parâmetros da UI) e
o **filtro digital do chip** (`DAC Digital Filter Mode`, os presets do CS43198).
Confundir os dois é erro comum em review.

## 9. USB, Bluetooth e rede

- **USB DAC (UAC)**: `snd-usb-audio-qmi.ko`, `audio.usb.bengal.so`,
  `libUsbAudio.so`, `fiio.uac.active`, `fiio.usb.host.audio` `[DRV]` `[FW]`.
  Ou seja: funciona como DAC USB (device) e como host de DAC externo.
- **Bluetooth**: `liblhdc.so` (codec LHDC), `audio.bluetooth_qti.default.so`,
  `libbluetooth_audio_session_qti*`, `fiio.a2dp.sink.active`.
- **Roon**: `fiio.roon.enabled` — o aparelho pode ser endpoint Roon `[FW]`.
- **AirPlay/Cast**: `FiiOCast.apk` (13,5 MB) `[FW]`.

## 10. Perguntas abertas desta camada

1. `[?]` O caminho `hifi_playback` fala com o dummy DAI ou com o FPGA direto?
2. `[?]` DSD nativo sai por I2S nativo do CS43198 ou é o FPGA que serializa?
3. `[?]` O FPGA reamostra? Se sim, o "bit-perfect" da FiiO é bit-perfect até o
   FPGA e não até o DAC.
4. `[?]` `fiio.use.kernel.play=true` (padrão?) muda o caminho para o DAI do
   kernel e desvia do PAL?
5. `[?]` A divisão Dual DAC é mono-por-chip (cada chip um canal) ou estéreo
   paralelo com soma analógica?
6. `[?]` Qual `mixer_paths_*` é carregado e por qual regra.
7. `[?]` `audio_policy_configuration_gaming.xml` é trocado por qual gatilho.
