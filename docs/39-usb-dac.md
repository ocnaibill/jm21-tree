# 39 — Modo USB DAC: o gadget UAC do JM21

> Sessão com o aparelho em **Ajustes → Modo → USB DAC**, cabo no PC (host Linux,
> ALSA direto, sem PipeWire/Iara no caminho).

## 1. Enumeração

```
lsusb:     2972:0045 FiiO Electronics Technology FiiO JM21
ALSA:      card 5 [JM21] USB-Audio — high speed
```

O `adb` **cai** nesse modo (o configuração USB passa a ser só áudio), como já
estava previsto.

## 2. O que o gadget anuncia

`/proc/asound/card5/stream0`:

| Altset | Formato | Canais | Taxas | Bits |
|--------|---------|--------|-------|------|
| 1 | **S32_LE** | 2 | 32 000, 44 100, 48 000, 88 200, 96 000, 176 400, 192 000, **352 800, 384 000** | 32 |
| 2 | **DSD_U32_BE** | 2 | as mesmas | 32 |

`DSD raw: DOP=0, bitrev=0` — ou seja, o gadget anuncia **DSD nativo** (não DoP).

`[FATO]` O JM21, como DAC USB, aceita **352,8 k e 384 k em PCM** e **DSD nativo
até 384 k** (o que corresponde a DSD256).

## 3. Teste de reprodução (host → JM21)

Tons de 1 kHz a −20 dBFS, direto no `hw:5,0` (sem resample do PipeWire):

```
aplay -D hw:5,0 t352.wav   → 352 800 Hz, aceito
aplay -D hw:5,0 t384.wav   → 384 000 Hz, aceito
```

Durante o 384 k, `/proc/asound/card5/pcm0p/sub0/hw_params`:

```
format: S32_LE   rate: 384000 (384000/1)   channels: 2
```

`[FATO]` O caminho UAC funciona até 384 kHz de verdade, não só no anúncio.

## 4. DSD nativo no USB

Converti o começo do `decaud-goldberg-aria-dsd64.dsf` para `DSD_U32_BE`:
bytes do DSF (LSB-first) **invertidos bit a bit** e agrupados em palavras de
32 bits big-endian, canais intercalados. Reproduzido com:

```
aplay -D hw:5,0 -t raw -f DSD_U32_BE -r 88200 -c 2 dsd64_u32be.raw
```

Aceito sem erro, ~4,6 s. `[?]` Falta a confirmação auditiva (se soou a ária, e
não ruído) — o teste foi feito com o fone no ouvido do usuário.

## 5. Controles expostos

`amixer -c 5 contents` mostra só `Internal Clock Validity` e
`Playback Channel Map` — **não há Feature Unit de volume/mute**. O volume
continua sendo o do aparelho (DAC), não o do host.

## 6. A discrepância do `uac_kernel_enabled`

A flag `config_fiio_uac_kernel_enabled` está **`false`** (docs/33 §4), mas o
gadget UAC funciona. Portanto:

`[HYP]` A flag não descreve "existe gadget UAC". Ela deve controlar outra coisa
— provavelmente se o caminho de áudio do UAC é tratado pelo driver do SoC
(`snd_usb_audio_qmi`, que existe no `lsmod`) ou por um serviço de usuário. O
gadget em si (`f_uac2`/configfs) está ativo de qualquer forma.

## 7. Iara / PipeWire

O serviço **Iara** (roteador PipeWire com sinks virtuais `iara.ch.*` em 48 kHz)
não interferiu: os testes usaram `hw:5,0` direto, que ignora o grafo. Pelo
PipeWire o JM21 apareceria como sink de 48 kHz e **reamostraria** tudo — o que
mascararia justamente as taxas altas.

## 8. Saída do modo

`ModeChooseService.resetUsbDac()` devolve `sys.usb.config = mtp,adb` em build
userdebug (docs/37 §3) — o adb volta ao sair do modo. A saída é feita na tela
do aparelho (Ajustes → Modo → Android).
