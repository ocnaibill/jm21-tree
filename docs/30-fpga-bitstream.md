# 30 — FPGA Gowin: bitstream, versões e carga

> Fonte: arquivos em `/vendor/firmware/` puxados do aparelho + `dmesg` + sysfs.
> Binários **não** vão para o git (só hashes e achados).

## 1. O que existe no aparelho

| Arquivo | Tamanho | SHA-256 | User code |
|---------|---------|---------|-----------|
| `gw_fpga_firmware_jm21.fw` | 33 605 B | `7b5a27758972acc9d2465337140abf6c7ee79b22c0c47bc80208573c9a842165` | **`0xF2510003`** |
| `gw_fpga_firmware_jm21_2.fw` | 29 843 B | `6de659ac827150e0bc0616661b8d682fa7f947f1f5ddcb5844667a56834778b4` | **`0xF2510004`** |

Drivers: `gw-fpga.ko`, `fpga_interface.ko`, `fpga_audio_interface.ko`,
`fpga-mgr.ko`.

## 2. Formato e identificação do chip

- Magic Gowin `A5 C3` no offset **0x0C** (precedido de 12 bytes `0xFF`).
- **ID code `0x0100681B`** (big-endian, offset 0x1C) nos **dois** arquivos.
  É o ID de dispositivo Gowin — corresponde à família **GW1NZ-1**.
- O **user code** fica nos últimos 26 bytes:

```
jm21.fw    ... 34 73 0a 00 00 00 f2 51 00 03 ff ff ...
jm21_2.fw  ... 34 73 0a 00 00 00 f2 51 00 04 ff ff ...
```

Ou seja: **mesmo alvo, builds diferentes** — `0xF2510003` e `0xF2510004`.
O aparelho carrega o **v3**.

## 3. Como o aparelho carrega (medido no boot)

`dmesg`:

```
[GW_FPGA]: fpga_cs = 406
[GW_FPGA]: fpga_init_gpio: fpga_pwr_en = 392
fpga_manager fpga0: GW Slave Serial FPGA Manager registered
[GW_FPGA]: fpga_reload_firmware: update fpga firmware success,
           id code = 0x100681b , user code = 0xf2510003 , status code = 0x3f020
```

sysfs:

```
fpga_gw_fw_name = gw_fpga_firmware_jm21.fw
fpga_gw_version = 0xf2510003
fpga_power      = off
```

O driver expõe `fpga_gw_reload`, `fpga_gw_update`, `fpga_gw_erase`,
`fpga_gw_update_firmware_name`, `fpga_gw_read_code`, `fpga_gw_spi_func`,
`fpga_gw_input_func`, `fpga_gw_power_ctrl`, `fpga_hwinit`, `fpga_bypass`,
`fpga_config`, `fpga_debug`.

Estágios internos do `gw-fpga.ko`: `INIT_ADDRESS`, `WRITE_ENABLE`,
`WRITE_DATA`, `WRITE_DISABLE` — protocolo de configuração do Gowin por SPI
(slave serial).

## 4. Protocolo SPI visto ao vivo

```
fiio_spi_write_then_read, n_tx=4 13 00 00 00  n_rx=4  f2 51 00 03   ← user code
fiio_spi_write_then_read, n_tx=4 41 00 00 00  n_rx=4  00 03 f0 20   ← status
```

Formato: comando de 4 bytes (`registrador` + 3 zeros), resposta de 4 bytes.
O `reg 0x13` devolve o user code do design carregado — é assim que o driver
confirma o que está no FPGA.

## 5. Energia

`fpga_ctrl_power_by_mode: pdata->mode:0, mode:0` e `fpga_set_power power = off`
aparecem quando o modo de áudio volta ao interno. Ou seja: o FPGA é **ligado
sob demanda** (quando o caminho de áudio precisa dele) e desligado fora disso.

## 6. Perguntas abertas

1. **O que tem dentro do design?** (SPI slave, divisores de clock, I²S/DSD,
   FIFO, reclock?) — precisa decodificar o bitstream.
2. **Diferença entre v3 e v4**: 3 762 bytes a menos no v4; mudança funcional ou
   só de build?
3. Quem escolhe o arquivo: `fiioconfig` (campo de nome vazio) ou o default do
   driver? O `_2.fw` nunca é carregado neste firmware?
4. O `fpga_bypass` (sysfs) faz o quê — desvia o FPGA no caminho de áudio?
