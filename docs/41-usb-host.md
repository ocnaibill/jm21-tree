# 41 — Modo host USB: o JM21 tocando para um DAC externo

> Teste com a **fifine AM8 Pro** (interface UAC, VID/PID `3142:01a8`) ligada na
> porta USB-C do JM21 por adaptador OTG. `adb` por **Wi-Fi** durante o teste
> (o USB fica ocupado).

## 1. O JM21 é host

```
lsusb (no aparelho): Bus 001 Device 002: ID 3142:01a8
dmesg: usb 1-1: Product: fifine AM8 Pro / Manufacturer: MV-SILICON
       usb 1-1: [2] FU [PCM Playback Volume] ch = 2
       usb 1-1: [5] FU [Mic Capture Volume]  ch = 1
       hid-generic ... USB HID v2.01
```

O `snd-usb-audio` (no kernel, não como módulo) parseou as Feature Units. **Não
aparece card ALSA** em `/proc/asound/cards` — o caminho é o USB audio do
Android/QMI (`snd_usb_audio_qmi`) exposto como `usb_headset`.

O `AudioService` mostra `Devices: usb_headset(4000000)` e
`fiio.current.play.device = USB`.

## 2. A pegadinha: permissão por app

Na primeira tentativa **não saiu som**: o Android abriu o diálogo de permissão
para **dois** apps (FiiO Music e **USB Audio Player PRO**, que estava instalado
e se auto-abre no evento de USB). Sem a permissão concedida ao FiiO Music, o app
não abre o dispositivo. Concedendo **só** ao FiiO Music (e negando ao UAPP), o
som saiu.

`[FATO]` A permissão USB do Android é **por aplicativo**; o UAPP compete pelo
mesmo dispositivo.

## 3. Taxas: o limite é do DAC, não do JM21

Log do app:

```
IDevice: setUsbAudioSupportSampleRate: [44100, 48000]
```

Ou seja, o **AM8 anuncia só 44,1 e 48 kHz**. Comportamento por arquivo:

| Arquivo | `originSampleRate` | `configSampleRate` | `isUseUsbOutput` | `open: support` |
|---------|--------------------|--------------------|------------------|-----------------|
| 44,1 k | 44 100 | 44 100 | true | **true** |
| 96 k | 96 000 | **48 000** | true | **false** |
| 192 k | 192 000 | **48 000** | true | **false** |
| 384 k | 384 000 | **48 000** | true | **false** |

`support = false` significa que o app **não abre o dispositivo na taxa nativa**
e reamostra para a maior taxa suportada (48 k). No 44,1 k, a HAL registrou
`srcRate 44100 / PCM 24-bit` e o USB recebeu a taxa nativa.

O app usa o **próprio driver USB** (`wzUsbAudioSetSampleRate ret: 0`), não o
`usb_headset` do Android. MQA por USB é recusado
(`setupMqa: usbAudio unsupport sampleRate`), porque exige 88,2/96 k.

## 4. Conclusões

1. **O JM21 é host UAC** e toca para um DAC externo — caminho validado.
2. **A taxa é negociada com o dispositivo**: com o AM8, teto de 48 k; arquivos
   maiores são reamostrados (não é limitação do JM21).
3. **A permissão USB por app** é obrigatória e o UAPP conflita.
4. Para testar 96/192/384 k (e DSD nativo) no host, é preciso um **DAC que
   anuncie essas taxas** — o AM8 não serve para isso.

## 5. Próximo teste

Um dongle DAC com 96/192 k (ou 384 k) e, se possível, DSD nativo. O que medir:
`setUsbAudioSupportSampleRate` (a lista lida), `configSampleRate` por arquivo e
se `open: support` fica `true` nas taxas altas.

## 6. Segundo teste: Tempotec Sonata BHD (PCM 384 k / DSD256)

Enumeração: `22e1:e208`, "TempoTec HD USB AUDIO", high-speed. O kernel reclamou
de um altset com formato que não suporta (`unsupported format bits
0x100000000`) — é o **DSD nativo** do dongle.

