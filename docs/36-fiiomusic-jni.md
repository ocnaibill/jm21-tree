# 36 — FiiO Music: JNI, DSD/MQA e bibliotecas nativas (issue #2)

> O nome de arquivo pedido na issue era `docs/11-…`, mas `docs/11` já é a
> extração das tabelas de volume. Este documento é o `docs/36`.

## 1. Bibliotecas nativas (arm64-v8a)

| Lib | Tamanho | Papel |
|-----|---------|-------|
| `libhello-jni.so` | 9,2 MB | **player/decoder** — ffmpeg **estático** (avcodec/avformat), derivado de ijkplayer |
| `libijkffmpeg.so` | 10,4 MB | ffmpeg compartilhado |
| `libfiioac-jni.so` | 235 KB | **estado atual do áudio** (`com.other.AC`, TAG `AQMAC`) |
| `libfiioa-jni.so` | 235 KB | helpers de saída (`com.other.A`) — ofuscado |
| `libeqLib.so` | 63 KB | DSP: `gainFilter`, `balanceFilter`, `changeVolume`, **`increaseDSD`**, fades |
| `libfilterAPI.so` | 18 KB | wrapper do **avfilter** do ffmpeg (`avfilter_graph_free`) |
| `libUsbAudio.so` | 141 KB | **UAC host próprio** (não usa o USB audio do Android) |
| `libfiiocd-jni.so` | 126 KB | leitura de CD-DA (`com.fiio.NativeCdControl`) |
| `libsacd.so` | 157 KB | SACD ISO/DSF: `open/read/seek`, **`isDst`** (DST) |
| `liblhdc.so` | 92 KB | codec LHDC (Bluetooth) |
| `libm3u.so` | 955 KB | playlists |

`libfiioa-jni` e `libfiioac-jni` só exportam `JNI_OnLoad` (registro dinâmico por
`RegisterNatives`); as strings estão cifradas — sem Ghidra não se lê mais.

## 2. Grafo app → JNI

| Classe Java | Lib | Métodos nativos |
|-------------|-----|-----------------|
| `com.example.root.checkappmusic.FiioMediaPlayer` | hello-jni | `AudioDecodeInit/Open/ReadWithBuffer/Seek/Close`, `AudioDecodeGetMediaInfo`, **`AudioDecodeGetDffWebInfo`**, `AudioDecodeGetPic` |
| `com.other.AC` | fiioac-jni | `acfunc1..10` |
| `com.other.A` | fiioa-jni | helpers de saída |
| `com.fiio.music.eq.Eq` | eqLib | `gainFilter`, `balanceFilter`, `changeVolume`, **`increaseDSD`**, fades |
| `com.fiio.usbaudio.UsbAudio` | UsbAudio | `UsbAudioTrackOpen/Stop`, `UsbAudioTrackSetSampleRate`, `UsbAudioGetSupportedSampleRate`, `UsbAudioSetVolume/GetVolume`, `UsbAudioGetNativeAlternateSetting`, `CloseUsbAudioRoute`, `SetJniCallback` |
| `com.fiio.NativeCdControl` | fiiocd-jni | `AudioTrackRead/Seek/getSampleRate/getSector` |
| `com.example.root.checkappmusic.SacdPlayer` | sacd | `open/read/seek/isDst/getProbe` |

`AC` é o **canal de estado**: `func3()` = tipo de saída, `func4()` = tipo de
áudio (**2/3 = MQA**, senão PCM), `func5()` = sample rate, `func6()` = bits.
O player usa isso para atualizar a UI (`j0()`).

## 3. DSD: quem decide o quê

O JM21 usa a classe **`t1.i` (XSeriesConfig)** — a escolha é feita em `s1/k.k()`
pelo `FiioDeviceEnum`; o JM21 cai no `else`, que é `t1.i`.

Tabela do ramo DSD (`t1/i.d()`), quando a saída **não** é USB/BT/HWA:

| Arquivo | `configSampleRate` | `audioDataFormat` | `decoderFormat` |
|---------|--------------------|-------------------|-----------------|
| DSD64 (2 822 400) | **88 200** | **7** | **1** |
| DSD128 (5 644 800) | **176 400** | **8** | **1** |
| DSD256 (11 289 600) | **352 800** | **9** | **1** |

**Bate exatamente com o que medimos na HAL** (`srcRate 88200`, `176400`,
`352800`, `mode BYPASS`, `AUDIO_FORMAT_DSD_32_BIT`). `decoderFormat = 1` é o
DSD nativo; `audioDataFormat` 7/8/9 identifica o nível.

