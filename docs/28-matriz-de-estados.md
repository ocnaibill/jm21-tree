# 28 — Matriz de estados (rodada 1): taxa × DAC/FPGA

> Captura automática em 2026-10-23 (monitor `tools/matrix-capture.sh`), 3,5 mm,
> volume 30 (código 93), FLAC 24-bit, tons de 1 kHz.
> Dump bruto: `device-baseline/matrix-20261023-225105.txt`.

## 1. Resultado

| Arquivo | `srcRate` | `srcFormat` | `halFormat` | `dstFormat` | Modo da HAL | Registradores |
|---------|-----------|-------------|-------------|-------------|-------------|----------------|
| 44,1 kHz | 44100 | 1 (PCM16) | 1 | 3 (PCM32) | **MQA** | volume 93, filtro 0x42 |
| 48 kHz | 48000 | 5 (float) | 5 | 3 | **MQA** | idem |
| 96 kHz | 96000 | 5 | 5 | 3 | **MQA** | idem |
| 192 kHz | 192000 | 5 | 5 | 3 | **ALLTO32BIT** | idem |
| 384 kHz | — | — | — | — | **recusado pelo app** | — |

## 2. O que confirma

1. **Zero reamostragem.** Em todos os casos `srcRate = dstRate = halRate`; o
   AudioFlinger reporta a mesma taxa do arquivo.
2. **O DAC não muda volume/filtro/power com a taxa**: `0x90002/0x90001 = 93`,
   `0x90000 = 0x42`, `0x80000 = 0x30`, `0x20000 = 0xAE` — idênticos de 44,1 a
   192 kHz. A taxa é configurada em **outros** registradores (ASP/clock), que
   esta rodada não leu — ver §4.
3. **O `fpga_config` do sysfs é cache, não estado vivo**: ficou todo zero em
   todas as taxas, embora o dmesg mostre escrita no FPGA e MCLK 22/24 MHz.
4. **O rótulo de modo não descreve o arquivo.** `MQA` apareceu em FLAC comuns
   (e o app registra `isMQA:false`); em 192 kHz virou `ALLTO32BIT`. É um
   **bitmask de estágios de processamento ativos**, não "o arquivo é MQA".
   `[HIP]` forte, agora com 4 amostras consistentes.

## 3. O 384 kHz: recusado pelo app

`ffprobe` confirma que o arquivo é válido (FLAC, 384 000 Hz, 24-bit, estéreo).
O FiiO Music responde *"we can't play this file"* já na abertura — é **política
do player**, não do hardware (o HAL nunca chegou a configurar o stream).

A ficha oficial promete 384 kHz na decodificação local; portanto:
- `[?]` ou o limite real do player é 352,8 kHz;
- `[?]` ou há exigência de formato (16-bit? WAV?) para 384 kHz.

Teste proposto (issue): gerar 352,8 kHz e 384 kHz em 16 e 32 bits e ver quais
abrem.

## 4. O que a rodada **não** capturou (e por quê)

Os registradores que **variam com a taxa** são os do ASP e do clock, que não
entraram no snapshot:

| Registrador | Decimal | Por que importa |
|-------------|---------|-----------------|
| `0x40010–0x40019` | 262160–262169 | configuração do ASP (gerador de clock) |
| `0x10006` | 65542 | System Clocking Control (MCLK_INT/MCLK_SRC) |
| `0x5000A/B` | 327690/327691 | mapping de slots |
| `0x70000/1` | 458752/458753 | volume DSD |
| `0x20052` | 131154 | bias do cristal |

Além disso, o `fpga_config` precisa ser trocado por **dmesg**
(`fpga_set_mclk`, `fpga_i2c_write`) — que é onde o clock real aparece.

## 5. Próxima rodada (P1b)

1. Monitor atualizado lendo o conjunto acima (e o dmesg do FPGA por timestamp).
2. Tocar 44,1 / 48 / 96 / 192 de novo (~4 s cada).
3. Comparar `0x40010–0x40019` e `0x10006` entre famílias (44,1 × 48) — é a
   assinatura do chaveamento de clock.
4. Testar 352,8 kHz e 384 kHz em 16/32 bits para localizar o limite do player.

## 6. Nota de método

