# 20 — DSD, DoP, D2P, ALL TO DSD e MQA (HAL)

> Fonte: `libfiioaudio.so` decompilada (Ghidra) + `readelf` para dependências e
> imports. Tudo verificado em código; o que é inferência está marcado.

## 1. Onde a decisão acontece

`match_audio_process_mode(rate, format)` lê cinco propriedades e o dispositivo
de saída corrente e grava um **modo numérico** em
`g_audio_play_config + 0x10` (lido por `get_audio_process_mode`).

Entradas:

| Propriedade | Papel |
|-------------|-------|
| `persist.sys.all.to.dsd` | liga/desliga o PCM→DSD |
| `persist.sys.audio.output.select` | `2` = saída SPDIF |
| `persist.music.DSD.format_spdif` | string; `"D2P"` desliga o AllToDSD no SPDIF |
| `fiio.current.play.device` | `"A2DP"`, `"USB"`, `"SPEAKER"`… |
| `persist.sys.eq.enable` | EQ |
| `persist.sys.resample.enable` | reamostragem |
| `persist.sys.d2p.enable` | DSD→PCM |

`[FW]` As comparações usam constantes de 4 bytes little-endian:
`0x50443241` = `"A2DP"`, `0x425355` = `"USB"`, `0x503244` = `"D2P"`.

### Regras que o código aplica

1. **AllToDSD só vale fora de A2DP e USB**, e não vale em SPDIF quando o
   formato é D2P. Nesses casos o log é explícito:
   *"current play mode is UAC, so don't use Alltodsd"*.
2. Se EQ e reamostragem estão desligados e a taxa é **44,1 / 48 / 88,2 / 96
   kHz**, o modo resultante é o de **passagem direta** (sem processamento).
3. Se o formato já é **DSD** (`0x1a000002`) a decisão muda de ramo — não se
   converte o que já é DSD.
4. Fora dessas taxas, chama `match_resample_rate()`; se ela devolver 0, cai no
   modo de reamostragem, senão no modo "sem EQ".

`[HIP]` Os modos são inteiros 1–8 sem tabela de nomes no binário. Pelos ramos,
a leitura mais consistente é:

| modo | Leitura provável |
|------|------------------|
| 1 | AllToDSD ativo (PCM→DSD) |
| 2 | processamento com EQ |
| 3 | processamento com reamostragem |
| 4 | EQ + reamostragem |
| 5 | passagem direta (44,1/48/88,2/96) |
| 6 | D2P (DSD→PCM) |
| 7 / 8 | caminho SPDIF (7 = com formato DSD, 8 = sem) |

`[?]` A numeração exata só se confirma com log no aparelho
(`logcat -s fiioaudio`), que imprime `audio_process %d`.

## 2. ALL TO DSD (PCM → DSD)

- Chave: `persist.sys.all.to.dsd`.
- Estado do conversor: `g_pcm2dsd_handle`, **1 311 712 bytes** (0x1403E0) —
  `init_pcm2dsd()` só faz `memset` dessa área. É um bloco grande de filtros e
  tabelas, consistente com modulador + noise shaper.
- Parâmetros vêm de propriedades: `persist.sys.pcm2dsd.level`,
  `persist.sys.dsd.shaper.coeffs`, `persist.sys.dsd.delta.gain`
  (`get_pcm2dsd_level`, `get_alltodsd_shaper_coeffs`,
  `get_alltodsd_delta_gain`).
- O nível efetivo é derivado da taxa por `get_current_sample_rate_from_dsdlevel`.
- Quando o modo é AllToDSD, `fiio_hw_config_update` troca o formato
  apresentado para **`0x1a000002`** (`AUDIO_FORMAT_DSD_U16_LE`).

Consequência prática: **ALL TO DSD não é DSD nativo** — é conversão com
modulação e shaping. Ligar isso derruba qualquer pretensão de bit-perfect de
PCM.

## 3. D2P (DSD → PCM) e DoP no SPDIF

- `persist.sys.d2p.enable` + `persist.music.DSD.format_spdif` = `"D2P"`.
- Logs: *"spdif and D2P"*, *"spdif and DOP"*, *"spdif and DOP, but not enable
  Alltodsd"*.
- Ou seja: no SPDIF o aparelho escolhe entre **DoP** (DSD empacotado em PCM) e
  **D2P** (conversão para PCM), conforme o formato configurado.
- `persist.sys.spdif.delay` ajusta o atraso da saída.

## 4. DSD nativo: o que a HAL realmente faz

As primitivas são de **empacotamento**, não de DSP:

```c
dsd8_convert_to_dsd16(buf, len)
    // usa TBL (NEON) com máscara de 16 bytes:
    //   02 00 03 01 06 04 07 05  fa b8 36 54 8c a2 93 40
    // expande 1 bit por amostra em 16 bits

dsd16_convert_32bit(buf, len)
    // reordena bytes em grupos de 8 (swap de posições), DSD16 -> DSD32
```

`[FW]` Isso confirma o que o kernel já sugeria (docs/13): o "DSD nativo" chega
ao DAC como palavras de 16/32 bits por amostra, via I2S. Não há decodificação
nem reamostragem no caminho nativo.

## 5. Reamostragem

- Chave: `persist.sys.resample.enable`.
- `match_resample_rate(rate)` decide se a taxa precisa passar pelo resampler;
  `convert_audio_sample_rate_for_resampler` faz a conversão.
- `persist.sys.deep.period.size` ajusta o período do buffer profundo.
- `[FW]` A 44,1 / 48 / 88,2 / 96 kHz o caminho é direto — não há SRC.

## 6. MQA

`[FW]` `libfiioaudio.so` **depende** de `libfiioaqm.so` (`DT_NEEDED`) e importa:

```
aqm_initialise        aqm_decode           aqm_flush
aqm_getOutput         aqm_getOutputState   aqm_getBitDepth
aqm_getCurrentAudioType                   aqm_getCurrentSampleRate
aqm_getOriginalSampleRate                 aqm_getMaximumEmptyChunkSize
aqm_getMinimumEmptyChunkSize
```

O estado exposto (bit depth, taxa original, tipo de stream, estado da UI) é o
que a interface mostra como "MQA". O kernel só recebe o resultado — a
decodificação é 100% userspace, dentro de `libfiioaqm.so`.

`[?]` Se é MQA completo (renderização) ou apenas "core decode" depende do que o
`aqm_decode` entrega; fecha-se com log no aparelho durante uma faixa MQA.

## 7. O que derruba o bit-perfect (lista objetiva)

| Fator | Efeito |
|-------|--------|
| `persist.sys.eq.enable=1` | EQ no caminho |
| `persist.sys.resample.enable=1` | SRC |
| `persist.sys.all.to.dsd=1` | converte tudo para DSD |
| saída A2DP | reencoda (SBC/AAC/aptX/LDAC/LHDC) |
| saída USB (UAC) | sai do domínio do DAC interno |
| SPDIF com D2P | converte DSD para PCM |
| volume digital < máximo | atenuação no DAC (por design) |

Ou seja: para bit-perfect de PCM local, são necessários **fio, 3,5/4,4 mm, EQ
off, resample off, all-to-dsd off** — e o volume, se possível, em 0 dB.

## 8. Aberto

| Item | Como fechar |
|------|-------------|
| Nomes/valores exatos dos 8 modos | `logcat -s fiioaudio` com cada combinação |
| MQA completo × core | faixa MQA + log |
| Taxa real entregue ao kernel | `hw_params` + `dumpsys media.audio_flinger` |
| Se o FPGA altera a taxa | bitstream / medição |
