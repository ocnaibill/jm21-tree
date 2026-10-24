# 41 — MQA (Q14): detecção, render e o que o DAC faz

> Dois arquivos MQA reais foram usados (não versionados no repo — só hashes).
> Aparelho com root, FiiO Music, saída interna.

| Arquivo | SHA-256 | Formato |
|---------|---------|---------|
| `mmixqv.flac` (The Weeknd — Starboy) | `499158f0…` | FLAC 24-bit/44,1 k, `ENCODER=MQAEncode v1.1 (2.3.2)`, álbum "Starboy [44.1-24 Tidal MQA]" |
| `ny0s79.flac` (Michal David) | `eac07609…` | FLAC 24-bit/44,1 k, `MQAEncode v1.1 (2.5.0)`, `ORIGINALSAMPLERATE=44100` |

## 1. O scanner só analisa MQA se a preferência estiver ligada

`[FATO]` Em `MediaManager.getAudioInfo`:

```java
boolean zB = e.d("setting").b("analyze_mqa", false);   // padrão FALSE
...
if (zB && (flac|wav) && rate in {44100,48000,88200,96000}) {
    ... AC.func2(rate, bits, path, size) ...  // checagem nativa (fiioac-jni)
    song.setSong_mimetype("MQA");
}
```

Com `analyze_mqa=false` (padrão), o arquivo entra na biblioteca como
**"FLAC 24 bits"** e o player abre com `isMQA:false` — **sem render MQA**. Foi
exatamente o que aconteceu na primeira tentativa.

Ligando a preferência (`/data/data/com.fiio.music/shared_prefs/setting.xml`,
`<boolean name="analyze_mqa" value="true"/>`) e reescaneando, o arquivo passa a
ter **duas entradas**: uma "FLAC 24 bits" e uma **"MQA"** (o scanner duplica o
registro em vez de atualizar).

## 2. Reprodução MQA — o que muda

Com o registro "MQA" tocando:

| Grandeza | PCM 44,1 k | **MQA 44,1 k** |
|----------|------------|----------------|
| App (`FiioMediaPlayer`) | `isMQA=false` | **`isMQA:true`**, `open: support = true` |
| HAL `mode` | MQA/ALLTO | **MQA** |
| HAL `srcRate` / `dstRate` | 44 100 / 44 100 | **44 100 / 44 100** (transporte não muda) |
| DAC `0x1000B` (SP_SRATE) | **1** | **7** (352,8 k) |
| FPGA `reg 0x02` | **`0x41`** | **`0x48`** (44,1 família × 8) |

Voltando ao PCM 44,1 k, os dois registradores **retornam** a 1 e `0x41` — ou
seja, a mudança é do caminho MQA, não resíduo.

Propriedades publicadas pelo stack MQA:

```
mqa.original.rate = 44100
mqa.bit.depth     = 24
mqa.audio.type    = 2      (o app trata 2/3 como MQA)
mqa.ui.state      = 3
```

## 3. Leitura

`[FATO]` Durante MQA, o DAC é reconfigurado para **352,8 kHz** (8 × 44,1 k) e o
FPGA para a mesma taxa, **enquanto o transporte HAL continua em 44,1 k**. Ou
seja: o DAC **não** recebe 352,8 k pelo I²S — ele recebe o FLAC/MQA a 44,1 k e
**faz o unfold/render internamente**, mudando o seu clock para a taxa de render.

`[HIP]` Isso é compatível com **decode completo (core + render) no DAC**: o core
sozinho daria 88,2 k; a configuração observada é a taxa de **render** (8×).
Para 48 k a família deve seguir (`0x81`/`0x88`), o que não foi testado.

`[?]` O segundo arquivo (`ny0s79.flac`) **não** foi marcado como MQA pelo
`AC.func2()`, mesmo com `MQAENCODER` e `ORIGINALSAMPLERATE` válidos. Pode ser
diferença de encoder (2.5.0 vs 2.3.2) ou de estrutura do stream. Fica aberto.

## 4. Implicação prática

Um usuário com arquivos MQA só ouve o render completo se a análise estiver
ligada (`analyze_mqa=true`); de fábrica ela está **desligada**, e o arquivo toca
como FLAC 24-bit comum (sem unfold). Isso é uma escolha de produto, não uma
limitação do hardware.

## 5. O caso `ny0s79.flac`: MQA real que o app não detecta

`[FATO]` O `AC.func2()` (checagem nativa do scanner) devolveu **false** para o
segundo arquivo, mesmo com `MQAENCODER` e `MQAENCODERSAMPLERATE` válidos. Para
separar "arquivo falso" de "checagem estrita", forcei o registro na tabela de
cache (`OBJECTA`, campo `I=1`) e reescanei: a biblioteca passou a tratá-lo como
"MQA", e a reprodução mostrou:

| | `mmixqv` | **`ny0s79`** |
|---|---|---|
| App `isMqa` | true | **true** |
| `mqa.audio.type` | 2 | **2** (MQA) |
| `mqa.original.rate` | 44 100 | 44 100 |
| `mqa.bit.depth` | **24** | **16** |
| `mqa.ui.state` | 3 | **2** |
| DAC `0x1000B` | 7 | **7** |
| FPGA `reg 0x02` | `0x48` | **`0x48`** |

`[FATO]` O **DAC reconhece o arquivo como MQA** (mesmo render em 352,8 k). Ou
seja: o arquivo é MQA genuíno; quem foi estrito demais foi o `AC.func2()`.

`[HIP]` A diferença está na profundidade: este stream renderiza em **16 bits**
(`mqa.bit.depth=16`) com `ui.state=2`, contra 24 bits/`state=3` do outro. A
checagem nativa parece exigir a variante de 24 bits (MQA "studio"/hi-res) e
rejeita a variante 16 bits — o que, na prática, faz o usuário perder o render
desses arquivos.

## 6. Bug observado: registro duplicado

Quando o scanner muda o mimetype para "MQA", ele **insere uma nova linha** em
`SONG` em vez de atualizar a existente — o arquivo aparece **duas vezes** na
biblioteca (uma "FLAC 24 bits" e uma "MQA"). Confirmado no banco depois do
rescan do `mmixqv`.

`[?]` Se a duplicata some com um rescan limpo (banco apagado) não foi testado.