A primeira versão do monitor lia o registrador **imediatamente** após escrever e
devolvia o valor anterior (deslocamento de um). Corrigido com atraso de 200 ms
entre escrita e leitura. Registro mantido porque é o tipo de erro que contamina
uma matriz inteira sem dar sinal.

---

# Rodada 2 (P1b): clock e registradores de taxa

> Captura automática em 2026-10-23 22:56 (monitor revisado), 3,5 mm, volume 30,
> FLAC 24-bit. Bruto: `device-baseline/matrix-20261023-225639.txt`.

## 7. Resultado

| Arquivo | `srcRate` | `halRate` | Modo | `0x40010–0x40019` | `0x10006` | FPGA reg `0x02` |
|---------|-----------|-----------|------|-------------------|-----------|-----------------|
| 44,1 kHz | 44100 | 44100 | MQA | idênticos | 0 | **`0x41`** |
| 48 kHz | 48000 | 48000 | MQA | idênticos | 0 | **`0x81`** |
| 96 kHz | 96000 | 96000 | MQA | idênticos | 0 | **`0x82`** |
| 192 kHz | 192000 | 192000 | ALLTO32BIT | idênticos | 0 | **`0x84`** |

Valores fixos lidos: `0x40010..19 = 1,0,8,0,31,0,63,0,12,10`; `0x5000A/B = 7/15`;
`0x70000/1 = 120`; `0x20052 = 4`.

## 8. O achado: o FPGA recebe a taxa por I²C

`[FW-DEV]` A cada configuração de stream, o driver escreve **um** registrador do
FPGA (`fpga_i2c_write, reg = 0x02`) com um código que muda por taxa, cercado por
`fpga_fill_clk enable=1` → escrita → `enable=0`:

| Taxa | `reg 0x02` | Binário |
|------|-----------|---------|
| 44,1 kHz | `0x41` | `0100 0001` |
| 48 kHz | `0x81` | `1000 0001` |
| 96 kHz | `0x82` | `1000 0010` |
| 192 kHz | `0x84` | `1000 0100` |

`[HIP]` Leitura do campo: **bit 6 (0x40) = família 44,1**; **bit 7 (0x80) =
família 48**; **bits baixos = multiplicador** (1 = base, 2 = ×2, 4 = ×4).
Previsão: 88,2 → `0x42`, 176,4 → `0x44`, 352,8 → `0x48`, 384 → `0x88`.
Testar 88,2 e 352,8 confirma o modelo.

Isso responde parte de Q5/Q27: o FPGA **é reconfigurado por taxa**, com um código
de família + multiplicador — consistente com ele gerando/redividindo o clock dos
DACs.

## 9. O que ainda falta para fechar o mapa de taxa

1. **`0x1000B` (SP_SRATE)** — o registrador onde o `config_dac` grava o índice
   de taxa. Não entrou no snapshot. É o lado DAC da mesma informação.
2. `0x1000C` (SP_BITSIZE), se aplicável.
3. Testar **88,2 kHz** e **352,8 kHz** para validar a codificação do FPGA.

Rodada 3: ler `0x1000B` enquanto toca cada taxa (uma leitura só, rápida).

## 10. Nota sobre o root durante a captura

Em um dos eventos o aviso de "superusuário concedido" do Magisk não apareceu.
Isso **não afetou** a captura: o snapshot de 48 kHz está completo (21
registradores lidos). O aviso só é exibido quando a concessão expira; com
"lembrar por 10 minutos" ele fica silencioso.

---

# Rodada 3 (P1c): o código de taxa, dos dois lados

> Captura mínima (`tools/rate-register-capture.sh`): para cada stream, espera
> 1,5 s e lê **apenas** `0x1000B` (SP_SRATE). Bruto:
> `device-baseline/rate-20261023-230757.txt`.

## 11. Resultado

| Taxa | `0x1000B` (DAC) | FPGA `reg 0x02` | Modo |
|------|-----------------|-----------------|------|
| 88 200 | **3** | `0x42` | MQA |
| 44 100 | **1** | `0x41` | MQA |
| 48 000 | **2** | `0x81` | MQA |
| 96 000 | **4** | `0x82` | MQA |
| 192 000 | **6** | `0x84` | ALLTO32BIT |
| 352 800 | recusado pelo app | — | — |
| 384 000 | recusado pelo app | — | — |

