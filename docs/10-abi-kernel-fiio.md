# 10 — ABI interna dos módulos FiiO (via BTF)

> Descoberta desta fase: todos os módulos FiiO carregam `.BTF` e mantêm os
> **nomes de função e struct**. Isso permite recuperar o contrato entre os
> módulos sem decompilar nada — e sem Ghidra.

## 1. Método

```bash
readelf -SW analysis/fw-1.1.1/vendor_dlkm/cs43198.ko | grep BTF
#   [44] .BTF   PROGBITS   ...  000b4f

pahole analysis/fw-1.1.1/vendor_dlkm/cs43198.ko          # lista structs/enums
pahole -C cs43198_priv .../cs43198.ko                   # uma struct
pahole -C dac_event_type .../dac_core_module.ko          # enum
readelf -sW .../cs43198.ko | awk '$4=="FUNC"{print $8}'  # funções
```

`bpftool btf dump file ...` falha nesses `.ko` (`Invalid argument`) — usar
`pahole` (presente no host, sem root). `CONFIG_DEBUG_INFO_BTF` está ligado na
árvore, por isso o BTF existe mesmo sem `.BTF.ext` (não há line info).

Funções com nome preservado em `cs43198.ko` (só removendo os `.cfi_jt`):

```
cs43198_i2c_probe          cs43198_i2c_remove        cs43198_config_dac
cs43198_set_sample_rate    cs43198_set_volume_db     cs43198_set_dre
cs43198_set_lpf            cs43198_set_mono_mode     cs43198_set_thd_c2
cs43198_sw_mute            cs43198_reg_read
cs43198_readable_register  cs43198_volatile_register cs43198_precious_register
```

Notas: `set_mono_mode` **existe** (responde parcialmente Q6), `set_thd_c2` casa
com a propriedade `persist.sys.thd.c2.way=soc`, e `set_dre` com o "DAC DRE" do
changelog.

## 2. O objeto central: `snd_dac_dai`

Compartilhado por todos os módulos FiiO (definido em `dac_dai.h`).

```c
struct snd_dac_dai {
    const char *name;
    struct device *dev;
    bool on;
    const struct snd_dac_dai_ops *ops;

    struct regmap *regmap_l, *regmap_r, *regmap_3, *regmap_4;
    struct regmap *regmap_ak4191;
    struct i2c_client *client_l, *client_r, *client_3, *client_4;
    struct i2c_client *client_ak4191;

    snd_pcm_format_t format, user_format;
    bool is_dsd;
    unsigned int sample_rate, bits;
    int volume, volumeL_DB, volumeR_DB;
    int lo_vol_adjustable;
    const int *volume_table;
    int lpf_setting, lrbalance;
    bool gain_update, gain_pwr_update;
    ...
};
```

Leituras:

- **Até 5 conversores**: L, R, "3", "4" e **AK4191** (modulador AKM usado com
  AK4499). Ou seja, a pilha FiiO é **compartilhada entre modelos** — o JM21 usa
  `regmap_l`/`regmap_r` (os dois CS43198).
- `format` × `user_format` e `is_dsd` confirmam que o driver negocia formato de
  entrada e formato efetivo.
- `volume_table` é **ponteiro** (tabela estática no `.rodata`) — alvo fácil de
  extrair depois.
- `lo_vol_adjustable` = ajuste de volume de *line out*.

## 3. A vtable: `snd_dac_dai_ops`

```c
struct snd_dac_dai_ops {
    void (*set_thd_c2)(struct snd_dac_dai *);
    void (*set_dac_sample_rate)(struct snd_dac_dai *);
    void (*read_reg_all)(struct snd_dac_dai *);
    void (*config_dac)(struct snd_dac_dai *);
    void (*set_performance_mode)(struct snd_dac_dai *, enum system_mode);
    void (*sw_mute)(struct snd_dac_dai *, int);
    void (*set_volume_db)(struct snd_dac_dai *, unsigned, unsigned);
    void (*volume_fade_in)(struct snd_dac_dai *);
    void (*set_lpf)(struct snd_dac_dai *);
    void (*switch_dac)(struct snd_dac_dai *);
    void (*set_dre)(struct snd_dac_dai *);
    int  (*dac_iic_test)(void);
};
```