**Taxas lidas pelo app:**

```
IDevice: setUsbAudioSupportSampleRate:
  [44100, 48000, 88200, 96000, 176400, 192000, 352800, 384000]
```

Reprodução PCM — **todas nativas** (`configSampleRate` = taxa do arquivo,
`open: support = true`):

| Arquivo | `configSampleRate` | `support` |
|---------|--------------------|-----------|
| 44,1 k | 44 100 | true |
| 96 k | 96 000 | true |
| 192 k | 192 000 | true |
| 352,8 k | 352 800 | true |
| 384 k | 384 000 | true |

### DSD: DoP funciona, nativo é silêncio

O JM21 se identifica como **DPA** (`persist.sys.fiio.config = FiiODPA`,
`dsd.native = 256`, `pcm.sample = 768000`), então o app usa o **`DPAConfig`**
(`t1.a`), cujo suporte DSD vem da tabela `{64,128,256,512}` × `dsd.native`.

| Modo | Evidência | Resultado |
|------|-----------|-----------|
| **DoP** | `audioDataFormat=49`, `decoderFormat=3`, `configSampleRate=176400`; `UsbAudioTrackOpen==true`, `usb audiotrack open : 3` | **som** (confirmado de ouvido) |
| **Nativo** | `audioDataFormat=254`, `decoderFormat=1`, `configSampleRate=88200`; `AudioTrack ... DSD_32_BIT`, *"Not linear PCM, forcing to Direct Output"*, *"AudioTrack for USB!"* | **silêncio** |

`[FATO]` O caminho nativo entrega `0x1A000002` (DSD_32_BIT) à HAL, que mostra
`srcFormat 3 / 88200`, mas **o áudio não chega ao DAC USB**.

`[HIP]` O HAL/USB audio não implementa o altset DSD do dongle; o DoP funciona
porque vai como PCM 176,4 k pelo stack USB do próprio app.

### A pegadinha do estado de rota

Se o app for **reiniciado (force-stop) logo depois** de um attach USB, ele perde
o evento e cai no ramo nativo (silêncio). Sem reiniciar — deixando o app
receber `USB_DEVICE_ATTACHED` — a rota vira `UsbAudio` e ele usa **DoP**.

`[FATO]` Reproduzido três vezes: com force-stop → 254/1 (silêncio); sem
force-stop → 49/3 (som).

## 7. Conclusões do modo host

1. **PCM no host vai até 384 kHz nativo** (com um DAC que anuncie).
2. **DSD por DoP funciona**; **DSD nativo está quebrado** neste stack (HAL/USB).
3. A **permissão USB é por app** e o UAPP conflita.
4. O app precisa do **evento de attach** para escolher o modo certo — reiniciar
   depois do plugue o joga no caminho nativo (silencioso).

### DSD por DoP: escada completa

| Arquivo | `configSampleRate` | `audioDataFormat` / `decoderFormat` | Resultado |
|---------|--------------------|--------------------------------------|-----------|
| DSD64 (2 822 400) | **176 400** | 49 / 3 | toca (confirmado) |
| DSD128 (5 644 800) | **352 800** | 49 / 3 | toca |
| DSD256 (11 289 600) | — | — | **`Audio open failure : UNSUPPORTED`** |

`[FATO]` O DSD256 é recusado porque o DoP exigiria **705,6 k** (11 289 600/16),
acima dos 384 k do Sonata; o caminho nativo, que aceitaria, é o que está mudo.
Depois da falha, o app **volta para a faixa anterior**.

### Workaround para o bug do DSD nativo

O app tem a opção **"DSD out mode"** na tela de USB audio
(`ExclusiveUsbFragment`), com o aviso: *"Please choose DSD mode according to the
USB DAC, and note that not all DACs support DoP/Native DSD."* Escolher **DoP**
evita o caminho nativo (silencioso) sem depender do truque de não reiniciar o
app.

`[?]` A chave de preferência gravada por esse diálogo não foi recuperada (a
classe `d2` não saiu no JADX), então o ajuste tem de ser feito pela interface.

