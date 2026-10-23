# 14 — Arquitetura do stack FiiO no kernel (e cruzamento com pesquisa externa)

> Fonte primária: Ghidra sobre `fiio_primary_modules.ko` (50 funções),
> `fiio_underlay_modules.ko` e BTF de todos os módulos.
> Fonte secundária: pesquisa externa trazida pelo usuário (marcada `[EXT]`,
> não verificada por nós).

## 1. `fiio_primary_modules.ko` é um SDK, não um driver

O módulo de 1,4 MB não tem driver de hardware: é a **biblioteca de base** que
todos os outros módulos usam. Funções exportadas (nomes reais, preservados):

| Grupo | Funções |
|-------|---------|
| Registro de observadores | `fiio_register_client(idx, nb)`, `fiio_unregister_client` |
| Disparo de eventos | `fiio_notifier_call_chain(idx, val, v)` |
| Barramento de dados nomeado | `fiio_device_register`, `fiio_device_unregister`, `fiio_device_get_by_name`, `fiio_device_get_data_by_name` |
| Hub de atributos sysfs | `fiio_device_attribute_register`, `fiio_device_attribute_unregister` |
| I2C | `fiio_i2c_transfer`, `fiio_i2c_master_send/recv`, `fiio_i2c_smbus_*`, contador de falhas |
| Regmap | `fiio_regmap_read/write/update_bits`, `fiio_regmap_raw_*`, `fiio_regmap_field_*` |
| DAC duplo | `dac_dual_regmap_write`, `dac_dual_regmap_multi_reg_write`, `dac_dual_regmap_update_bits`, `dac_dual_client_write` |
| GPIO | `dac_set_gpio_value`, `dac_set_gpio_value_cansleep`, `dac_get_gpio_value` |
| Reporte | `report_playing_info(dev, format, sample_rate)` |
| Diversos | `atoi`, `htoi`, `fiio_filp_open`, helpers de touchscreen/LCD |

Ou seja: os módulos FiiO **não se conhecem diretamente**. Tudo passa por:
(i) cadeias de notificação por índice, (ii) um registro global por nome
(`"dac_dai module"`, `"headset_jack module"`, `"anolog_board module"`),
(iii) atributos sysfs registrados no hub, (iv) helpers de I2C/regmap.

## 2. As 19 cadeias de notificação

`enum fiio_notifier_type` (BTF), limite validado em runtime
(`index < notifier_gpio_key|notifier_dac`):

```c
notifier_headset=0   notifier_dac=1      notifier_light=2
notifier_player=3    notifier_charger=4  notifier_sw_hold=5
notifier_system_status=6   notifier_monitor=7   notifier_user_config=8
notifier_output_mode=9     notifier_fpga=10     notifier_misc_config=11
notifier_vbus_detection_qti=12   notifier_vbus_detection_fiio=13
notifier_pump_irq=14  notifier_dmode_irq=15  notifier_usb_otg=16
notifier_uart=17      notifier_gpio_key=18
```

Cada índice é um `blocking_notifier_head` independente. Achados de quem usa o
quê (evidência direta):

| Índice | Quem dispara / consome | Onde vimos |
|--------|------------------------|------------|
| 1 = `notifier_dac` | `snd_dac_hw_params` **dispara**; `player_notifier_cb` consome | `dac_core_module` |
| 3 = `notifier_player` | consumido em `player_notifier_cb` (eventos 0–8) | `dac_core_module` |
| 0 = `notifier_headset` | `headset_notifier_cb` | `dac_core_module` |
| 7 = `notifier_monitor` | `monitor_notifier_cb` | `dac_core_module` |
| 8 = `notifier_user_config` | `fiio_user_config_notify_data` | `fiio_headset_jack` |
| 9 = `notifier_output_mode` | `notify_output_mode_event_notifier_cb` | `dac_core_module` |
| 10 = `notifier_fpga` | `fiio_control_fpga_ctrl_notify_data` | `gw-fpga`, `fpga_audio_interface` |

