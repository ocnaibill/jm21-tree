# 19 — HAL de áudio (`libfiioaudio.so`): API real e caminho até o kernel

> Fonte: Ghidra 12.1.2 headless sobre `libfiioaudio.so` (335 funções
> decompiladas) + leitura direta do ELF para resolver a tabela de nomes em
> `.data.rel.ro`. Nada aqui é inferência: ou é código, ou é dado extraído.

## 1. Correção importante: a HAL **não** escreve em sysfs

`[FW]` Varrendo `libfiioaudio.so` por `"/sys"`, `"fiio_attr"`, `"/dev"`:
**nenhuma ocorrência**. A HAL fala com o kernel por **kcontrols ALSA**
(`mixer_open` / `mixer_get_ctl_by_name` / `mixer_ctl_set_value`).

Os nós `soc:fiio_attr/*` (docs/18) são o caminho dos **apps e scripts**
(`init.fiio.common.rc`, `fiio_init.sh`, `system_ctrl.sh`), não da HAL.

```
caminho 1 (áudio):   app → AudioFlinger → HAL → kcontrol ALSA → dac_core
caminho 2 (controle): app/init → property → init → sysfs fiio_attr → módulo
```

## 2. A API central: `fiio_adev_set_codec_param(adev, type, v1, v2, v3)`

Um único ponto de entrada, indexado por `type`. Os nomes vêm de uma tabela de
ponteiros em `.data.rel.ro` (`0x1f008`), resolvida pelas relocações
`R_AARCH64_RELATIVE`:

| `type` | Nome do controle | Existe no `dac_core`? |
|--------|------------------|-----------------------|
| 0 | `DAC line Out Volume` | sim |
| 1 | `DAC LR Balance` | sim |
| 2 | `DAC PO Gain` | sim |
| 3 | `DAC Digital Filter Mode` | sim |
| 4 | `DAC Playback Volume` | sim |
| 5 | `Audio POLO Mode` | sim |
| 6 | `Audio Headset Type` | **não** |
| 7 | (especial: aborta delay) | — |
| 8–15 | (nulos) | — |
| 16 | `DAC L MasterTrim` | **não** |
| 17 | `DAC R MasterTrim` | **não** |
| 18 | `DAC THD C2` | sim |
| 19 | (especial: flag de play config) | — |
| 20 | `DAC MUTE` | **não** |
| 21 | `DAC Hifi Boost Mode` | **não** |
| 23 | `NO PROCESS` | — |
| 100 | (especial: broadcast de params) | — |

`[FW]` Os cinco "não" não existem **em lugar nenhum** do firmware: varri
`vendor_dlkm`, `system_dlkm` e o `Image` do kernel — zero ocorrências. A HAL é
**compartilhada entre modelos FiiO** e expõe uma API maior do que o JM21
implementa. Quando o `mixer_get_ctl_by_name` falha, a função loga
`Can't get %s mixer!` e retorna `-22` (`0xffffffda`).

Os kcontrols que o `dac_core` realmente registra `[FW]`:

```
Audio Format            (snd_put_audio_format  -> dac_dai->user_format)
Audio POLO Mode         (snd_dac_put_lopo_select)
DAC Digital Filter Mode (dac_dai->lpf_setting)
DAC line Out Volume
DAC LR Balance          (dac_dai->lrbalance)
DAC Playback Volume     (dac_dai->volume)
DAC PO Gain             (dac_dai->pogain)
DAC THD C2              (dac_dai->thd_c2)
```

## 3. Caminho do volume, ponta a ponta (agora fechado)

```c
// HAL — libfiioaudio.so
fiio_adev_set_master_volume_dac(adev, v)
    mixer = get_device_mixer();
    for (i = 0; i < 22; i++) {                    // 22 tentativas!
        ctl = mixer_get_ctl_by_name(mixer, "DAC Playback Volume");
        if (!ctl) log("Can't get volume control mixer!");
        else if (mixer_ctl_set_value(ctl, 0, v) == 0) return 0;
    }
    return -22;
```

```c
// kernel — dac_core_module.ko
snd_dac_kcontrol_put_volume(kctl, uctl)
    dai->volume = uctl->value;          // dac_dai+0x84
    gain_update = false;
    ops->...                            // callback de atualizacao
```

