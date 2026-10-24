# 31 — Netlist do FPGA (Gowin GW1NZ-1) extraído do bitstream

> Conversão do `.fw` binário da FiiO para o formato `.fs` do Apicula, seguida de
> `gowin_unpack`. O artefato é o `gw_fpga_firmware_jm21.fw` (user code
> `0xF2510003`), o que o aparelho carrega.

## 1. Como foi feito

`tools/fpga_fw_to_fs.py` (novo, no repo) faz a conversão:

1. Header: 22 bytes `FF` (20+2) + `A5C3` + ID + compress keys + SPI address +
   `3B` com a contagem (**274** frames).
2. Dados: **comprimidos** com RLE de uma chave. A chave vem do byte 5 da linha
   `0x51` do header — `0xDB` neste build — e cada `0xDB` vira **8 bytes zero**.
3. Cada frame, já descomprimido, tem **160 bytes** (1280 bits = 1216 úteis +
   64 de padding), o que fecha com `db.width = 1216` do chipdb do GW1NZ-1.
4. O `.fs` é reescrito com a flag de compressão **desligada** (bit 13 da linha
   `0x10`), CRC16-ARC por frame (2 bytes + 6 de padding), como o Apicula espera.

```
$ python3 tools/fpga_fw_to_fs.py gw_fpga_firmware_jm21.fw jm21_v3.fs
jm21_v3.fs: header 68 B, 274 frames de 160 B
            (bruto 33487 B, chave 0xdb, descomprimido 43840 B), footer 50 B

$ gowin_unpack jm21_v3.fs -d GW1NZ-1 -o jm21_v3.v
```

`[NOTA]` Foi preciso corrigir **um bug do Apicula**: em `parse_tile_`, um DFF
sem `dff_type` reconhecido com atributo `REG*_SD` estourava `KeyError`
(`bels[f'{name}'].update({'SD'})` fora de um `if`). Correção local: mover o
`update` para dentro do `if dff_type:`.

## 2. O que o design contém (contagem de células)

| Célula | Qtd | Para que serve |
|--------|-----|----------------|
| `LUT4` | **803** | lógica combinacional |
| `MUX2` | 1040 | muxes LUT5 (realização das funções) |
| `DFFSE` | **337** | flip-flops (registradores) |
| `ALU` | **52** | somadores/contadores |
| `RAM16SDP4` | **18** | RAM 16×4 distribuída → FIFOs / delay / CDC |
| `DFFPE`, `DFFE`, `DFFRE`, `DFFCE`, `DFFR`, `DFF` | 25+19+11+1+11+26 | outros FFs |
| `IDES10` | 1 | desserializador de **10 bits** (entrada serial rápida) |
| `IDDRC`, `IVIDEO` | 1, 2 | captura DDR / vídeo |
| `ODDR` | 1 | saída DDR |
| `ELVDS_OBUF` | 1 | **saída LVDS** (diferencial) |
| `IOBUF`, `IBUF` | 2, 7 | buffers de I/O |
| `OSCZ` | 1 | oscilador interno, `FREQ_DIV = 2` |
| `DLE/DLPE/DLCE` | 34+16+10 | latches |

Topo: **11 pinos** (7 entradas, 2 saídas, 2 bidirecionais). Os nomes
(`R#C#_...`) são coordenadas do die, não pinos do pacote.

## 3. Leitura

`[FATO]` O design é **pequeno e sequencial**, não um processador de áudio:

1. **Desserializador de entrada** (`IDES10`/`IDDRC`) + **FIFOs** (`RAM16SDP4`)
   + **saída DDR/LVDS** (`ODDR`/`ELVDS_OBUF`) = um estágio de
   **re-clock / travessia de domínio de clock**.
2. **Oscilador interno** com divisor 2 (`OSCZ`, `FREQ_DIV=2`) alimenta esse
   estágio — é a referência própria do FPGA para re-temporizar.
3. **52 ALU** sugerem contadores/divisores de clock (geração de BCLK/LRCLK a
   partir do MCLK).
4. **Zero** blocos de multiplicação (`MULT*`) e **zero** BSRAM grande: não há
   DSP de áudio (nem volume, nem EQ) dentro do FPGA.

Isso fecha a pergunta da issue #4: o FPGA **re-clocka e roteia** o áudio, e
gera os clocks; não processa o sinal.

## 4. O segundo bitstream (`_2.fw`, user code `0xF2510004`)

Também decodifica com o conversor — mas com **duas** chaves de compressão
(`0x97` → 8 zeros, `0xD9` → 4 zeros). O resultado é **outro design**:

| | v3 (carregado) | v4 (`_2.fw`) |
|---|---|---|
| Pinos no topo | **11** | **23** |
| `LUT4` | 803 | 734 |
| `DFFSE` | 337 | 265 |
| `ALU` | 52 | 62 |
| `RAM16SDP4` | 18 | 12 |
| `IOBUF` | 2 | **10** |
| `IVIDEO` | 2 | **9** |
| `I3C_IOBUF` | — | **9** |
| Serializador/DDR | `IDES10`, `IDDRC`, `ODDR`, `ELVDS_OBUF` | ausentes |

`[HIP]` O v4 é um design para **outra variante de placa** (interface I3C e muito
mais I/O), não uma atualização do v3. É por isso que o aparelho carrega o v3.

## 5. Pendências

- `gw_fpga_firmware_jm21_2.fw` (user code `0xF2510004`) **não** descomprime para
  o tamanho esperado: chave `0x97`, saída 39 623 B contra 43 840 B. Ou é um
  build parcial/delta, ou usa outra codificação. **Não é o que o aparelho
  carrega**, então ficou de fora.
- O netlist é **porta-a-porta** (LUTs), não um esquemático nomeado. Mapear
  função por função exigiria simulação/equivalência — possível, mas é outro
  projeto.
- O `.cst` (mapa pino↔sinal da placa) não existe no aparelho; os nomes de pino
  do topo são coordenadas do die.