`[?]` Quem **origina** os eventos 0–8 do `notifier_player` (o que a HAL escreve
para chegar lá) — ver §4.

## 3. O hub de atributos (`soc:fiio_attr`)

`fiio_attr_probe` percorre a lista global `g_fiio_attrs_list` e faz
`device_create_file` para **cada** `device_attribute` registrada por qualquer
módulo:

```c
for (nó = g_fiio_attrs_list; nó != &g_fiio_attrs_list; nó = nó->next)
    for (i = 0; i < nó->count; i++)
        device_create_file(&pdev->dev, &nó->attrs[i]);   // 0x20 bytes por attr
```

Consequência prática: o caminho
`/sys/devices/platform/soc/soc:fiio_attr/<nome>` é **extensível** — cada módulo
adiciona seus atributos ali. É por aí que o userspace (HAL, apps) fala com o
kernel, e não por `/dev`. Em caso de falha, o probe remove o que já criou.

## 4. Caminho completo, com o que falta

### 4.1 Quem dispara cada cadeia (agora com evidência)

Varrendo todas as chamadas de `fiio_notifier_call_chain` no código decompilado:

| Chamador | Índice | Contexto |
|----------|--------|----------|
| `snd_dac_startup` | **1 (dac)** | início de stream |
| `snd_dac_hw_params` | **1** | configuração de formato/taxa |
| `snd_dac_shutdown_time` | **1** | desligamento temporizado |
| `snd_dac_put_lopo_select` | **1** | troca de modo LO/PO |
| `snd_dac_mute`, `snd_dac_sw_mute` | **3 (player)** | mute |
| `snd_dac_startup_gpl`, `snd_dac_shutdown_gpl`, `snd_dac_hw_params_gpl`, `snd_dac_shutdown_now_gpl` | **3** | wrappers exportados |

O padrão é de **dois estágios**:

```
API exportada (snd_dac_*_gpl)  --chain 3 (player)-->  player_notifier_cb
                                                            |
                                                            v
                                         snd_dac_* (baixo nível) --chain 1 (dac)--> consumidores
```

`snd_dac_startup_gpl()` é literalmente `payload zerado` + `fiio_notifier_call_chain(3, 0, &p)`
— ou seja, o evento 0 do `player_notifier_cb`. O callback então chama
`snd_dac_startup()`, que avisa a cadeia 1.

### 4.2 A ponta que falta

O `dac_core` exporta **quatro** símbolos GPL:

```
snd_dac_startup_gpl  snd_dac_shutdown_gpl
snd_dac_hw_params_gpl  snd_dac_shutdown_now_gpl
```

`[FW]` Nenhum módulo de `vendor_dlkm` importa esses símbolos (varredura de
`UND` em todos os 100+ `.ko`, e de strings). Conclusão provável: quem chama é
**código embutido no kernel** (a machine driver `bengal` que a FiiO patcheou),
invisível nas strings porque o kallsyms é comprimido. `[?]` Confirmar com
`/proc/kallsyms` (root) no aparelho ou descomprimindo o kallsyms do `Image`.

## 5. Cruzamento com a pesquisa externa

### 5.1 O que a pesquisa acrescenta e nós não tínhamos

