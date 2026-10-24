# 43 — `jm21ctl`: controle por userspace (issue #14)

> Ferramenta em `tools/jm21ctl.sh`. Roda no **host** e fala com o aparelho via
> adb (root). Não precisa de módulo de kernel nem toca em AVB.

## 1. Por que userspace

O caminho de kernel (módulo out-of-tree) depende da árvore/`Module.symvers` da
FiiO (`docs/42`/issue #10). Entretanto, **tudo o que controla o áudio já está
exposto** por interfaces estáveis:

| Interface | O que dá | Onde |
|-----------|----------|------|
| kcontrols ALSA (`tinymix`) | volume, ganho, filtro, balanço, line out, THD C2 | HAL → `dac_core` |
| `soc:fiio_attr/dac_ctrl` | comandos (volume `2NNN`, leitura `7XXXXXX`, escrita `8/9`) | `dac_core` (`docs/27`) |
| `soc:fiio_attr/dac_read_reg` | leitura de registrador nos dois chips | `cs43198` |
| keyevents 24/25 | volume da música (o framework é autoritativo) | AudioService |

`[FATO]` Escrita direta no kcontrol de volume é ignorada enquanto o framework
está no comando (`docs/33` §2) — por isso `jm21ctl vol set` usa **keyevents**,
e não o mixer.

## 2. Comandos

```bash
./tools/jm21ctl.sh status
./tools/jm21ctl.sh vol get | vol set 30 | vol +5 | vol -5
./tools/jm21ctl.sh gain get | gain set 0|1|2
./tools/jm21ctl.sh filter get | filter set 0..4
./tools/jm21ctl.sh balance get | balance set 0..40      # 20 = centro
./tools/jm21ctl.sh lineout get | lineout set N
./tools/jm21ctl.sh thdc2 get | thdc2 set N
./tools/jm21ctl.sh reg read 0x90001
./tools/jm21ctl.sh reg dump 40
./tools/jm21ctl.sh rate
```

Seleção de aparelho: por padrão usa o **USB** (`adb -d`). Com Wi-Fi:
`./tools/jm21ctl.sh -s 192.168.1.33:5555 status` ou `JM21_SERIAL=...`.

## 3. O que ele mostra

`status` traz: volume da UI, `PO Gain`, filtro, balanço, `0x1000B` (índice da
taxa), código do FPGA (`reg 0x02`), a última linha da HAL e a saída
(`fiio.current.play.device`).

`rate` mostra só a tríade taxa: `0x1000B`, FPGA e HAL — útil durante a matriz.

`reg read 0xADDR` lê **nos dois chips** (L e R) e devolve os dois valores, no
formato do driver.

`reg dump N` dispara `read_all_regs` e mostra as N últimas linhas
(`[CS43198]: read reg 0x…, value_l = …, value_r = …`).

## 4. Teste feito

```
status  -> volume 31, gain 2, filtro 2, balanço 20, 0x1000B=7, FPGA 0x48
gain set 1 -> 1 ; gain set 2 -> 2
filter set 3 -> 3 ; filter set 2 -> 2
vol set 30 -> 30 ; vol set 31 -> 31
reg read 0x90001 -> 93
reg dump 4 -> linhas [CS43198] com value_l/value_r
```

Restaurado ao estado original depois do teste.

## 5. Limites

- **Não escreve registrador** por padrão: os opcodes `8`/`9` do `dac_ctrl`
  existem, mas a ferramenta só lê. Escrita fica para quando houver um caso
  concreto e reversível.
- Não troca modo de operação (isso reinicia o app e pode derrubar o adb —
  `docs/37`).
- Não faz EQ (é `AudioEffect` do AOSP, `docs/32`).