## 12. Confirmação cruzada: decompilado × hardware

A tabela que extraímos de `cs43198_config_dac` (índice de taxa → registrador
ASP) era:

```
0 = 32000   1 = 44100   2 = 48000   3 = 88200   4 = 96000
5 = 176400  6 = 192000  7 = 352800  8 = 384000
```

Os cinco pontos medidos batem **exatamente** (1, 2, 3, 4, 6). É a validação
completa do mapa de taxa do driver no silício.

Do lado do FPGA, a codificação também é consistente: **bit 6 = família 44,1**,
**bit 7 = família 48**, bits baixos = multiplicador da taxa base. Previsões
(ainda não medidas, porque o app recusa): 176,4 → `0x44`, 352,8 → `0x48`,
384 → `0x88`.

## 13. Nota de método (de novo)

A leitura em sequência rápida de vários registradores durante a reprodução
devolve valores **atrasados** (o store do sysfs ainda não propagou). A solução
adotada: **um registrador por vez, com 1,5 s de estabilização**. A matriz das
rodadas 1–2 sofreu com isso em parte dos blocos; os campos estáveis (volume,
filtro, power) foram reconfirmados na rodada 3.

## 14. O que isso fecha

- **Q27 (clock por família)**: respondida. O FPGA recebe um código de taxa por
  I²C a cada stream; o DAC recebe o índice em `0x1000B`.
- **Q26 (DSD nativo)**: ainda aberto — precisamos de um arquivo DSD.
- **Q5 (o que o FPGA faz)**: agora sabemos que ele é **reconfigurado por taxa**;
  resta saber se processa amostras ou só divide clock.

---

# O limite de 352,8/384 kHz é **política do app** (achado no código)

> Descoberto no `MediaPlayerService` do FiiO Music decompilado, depois do teste
> com o VLC.

## 15. A regra exata

`com/fiio/music/service/MediaPlayerService.java` (~linha 2567):

```java
if (songF != null
    && com.fiio.product.b.d().k()                       // capacidade do modelo
    && (rate == 352800 || rate == 384000)
    && !com.fiio.product.b.d().c().p())                 // NÃO é saída USB
{
    this.f5493d = ErrorCode.UNSUPPORTED;
}
```

E a flag `k()`:

| Implementação | Retorno |
|---------------|---------|
| `com.fiio.product.b.k()` | `true` só para M6 / M7 / M7K / M9 |
| `com.fiio.product.device.b.k()` | **`true` fixo** (classe do JM21) |

Ou seja: no JM21 a combinação **"352,8/384 kHz + saída interna (3,5/4,4 mm)"**
é marcada como **UNSUPPORTED de propósito**. Com saída **USB**, a mesma taxa é
permitida — e `IDevice.setUsbAudioSupportSampleRate()` existe justamente para
listar as taxas suportadas por USB (bitmask; 64 = 352,8 k, 128 = 384 k).

Isso resolve a issue #9: **não é o hardware nem o arquivo** — é o player que
recusa. A ficha oficial ("384 kHz na decodificação local") não bate com o
código do próprio app para a saída interna.

`[?]` Continua em aberto se o **DAC/FPGA** aceitariam 352,8/384 — a previsão
pelo modelo é `0x1000B = 7/8` e FPGA `0x02 = 0x48/0x88`. Para provar, só por
USB (UAC), com um host que envie essas taxas.

## 16. Teste com o VLC (inconclusivo, e por quê)

- APK oficial 3.7.1 arm64, hash conferido com o `.sha256` do VideoLAN.
- VLC **abriu** o `tone_352800_24.flac` (não recusou), mas entregou o áudio à
  HAL a **44 100 Hz / PCM16** — ou seja, reamostrou na saída dele.
- Portanto **não serve** para provar o limite do hardware: o gargalo passou a
  ser o VLC, não o JM21.
- VLC desinstalado ao fim do teste.

Lição: para testar o limite do hardware, o caminho é **USB (UAC)** ou um player
que force a taxa nativa — não um player que negocia a taxa de saída.