| Informação `[EXT]` | Status |
|--------------------|--------|
| FPGA é **Gowin GW1NZ-1** (review) | compatível com `gowin,fpga_i2c` + bitstreams de 30–34 kB `[DT]`; part number é citação de review, **não confirmada por nós** |
| Topologia: FPGA central → 1 DAC por saída → 1 SGM8262 por DAC; SE usa um amp, BAL usa os dois | hipótese de review; ver §5.3 |
| Driver upstream do CS43198 é `sound/soc/codecs/cs43130.c` (não existe `cs43198.c`) | **correto e útil**: é a referência de register map/regmap |
| `regmap` do cs43130: `reg_bits=24, pad_bits=8, val_bits=8` | explica os endereços de 24 bits (`0x090000`) |
| Bits de `PCM_FILT_OPT`: 7 = Fast/Slow, 6 = Phase Comp, 5 = NOS, 1 = High-pass, 0 = De-emphasis | **confere com o datasheet**; corrige nossa tabela (ver §5.2) |
| TLV de volume `-12750, 50, 1` (0 a −127,5 dB, 0,5 dB/passo, mute) | **confere** com o datasheet DS1156F2 |
| 0x99 em `DXD1` libera registradores de teste | **confirmado**: `0x10010` é o registrador de "pop-free settings" (datasheet §6.5) |
| `PWDN_CTL = 0x020000` | **confirmado** ("Power Down Control 0x20000") |
| SM6225 = khaje, herda DTS de bengal; machine driver `bengal.c` (`bengal-asoc-snd`) | coerente com nosso `bengal_515` + `audio.primary.bengal.so` |

### 5.2 Correções que ela provoca na nossa documentação

**Filtros (`PCM_FILT_OPT`, 0x90000)** — a leitura por bits é melhor que a nossa
"base 2":

| `lpf_setting` | Valor | Bits | Leitura |
|---|---|---|---|
| 0 | `0x02` | bit 1 | high-pass ligado |
| 1 | `0x82` | bit 7 + 1 | slow roll-off + high-pass |
| 2 | `0x42` | bit 6 + 1 | phase comp / low-latency + high-pass |
| 3 | `0xC2` | 7 + 6 + 1 | slow + phase comp + high-pass |
| 4 | `0x03` | 1 + 0 | high-pass + de-emphasis (44,1 kHz) |
| 5 | `0x22` | bit 5 + 1 | **NOS** + high-pass |

**`0x20000` (`PWDN_CTL`)** — o init escreve `0xFE` (quase tudo em power-down) e
depois **limpa** bits para ligar o necessário: `& 0xBF` (bit 6) e `& 0xEF`
(bit 4 = ASP). O datasheet lista "power down amplifier", "power down ASP",
"PDN_CLKOUT", "power on appropriate interface" — encaixa exatamente.

**`0x10010`** — é o registrador de *pop-free power-up/down settings*, destravado
com `0x99` e travado com `0x00`. Nossa função `cs43198_set_dre` usa esse mesmo
padrão: **o DRE é configurado por registradores de teste (bloco 0xC)**, não por
um bit documentado de DRE.

### 5.3 Onde a pesquisa conflita com a nossa evidência

- Ela supõe **um DAC por saída** (SE e BAL) e ganho chaveado na realimentação
  dos SGM8262. Nosso disassembly mostra `channel_mode = SPECIAL_MODE_2`: **os
  dois chips recebem o mesmo estéreo** (reg 0x90002 = L, 0x90001 = R, escritos
  nos dois regmaps). Isso é compatível com "cada DAC alimenta um amp", mas
  incompatível com "cada DAC toca um canal".
- O SGM8262 é um op-amp **sem pinos de controle** — não há como chavear ganho
  nele. O ganho deve vir de (a) `OUT_FS[1:0]`/`HV_EN`/`+1dB_EN` do CS43198, (b)
  rede resistiva chaveada por GPIO, ou (c) atenuação digital (as 5 tabelas).
  `[?]` A hipótese mais forte agora é **(a) + (c)**, porque o driver escreve
  full-scale e a curva digital muda por modo.
- Ela cita FW1.0.4 como pacote público; nós temos o **1.1.1** completo e
  validado por AVB.

## 6. O que fazer com isso

1. Decomilar `fiio_config.ko` e `fiio_wakeup.ko` (pequenos) para achar o
   `store` que origina os eventos — é a última peça do caminho HAL→kernel.
2. Confirmar `OUT_FS`/`HV_EN` nos bits de `0x40000` (bloco analógico) lendo
   `cs43198_config_dac` com o mapa do datasheet.
3. Se aparecer o esquemático (pedido de fonte GPL à FiiO), resolver a topologia
   SE/BAL de uma vez.