Essa é a interface **completa** que qualquer driver de DAC FiiO deve implementar.
`cs43198.ko` implementa os 12 (com `dac_iic_test` para bancada).

## 4. Contrato entre módulos (`*_public_data`)

O `dac_core_module.ko` faz `get_*_module()` em cada módulo e recebe um ponteiro
para uma dessas structs — é a ABI interna:

```c
struct dac_public_data {
    bool power_state, playing_state, mute_state;
    void (*dac_startup)(void);
    void (*dac_shutdown)(bool, int);
    void (*dac_hw_params)(int, int, int, int);   // rate, format, bits, mode?
    void (*dac_mute)(bool);
    void (*dac_sw_mute)(bool);
    void (*dac_shutdown_now)(void);
};

struct volume_public_data {
    int on, volumeL_DB, volumeR_DB;
    void (*init)(void);
    void (*set_volume_db)(struct volume_public_data *, unsigned, unsigned);
    int  (*nju_iic_test)(void);     // chip NJU (controle de volume) em outros modelos
};

struct mode_select_public_data {
    int  (*get_current_player_mode)(void);
    int  (*get_current_xmos_mode)(void);
    void (*usb_path_ctrl)(enum sel_usb_path);
};

struct headset_jack_public_data {
    bool allow_dc_det, allow_overload_det;
    bool hs35_det_gpio_disable;
    bool allow_thx_therm_det;
};

struct xmos_public_data {          // receptor USB XMOS (outros modelos)
    void (*usb_path_enable)(bool);   void (*power_ctrl)(bool);
    void (*power_set)(bool);         void (*read_version)(void);
    bool (*power_on_state)(void);    void (*set_startup)(bool);
    void (*reset_chip)(bool);        void (*reset_flag)(void);
    void (*reset_power)(bool);       void (*set_mode)(int);
    bool (*is_usb_plug)(void);       void (*set_usb_plug)(bool);
    void (*set_ios_mode)(bool);      void (*read_uart)(void);
};
```

Isso fecha o desenho: **`dac_core` orquestra; cada módulo expõe uma struct de
funções + estado**. Os ioctls que vimos como strings são os *eventos* que
alimentam essa máquina.

## 5. Enums (as constantes que faltavam)

```c
enum dac_event_type {           // bitmask de notificação
    LOPO_MODE_SETTING_CHANGE = 1,
    DC_DETECE_CHANGE         = 2,   // (sic, typo no fonte original)
    DAC_STARTUP_EVENT        = 4,
    DAC_SHUTDOWN_EVENT       = 8,
    DAC_MUTE_EVENT           = 16,
    DAC_LOCAL_PLAY_EVENT     = 32,
};

enum system_mode {
    SYSTEM_MODE_MTP = 0, SYSTEM_MODE_XMOS = 1, SYSTEM_MODE_BT = 2,
    SYSTEM_MODE_BT_UPDATE = 3, SYSTEM_MODE_SPDIF_RX_BYPASS = 4,
    SYSTEM_MODE_SOC_UAC = 5, SYSTEM_MODE_SOC_UAC_EXIT = 6,
    SYSTEM_MODE_SOC_BT = 7, SYSTEM_MODE_SOC_BT_EXIT = 8,
    SYSTEM_MODE_BT_EXIT = 9, SYSTEM_MODE_HDMI_IN = 10,
    SYSTEM_MODE_HDMI_TX_ARC = 11,
};

enum sel_usb_path {
    USB_PATH_MTP = 0, USB_PATH_CHARGER = 1,
    USB_PATH_XMOS = 2, USB_PATH_BT_UPDATE = 3,
};
```

`SYSTEM_MODE_SPDIF_RX_BYPASS` e `SOC_UAC` aparecem nas mensagens do `dac_core`
("can't mute for spdif rx bypass mode") — coerente.

## 6. `cs43198_priv` — estado do chip

```c
struct cs43198_priv {
    struct snd_dac_dai *dac_dai;
    struct mutex clk_mutex;
    int clk_req;
    bool pll_bypass;
    unsigned int mclk;      // clock atual
    unsigned int mclk_int;  // clock interno
};
```

