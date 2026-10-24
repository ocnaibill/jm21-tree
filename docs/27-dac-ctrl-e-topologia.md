# 27 — `dac_ctrl`: comandos de debug e a topologia provada nos dois chips

> Tudo aqui foi executado no aparelho (root) e confirmado por log do kernel.
> Dump completo em `device-baseline/regdump/read_all_regs.txt` (85 registradores,
> lidos **nos dois chips**).

## 1. A linguagem do `dac_ctrl`

O sysfs `dac_ctrl` não é só "rota": o `store` interpreta o **primeiro
caractere** como opcode.

| Opcode | Forma | Ação |
|--------|-------|------|
| `route_po` / `route_lo` / `route_ba` / `route_balo` | string | **nada** (ver §2) |
| `dac_reconfig` | string | re-executa `ops->config_dac` |
| `read_all_regs` | string | `ops->read_reg_all` — dump de todos os registradores nos dois chips |
| `2` | decimal `2NNN` | `volume = (N % 1000) - 100` e atualiza volume |
| `7` | hex `7XXXXXX` | **lê** `reg = (htoi(buf) % 0x1000000) - 0x100000` nos **dois** chips |
| `8` | decimal | escreve bits nos dois chips (reg, bit, valor empacotados) |
| `9` | `9` + 7 hex + valor | escreve bits nos dois chips (reg e valor em hex) |

### Como ler um registrador nos dois chips (opcode `7`)

O valor precisa satisfazer `(X % 0x1000000) - 0x100000 = reg`. Na prática,
basta somar `0x7000000`:

| Registrador | Comando | Saída |
|-------------|---------|-------|
| `0x90004` | `7190004` | `value_l` e `value_r` |
| `0x90002` | `7190002` | idem |
| `0x80000` | `7180000` | idem |

Exemplo real (capturado):

```
[snd_dac_set_ctrl] read dac reg = 0x90004, value_l = 0x00, value_r = 0x0c
[snd_dac_set_ctrl] read dac reg = 0x90002, value_l = 0x5d, value_r = 0x5d
```

## 2. Correção: os comandos de rota são **inertes**

Testei os quatro (write retornou 0, o driver logou cada um) e **nada mudou**:
`headset_type`, `board_output_type`, `board_vol_dac` e `dac_vol` idênticos, sem
`HEADSET_OUTPUT_TYPE_CHANGE` no dmesg.

O código explica: os `strcmp` das rotas, quando **casam**, apenas saem da cadeia
de `if` e não executam ação nenhuma. A rota real é dirigida pelo
`current_output_type`, definido pela **detecção de jack** e pelo modo de
operação — não por esse sysfs.

`[?]` Fica em aberto se em outro modelo/modo esses comandos fazem algo. No JM21
1.1.1, não.

## 3. A topologia, provada no silício

`read_all_regs` (tocando FLAC 44,1 kHz, volume 30, 3,5 mm):

| Registrador | L | R | Leitura |
|-------------|---|---|---------|
| `0x90004` PCM Path Control 2 | `0x00` | **`0x0C`** | **R com INV_A+INV_B** → par diferencial |
| `0x90002` PCM Volume A | `0x5D` (93) | `0x5D` | mesmo código nos dois |
| `0x90001` PCM Volume B | `0x5D` | `0x5D` | idem |
| `0x90000` Filtro | `0x42` | `0x42` | preset 2 |
| `0x90003` Path Signal 1 | `0xAC` | `0xAC` | ativo, sem mute |
| `0x80000` Analog Out 1 | `0x30` | `0x30` | OUT_FS=11, +1dB_EN=0 |
| `0x20000` Power Down | `0xAE` | `0xAE` | ligado (bits 6 e 4 limpos) |
| `0x5000A/B` ASP slots | `0x07` / `0x0F` | idem | `SPECIAL_MODE_2` |
| `0x70000/1` DSD volume | `0x78` | `0x78` | default (não usado) |
| `0x20052` Cristal | `0x04` | `0x04` | bias de 12,5 µA |
| `0x40002` PLL | `0x02` | `0x02` | default |

E a identidade do chip `[FW-DEV]`:

```
0x10000 = 0x43   0x10001 = 0x19   0x10002 = 0x80   -> DEVID = 0x431980
0x10004 = 0xA1                                      -> REV_ID = Rev A1
```

Os dois valores batem com o datasheet e com a pesquisa externa (que acertou
`DEVID 0x431980` e `REV_ID 0xA1`).

**Conclusão definitiva:** os dois CS43198 recebem **o mesmo estéreo** (volumes e
filtro idênticos) e o chip **R opera com os dois canais invertidos**. É um par
diferencial, não uma divisão L/R. Fecha o conflito de
`15-conflitos-e-metodo-de-prova.md` §1 com evidência de registrador, não de
inferência.

## 4. O que ainda dá para fazer com esses comandos

- **`8`/`9`**: escrevem bits em ambos os chips sem passar pelo driver — útili
  para experimentos controlados (ex.: ligar `+1dB_EN` manualmente e medir),
  mas é escrita direta em registrador de hardware. Só com o fone longe e
  sabendo o valor anterior.
- **`dac_reconfig`**: re-executa o init do DAC; cuidado com pop.
- **`read_all_regs`**: baseline completo antes/depois de qualquer mudança —
  hoje temos o de 44,1 kHz/vol 30 com 3,5 mm.

## 5. Próximos experimentos sugeridos

1. `read_all_regs` em **DSD** e em **96/192 kHz** para comparar `0x10006`,
   `0x40010–0x40019` e `0x5000A/B`.
2. `read_all_regs` com **EQ ligado/desligado** — ver se algo muda no chip
   (deve mudar só no domínio digital do HAL, não no DAC).
3. `read_all_regs` em **volume 120** (com cautela) para confirmar `+1dB_EN`.