Outros ramos:

| Saída | `decoderFormat` | `audioDataFormat` | Taxa |
|-------|-----------------|-------------------|------|
| SPDIF | 1 | 7 | 88 200 fixo |
| USB DoP (`t()`, UAC2) | **3** | **49** | taxa / 16 |
| USB nativo (`u()`, UAC2) | **6** | **51** | taxa / 32 |
| Bluetooth | 2 | 2 | taxa da música |
| HWA | **4** | 2 | 88,2 k / 44,1 k |
| USB (outros) | 2 | 50 | convertida |

`Eq.increaseDSD()` só é chamado quando `isDsd && decoderFormat ∈ {2, 4}` — ou
seja, **nos caminhos convertidos**, não no DSD nativo.

## 4. MQA

- Campos do `PlayerConfig`: `isMqa`, `needSystemNativeMqa`, `isDst`.
- `t1/d.e()` (`setupMqa`) **recusa** MQA em: taxa não suportada, bit depth não
  suportado, Bluetooth, HWA, USB "anti-exclusive" e taxas USB ausentes
  (88,2/96/44,1/48 k).
- O aviso `IConfig: setupMqa: unsupport sampleRate` apareceu no nosso teste de
  352,8 k — é exatamente essa função.
- O framework expõe `CODEC_PARAM_FIIO_MQA = 9`; o app sinaliza o MQA por esse
  parâmetro e a decodificação MQA em si **não** é feita no app: é o DAC/HAL que
  a habilita.

## 5. ALL TO DSD: código morto

O app faz, por reflexão:

```java
AudioManager.class.getMethod("fiioConfigALLTODSD", Boolean.TYPE).invoke(...)
```

`[FATO]` Esse método **não existe** no `framework.jar` deste firmware (nem em
`AudioManager`, nem no `services.jar`; não há a string `fiioConfigALLTODSD` no
dex). A chamada cai em `NoSuchMethodException` e é engolida.

O mecanismo real é o que já tínhamos achado:

```java
SystemProperties.set("persist.sys.all.to.dsd", z ? "1" : "0");
Settings.System.putInt(cr, "all2dsd_ctl_value", z ? 1 : 0);
```

## 6. Propriedades usadas pelo app

| Propriedade | Uso |
|-------------|-----|
| `persist.sys.fiio.config` | marca de dispositivo FiiO (`FiiODPA`) |
| `persist.sys.fiio.config.dsd.native` | modo DSD nativo |
| `persist.sys.fiio.config.pcm.sample` | taxa PCM configurada |
| `persist.sys.dsd2pcm.exist` | existe conversão DSD→PCM (`t1/g`) |
| `persist.sys.eq.exist` | EQ disponível |
| `persist.sys.all.to.dsd` | ALL TO DSD ligado |
| `persist.sys.audio.output.select` | saída (PO/LO/SPDIF) |
| `persist.tape.mode` | Tape Mode |
| `persist.sys.theme` / `persist.sys.locale` | UI |

## 7. Responsabilidades (quem faz o quê)

| Função | App | HAL | DAC/FPGA |
|--------|-----|-----|----------|
| Decodificar FLAC/DSF/DFF/ISO/DST | **sim** (ffmpeg + libsacd) | — | — |
| Reamostrar / converter DSD→PCM | nos modos BT/HWA | — | — |
| Transportar DSD nativo | empacota em 32 bits | `BYPASS` | DAC recebe DSD (pág. 7) |
| DoP / USB nativo | formata | repassa | conforme modo |
| Volume | envia índice | `DAC Playback Volume` + `setMasterVolumeDac` | atenuação no DAC |
| EQ | calcula (`libeqLib`/`avfilter`) | tem `FiiOAudioSetEqParams` (não usado por este app) | — |
| MQA | sinaliza (param 9) | repassa | **decodifica** |

## 8. Respostas diretas à issue

1. **Chamadas JNI mapeadas** (tabela §2). `FiioMediaPlayer` = decodificação;
   `AC` = estado do áudio; `Eq` = DSP; `UsbAudio` = UAC host próprio.
2. **DSD nativo, DoP e ALL TO DSD**: nativo e DoP estão no app (§3); ALL TO DSD
   é propriedade + Settings, com a chamada por reflexão morta (§5). MQA é
   sinalizado pelo app e decodificado pelo DAC.
3. **`libhello-jni.so`**: é ffmpeg estático (ijkplayer), **não** um decoder
   proprietário; o SACD/DST proprietário está em `libsacd.so` (com `isDst`).
4. **Propriedades**: tabela §6.