```c
// placa — anolog_board_jm21.ko
update_volume()
    tab = vol_table_po_gain_{l|m|h}[pogain];
    code = tab[dai->volume] + gain_table[pogain];
    code = min(code, tab[0]);           // 0xFF = mute
    dai->volumeL_DB = dai->volumeR_DB = code;
    dai->ops->set_volume_db(dai, code, code);
```

```c
// chip — cs43198.ko
set_volume_db(dai, l, r)
    update_bits(0x80000, 0x1, gain_spe);   // +1dB_EN no volume maximo
    regmap_l/r: 0x90002 = l, 0x90001 = r  // PCM  (DSD: 0x70000/0x70001)
```

E o lado Java, que já tínhamos: `AudioService` chama
`AudioSystem.setMasterVolumeDac(i)`.

> Ou seja: **um único fio** liga o slider do Android ao registrador do
> CS43198, e ele passa por um kcontrol ALSA — não por sysfs.

### Detalhe de engenharia: por que 22 tentativas?

O mixer pode não existir ainda quando o `AudioService` restaura o volume no
boot (HAL sobe antes do card de som estar pronto). Em vez de falhar, a HAL
insiste 22 vezes **em sequência, sem sleep** — na prática, depende do
escalonamento. É o tipo de laço que explica volume "não aplicado" após boot
rápido.

## 4. Propriedades lidas pela HAL `[FW]`

Extraídas das strings e confirmadas no código decompilado:

| Propriedade | Quem lê | Uso |
|-------------|---------|-----|
| `persist.sys.all.to.dsd` | `get_alltodsd_config` | liga o upsampling PCM→DSD |
| `persist.sys.d2p.enable` | `match_audio_process_mode` | DSD→PCM (D2P) |
| `persist.sys.resample.enable` | `match_audio_process_mode` | habilita reamostragem |
| `persist.sys.pcm2dsd.level` | `fiio_hw_config_update`, `get_current_sample_rate_from_dsdlevel` | nível do modulador |
| `persist.sys.dsd.shaper.coeffs` | `get_alltodsd_shaper_coeffs` | coeficientes do noise shaper |
| `persist.sys.dsd.delta.gain` | `get_alltodsd_delta_gain` | ganho do estágio DSD |
| `persist.sys.pcm.pre.zero.size` / `pcm44p1.pre.zero.size` | HAL | silêncio inicial anti-pop |
| `persist.sys.audio.output.select` | `fiio_player_config_update`, `get_cur_audio_output_config` | saída selecionada |
| `persist.sys.deep.period.size` | HAL | tamanho de período |
| `persist.sys.spdif.delay` | HAL | atraso do SPDIF |
| `persist.music.DSD.format_spdif` | HAL | formato DSD no SPDIF |
| `persist.sys.eq.enable`, `persist.sys.fiio.audio.*.log` | HAL | EQ e logs |
| `fiio.current.play.device`, `fiio.use.kernel.play`, `fiio.uac.active`, `fiio.usb.host.audio`, `fiio.roon.enabled`, `fiio.a2dp.sink.active`, `fiio.harmonic.*`, `fiio.sys.audio.dummy.flag` | HAL | estado/roteamento |

`[FW]` Também existe `persist.sys.fiio.audio.service.enable` — provável chave
para o serviço de processamento (`FiiOAudioProcess`).

## 5. Funções-âncora para a próxima sessão

| Função | Endereço | Por que importa |
|--------|----------|-----------------|
| `FiiOAudioProcess` | — | laço de processamento (resample/DSD/eq) |
| `FiiOAudioConfigParams` | — | entrada de configuração |
| `processAudioConfigParams` | — | aplica propriedades |
| `match_audio_process_mode` | — | decide PCM/DSD/D2P |
| `get_alltodsd_config` | `0x116b18` | parâmetros do ALL TO DSD |
| `init_pcm2dsd` / `get_pcm2dsd_*` | — | modulador e shaper |
| `fiio_adev_set_codec_param` | `0x11cd10` | **API de controle** (tabela do §2) |
| `fiio_adev_set_master_volume_dac` | `0x11cd00` | volume (laço de 22) |

## 6. O que isso muda no dossiê

- `03-stack-de-audio.md` dizia que a HAL conversa com o kernel; agora sabemos
  **por qual canal** (ALSA kcontrol) e **por qual não** (sysfs).
- `18-superficie-sysfs.md` fica correto com uma ressalva: aquela superfície é de
  apps/scripts, não da HAL.
- A existência de 5 controles "fantasma" explica por que certas funções de UI
  podem existir em outros modelos FiiO e não fazerem nada aqui.
