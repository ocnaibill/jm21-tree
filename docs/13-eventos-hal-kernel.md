# 13 — O elo HAL ↔ kernel: notifier chain (não ioctl)

> Correção importante: os nomes `PLAYER_STARTUP`, `PLAYER_SHUTDOWN`,
> `NOTIFY_EVENT_OUTPUT_MODE_CONFIG` etc. **não são ioctls**. São eventos de uma
> *notifier chain* interna do kernel FiiO, consumidos por `player_notifier_cb`
> em `dac_core_module.ko`. A HAL/libfiioaudio chega até aqui por kcontrols e
> sysfs, e o disparo da cadeia é feito por um dos módulos FiiO.

## 1. A cadeia

```c
fiio_notifier_call_chain(1, 0, &notify_data);   // visto em snd_dac_hw_params
```

`player_notifier_cb(self, event, data)` recebe `data` como um ponteiro para
struct cujo **primeiro campo é o código do evento** (`*(uint*)data`, 0–8).
Layout observado nos acessos:

| Offset | Campo | Uso |
|--------|-------|-----|
| `+0x00` | `event` (u32) | 0–8, seleciona o case |
| `+0x04` | `sample_rate` | copiado para `dac_dai->sample_rate` |
| `+0x08` | `format` | copiado para `dac_dai->format` |
| `+0x0c` | `bits` | copiado para `dac_dai->bits` |
| `+0x14` | flag de shutdown | se != 0, desliga |
| `+0x18` | `system_mode` | transições de modo (5/6/8/9) |
| `+0x20` | flag de mute | `== 1` → mute |

## 2. Os 9 eventos `[FW]`

| `data[0]` | Nome provável | O que o callback faz |
|-----------|---------------|----------------------|
| 0 | `PLAYER_STARTUP` | chama `snd_dac_startup()`; marca "iniciado" |
| 1 | `PLAYER_CONFIG_PARAMS` | cancela unmutes pendentes; se não iniciado → startup, senão cancela poweroff; copia rate/format/bits; chama `snd_dac_hw_params()`; desmuta (`ops->set_mute(0)`) |
| 2 | `PLAYER_SHUTDOWN` | se a flag estiver setada: marca parado, mute, `snd_dac_shutdown_extern(..., 0x30)` |
| 3 | `PLAYER_MODE_CHANGE` | máquina de estados de `system_mode` (trata 5↔6, 7↔8, 9) e zera o modo |
| 4 | `PLAYER_MUTE` | `snd_dac_dai_mute(1)` |
| 5 | — | (não tratado) |
| 6 | — | usado como valor de modo no case 3 |
| 7 | `PLAYER_SW_MUTE` | `ops->set_mute(dai, data[0x20] == 1)` |
| 8 | `PLAYER_SHUTDOWN_NOW` | mute + `snd_dac_shutdown_time(dac, 3000)` → **desliga em 3 s** |

Leitura: o desligamento tem três sabores — imediato (`8`), externo (`2`, usado
quando o FPGA/rota muda) e por tempo (`8` com 3 s de carência). É o que explica
os "pops" que a FiiO corrigiu na 1.1.0: existe uma janela de 3 s em que o DAC
pode ser religado sem corte.

## 3. `snd_dac_hw_params` — como o formato chega ao chip

```c
if (user_format == 0) {              // HAL nao fixou formato
    format = ffs(mask_de_formatos);  // primeiro formato do mask ALSA
    bits   = snd_pcm_format_width(format);
}
is_dsd = (format & MASK_DSD) ...     // bits 49 e 50 de snd_pcm_format_t

if (soc_i2s_use_one_line == 1)       // modo I2S de uma linha
    sample_rate *= 2;

anolog_board->hw_params();
is_local_playing = (system_work_mode == SYSTEM_MODE_MTP) && !is_dsd;
fiio_notifier_call_chain(1, 0, &notify);   // avisa os outros modulos
anolog_board->update_volume();             // reaplica volume com gain_update=1
```

Dois achados que valem:

1. **`soc_i2s_use_one_line`** dobra a taxa: quando o I2S usa uma única linha de
   dados, o clock precisa ser 2×. É um parâmetro de placa que muda a conta de
   MCLK/BCLK — vale procurar no DT e nos `.ko` da placa.
2. **`is_local_playing` é só `MTP && !DSD`**: reprodução "local" é o caminho
   Android normal; DSD nunca conta como local (vai por outro caminho, coerente
   com `PLAYER_MODE_CHANGE`).

## 4. Formatos DSD no kernel

A detecção usa bits **49 e 50** de `snd_pcm_format_t`
(`1L << fmt & 0x6000000000000`), fora da faixa que o ALSA upstream usa. Ou seja:
a FiiO adicionou formatos DSD próprios na enumeração, casando com
`AUDIO_FORMAT_DSD_16_BIT`/`DSD_32_BIT` da política de áudio. `[?]` Os nomes
exatos dependem de um header FiiO que não está no firmware público.

## 5. O que a HAL escreve direto

`snd_put_audio_format` é um kcontrol que grava **`dac_dai->user_format`**
(offset `0x74`). É o `fiio_adev_set_hardware_audio_format` da HAL chegando ao
kernel — e o que força o formato quando o app pede algo específico.

Fluxo completo, do mais alto ao mais baixo:

```
App -> AudioFlinger -> HAL (audio.primary.bengal.so)
      ├─ kcontrol "hardware audio format"  -> dac_dai->user_format
      ├─ kcontrol "DAC Playback Volume"    -> dac_dai->volume  -> update_volume()
      ├─ kcontrol "DAC PO Gain"            -> dac_dai->pogain   (gain_update/pwr)
      ├─ kcontrol "DAC Digital Filter Mode"-> dac_dai->lpf_setting
      └─ sysfs soc:fiio_attr/...           -> fiio_attr (estado/config)
                                     |
                                     v
        fiio_notifier_call_chain -> player_notifier_cb (eventos 0..8)
                                     |
                                     v
        dac_core -> anolog_board -> cs43198 (I2C) / FPGA (SPI)
```

## 6. Aberto

| Pergunta | Como fechar |
|----------|-------------|
| Quem chama `fiio_notifier_call_chain` com cada evento? | decompilar `fiio_primary_modules.ko` |
| Nomes reais dos formatos DSD 49/50 | procurar header/enum no `libfiioaudio.so` |
| `soc_i2s_use_one_line` está ligado no JM21? | DT + strings do módulo da placa |
| Conteúdo exato do struct de notificação | cruzar com BTF de `fiio_primary_modules.ko` |
