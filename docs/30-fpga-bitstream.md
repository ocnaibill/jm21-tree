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

## 7. Tentativa de decodificar (Apicula) — bloqueio conhecido

Instalei o **Apicula** (projeto aberto de engenharia reversa Gowin) num venv. Ele
**suporta o GW1NZ-1** (`GW1NZ-1.msgpack.xz` presente).

```
python -m apycula.gowin_unpack gw_fpga_firmware_jm21.fw -d GW1NZ-1
→ UnicodeDecodeError: 'utf-8' codec can't decode byte 0xff
```

**Causa:** o Apicula lê o formato **texto** (`.fs`, do programmer da Gowin:
cada linha é um frame em ASCII binário, com CRC16-ARC por frame). O arquivo da
FiiO é **binário** — comandos + frames crus, sem as linhas nem os CRCs.

O conteúdo bate: no offset 0x20 aparecem `0x10` e `0x51`, que o `bslib.py` usa
para detectar header/compressão; e o ID `0x0100681B` está em 0x1C.

**Caminho para destravar:** escrever um conversor `.fw → .fs`
(comando `0x3B` dá a contagem de frames; cada frame é payload + 8 bytes de
CRC/pad no formato texto). O validador é o próprio `bslib.read_bitstream`, que
confere o CRC16 de cada frame — se o conversor estiver certo, ele lê o design.

Enquanto isso não é feito, o que já sabemos do FPGA vem de fora do bitstream:
registradores SPI (0x01 modo, 0x02 taxa, 0x13 user code, 0x41 status), clocks
de saída (22/24 MHz), e o comportamento medido no áudio.

### Sem caminho de leitura genérica de registradores

`fpga_debug` (sysfs) só aceita `hdmi_code_fmt_0..3` — não é um acesso genérico
a registrador. `fpga_gw_read_code` devolve o user code. Não há, portanto, como
varrer o mapa de registradores do design sem um hook novo.

## 8. Geometria do arquivo (medida)

| Campo | Valor |
|-------|-------|
| Header | **129 bytes** (inclui 20× `FF`, `A5C3`, ID, compress keys, SPI address, `3B` com a contagem) |
| Frames | **274** (`0x0112`, bate com `db.height = 274` do chipdb do Apicula) |
| Bytes por frame | **122** (976 bits) |
| Dados | **33 428** = 274 × 122 |
| Footer | 48 bytes (termina em `34 73 0A 00 00 00 <user code>`) |
| Total | 129 + 33 428 + 48 = **33 605** ✓ |

`[?]` A linha `3B 80 01 12` (contagem de frames) está no offset **0x40**, e não no
fim do header — sobram **63 bytes** entre ela e o começo dos frames. Pelo
formato do Apicula, o `3B` encerra o header. Ou o header real tem 66 bytes e os
63 bytes são um bloco extra **depois** dos frames (BSRAM/init), ou o layout da
FiiO difere do `.fs` do programmer. As duas leituras fecham a conta
(66 + 33 428 + 63 + 48 = 33 605), e essa é a única ambiguidade que resta para
escrever o conversor.

## 9. O que já se sabe do design sem decodificar

- O FPGA **gera os clocks** dos DACs: `fpga_set_mclk … 22/24 MHz`.
- Converte/repassa **I²S → DAC** e **DSD/DoP → DAC** (regs `0x01`/`0x02`).
- Tem **entrada e saída SPDIF** (`fpga_config_spdif_rx/tx`, `spdif_rx_bypass`,
  `spdif_tx_enable`, `xmos_spdif_rx`).
- Tem caminho de **HDMI** (`fpga_config_hdmi_code_fmt`).
- Liga/desliga por modo (`fpga_ctrl_power_by_mode`), com `fpga_bypass` no sysfs.
- Não faz volume (o volume vai por I²C ao DAC) nem EQ.

Ou seja: é um **roteador de áudio + gerador de clock**, não um DSP.