`pll_bypass` é importante: o CS43198 pode operar com PLL a partir do MCLK ou em
bypass. `[?]` Qual é usado no JM21 — deve depender da taxa.

## 7. `anolog_board_priv` — a placa

```c
struct anolog_board_priv {
    struct device *dev;
    int dac_vol_db;
    int dc_det_value;
    unsigned int gpio_ctrl[7];       // <- exatamente os 7 GPIOs do DT
    struct anolog_board_public_data *anolog_board_public;
    struct snd_dac_dai *dac_dai;
    struct fpga_public_data *fpga_module;
    struct mode_select_public_data *mode_select_module;
    struct headset_jack_public_data *headset_jack_module;
};
```

`gpio_ctrl[7]` fecha com `dac_rst`, `out_sel`, `ang_pwr`, `dac_pwr`, `amp_pwr`,
`amp2_pwr`, `sw_en` — os 7 do DT, na mesma ordem em que o driver os declara.

## 8. `headset_data` — detecção e proteção

39 campos, todos com nome. Os que importam:

| Campo | Papel |
|-------|-------|
| `hs35_det_gpio` / `bal44_det_gpio` / `po635_det_gpio` | GPIOs de detecção |
| `dc_det1`/`dc_det2` (iio_channel) | ADC de DC offset |
| `bal25_det_adc`, `hs35_det_adc`, `thx_therm_det` | ADC por caminho |
| `hs_det_delay_ms` | debounce (150 ms no DT) |
| `hs35/bal25/bal44/po635_det_threshold` | limiares por tipo de plug |
| `dc_det1/2_threshold`, `po_dc_det_*`, `bal_dc_det_*` | limiares de DC |
| `overload_det*`, `thx_therm_det_*` | proteção térmica e de sobrecarga |
| `*_filter_count` | histerese/filtro de cada detector |

## 9. FPGA por BTF — o que ele faz

```c
struct fpga_config_params {
    bool is_dsd;
    int  sample_rate;
    fpga_i2s_format i2s_out_format;
    fpga_i2s_bits   i2s_out_bits;
    fpga_i2s_format i2s_in_format;
    fpga_i2s_bits   i2s_in_bits;
    fpga_i2s_type   i2s_in_type;
    bool spdif_tx, opt_tx, i2s_clk_out_en, i2s_data_out_en;
};
```

**Isto responde boa parte de Q5/Q8:** o FPGA é configurado com
`is_dsd`, `sample_rate` e formatos/bits de **entrada e saída** I2S, além de
habilitar SPDIF TX, **óptico**, clock out e data out. Não há campo de razão de
reamostragem — o modelo é **roteador/formatador**, não SRC.

`[HIP]` Conclusão provável: o áudio atravessa o FPGA sem conversão de taxa; ele
formata I2S, distribui clock e habilita as saídas SPDIF/óptica. Isso é
consistente com "bit-perfect até o DAC", mas **só a análise do bitstream ou uma
medição** fecha a questão.

Atualização de firmware por SPI (Gowin *slave SPI*):

```c
struct gw_fpga_device {
    ... void (*sspi_set_cs)(...); int (*sspi_single_write)(...);
    int (*sspi_bulk_write)(...);
    int (*read_id_code)(...); int (*read_user_code)(...);
    int (*read_status_code)(...); int (*update_firmware)(...);
};
```

`read_id_code`/`user_code`/`status_code` são os registradores de configuração
Gowin — dá para checar no aparelho se o FPGA carregou (`[?]` via sysfs).

## 10. O que ainda falta (e por que agora é fácil)

| Falta | Como fechar |
|-------|-------------|
| `volume_table` (valores em dB) | ler `.rodata` no offset do símbolo |
| Tabela de registradores do CS43198 | `cs43198_readable_register` + `.rodata` |
| Sequência de energia (delays) | `anolog_board_config_dac` (disassembly) |
| Protocolo SPI do FPGA | `gw_fpga_device` + bitstream |
| `fiioconfig` (layout) | `fiio_config.ko` + dump da partição |

Com símbolos e structs em mão, qualquer decompilador (Ghidra/IDA/objdump) vira
um leitor de lógica, não um exercício de adivinhação. `llvm-objdump` já está
disponível no host para o primeiro passe.