### ALL TO DSD como amplificador do diagnóstico (não como correção)

O painel tem **"All To DSD"** (off por padrão). Ele **não** conserta o bug de DSD
nativo por USB — são caminhos diferentes:

| | All To DSD | Bug do DSD nativo USB |
|---|---|---|
| onde vive | `persist.sys.all.to.dsd` + `init_pcm2dsd`/shaper na `libfiioaudio.so`, gravado por `all2dsd_ctl_value` (Settings) | `audio.usb.bengal.so` + rota `UsbAudio` (UAC2 no DAC externo) |
| saída | DAC **interno** (cs43198) | DAC **externo** por USB host |
| o que faz | converte **PCM -> DSD** dentro da HAL | transporte DSD nativo |

**Mas ele é um separador de hipóteses excelente:** com "All To DSD" **ligado**,
qualquer FLAC comum passa pelo *pipeline* DSD. Então:

- DAC USB toca normal com o toggle **off** e fica **mudo** com o toggle **on**
  -> o defeito está no **transporte DSD**, não na decodificação de arquivo DSD;
- toca nos dois casos -> o defeito é só do *decode* de arquivo DSD nativo.

É um teste de dois minutos que fecha uma das duas metades do bug. `[?]` Vale
registrar também o reverso (DSD64 nativo com o toggle off continua mudo — já
observado).

Bônus: com o toggle ligado, a captura de pacotes GPR (§docs/48 11.15) mostra a
**variante DSD** dos pacotes, o que documenta o segundo formato do protocolo.

### TESTE 2026-10-27: o transporte USB ACEITA DSD (corrige a leitura anterior)

Feito com o **Sonata** como DAC USB (host) + FT1 no Sonata, e depois FT1 direto
no JM21:

| cenario | resultado |
|---|---|
| PCM comum, **All To DSD OFF**, pelo Sonata | **toca** |
| PCM comum, **All To DSD ON**, pelo Sonata | **toca** |
| `decaud-goldberg-var5-dsd256.dsf` pelo Sonata | **silencio, nao toca de forma alguma** |
| mesmo `.dsf` no DAC interno (FT1 balanceado) | **toca normalmente** |

**O que isso derruba:** a frase "DSD nativo esta quebrado neste stack"
(secoes anteriores) era **larga demais**. Com All To DSD ligado, o mesmo caminho
USB leva DSD e toca — logo o **transporte USB suporta DSD**; o `libfiioaudio`
converte PCM->DSD e o Sonata reproduz.

**O que sobra como causa:** o problema e especifico do **arquivo DSD nativo em
taxa DSD256** (11,2896 MHz) por USB. Hipoteses, em ordem:

1. **Taxa fora do alcance do Sonata**: DoP de DSD256 exigiria 705,6 kHz (acima
   dos 384 kHz ja recusados com `Audio open failure : UNSUPPORTED`); o caminho
   nativo DSD256 (altsetting DSD do UAC2) pode nao estar sendo negociado.
2. **"DSD out mode"** do app (Native vs DoP) — se estiver em DoP, DSD256 nao
   cabe em taxa nenhuma; se estiver em Native, o altsetting nao foi aceito.
3. O DAC interno aceita DSD256 nativamente (por isso toca no FT1 direto), o que
   **nao** diz nada sobre o Sonata.

**Experimento decisivo (barato):** tocar um arquivo **DSD64** (2,8224 MHz) pelo
Sonata em modo **Native**.
- DSD64 Native toca -> "nativo quebrado" e falso: o limite e de **taxa**
  (DSD256), e o diagnostico muda de "bug de transporte" para "limite do DAC".
- DSD64 Native tambem fica mudo -> o nativo so funciona ate certa taxa ou nao
  funciona, e o alvo passa a ser o altsetting/negociacao.

`[?]` Registrado que `persist.sys.all.to.dsd` voltou a `0` e a rota a `SPEAKER`
depois do teste (Sonata removido).
