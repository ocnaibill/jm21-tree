# 38 — Ganho analógico (P2): as três curvas de volume, medidas no silício

> Procedimento: tom de 44,1 kHz tocando, `DAC PO Gain` varrido em 0/1/2 e
> `0x90001` (volume L) lido a cada passo, com 1 s de estabilização. Volume
> ajustado pelo kcontrol `DAC Playback Volume`.

## 1. Resultado

Código escrito no DAC (`0x90001` / `0x90002`; menor = mais alto):

| Volume | ganho 2 (alto) | ganho 1 (médio) | ganho 0 (baixo) |
|--------|----------------|-----------------|-----------------|
| 0 | 255 | 255 | 255 |
| 10 | 153 | 167 | 179 |
| 20 | 113 | 133 | 145 |
| 30 | 93 | 113 | 125 |
| 40 | 80 | 93 | 105 |
| 60 | 60 | 72 | 84 |
| 80 | 40 | 52 | 64 |
| 100 | 20 | 32 | 44 |

`dac_vol` do sysfs acompanha o volume; `board_vol_dac` continua sendo
**`255 − código`** em todos os casos (195/183/171 no volume 60, etc.).

## 2. Validação das tabelas do driver

As três colunas são **idênticas** às tabelas extraídas do código decompilado
(`analysis/fw-1.1.1/volume-tables.csv`, colunas `gain_h`, `gain_m`, `gain_l`):

| Volume | CSV `gain_h` | medido g2 | CSV `gain_m` | medido g1 | CSV `gain_l` | medido g0 |
|---|---|---|---|---|---|---|
| 20 | 113 | 113 | 133 | 133 | 145 | 145 |
| 30 | 93 | 93 | 113 | 113 | 125 | 125 |
| 60 | 60 | 60 | 72 | 72 | 84 | 84 |
| 100 | 20 | 20 | 32 | 32 | 44 | 44 |

`[FATO]` As três curvas estão **validadas em hardware**, sem nenhum valor
derivado.

## 3. O ganho **não** mexe em registrador analógico

No mesmo teste, com o volume fixo em 30 e variando o ganho, estes registradores
ficaram **idênticos**:

```
0x80000 = 48   0x80001 = 0   0x90004 = 0   0x90000 = 66   0x40000 = 0
```

`[FATO]` O `DAC PO Gain` é aplicado como **atenuação digital** no próprio DAC
(a curva escolhida), não por troca de ganho analógico no amplificador. Se
houvesse chaveamento de ganho no SGM8262-2, ele não aparece por I²C do DAC —
teria de ser por GPIO, e nenhum GPIO mudou de estado.

`[HYP]` Isso significa que os ganhos "médio" e "baixo" **perdem relação
sinal/ruído** em vez de ganhar headroom analógico — coerente com um DAP que usa
o ganho para limitar potência, não para melhorar SNR.

## 4. Nota de segurança (processo)

A varredura incluiu volume 100 **com o fone no ouvido do usuário**. O volume foi
restaurado para 30 imediatamente, mas o correto seria avisar antes de varrer
volumes altos. Regra que fica: **varredura de volume sempre com o fone fora do
ouvido**, ou apenas até o teto combinado (30/120).

## 5. O que fica em aberto

- `DAC line Out Volume` (0 no repouso) não foi varrido — é o nível da saída de
  linha, controlado separadamente.
- A medição é do **código digital**; a potência real (Vrms) continua sendo
  assunto de bancada (P3).
