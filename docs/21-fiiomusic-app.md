# 21 — FiiOMusic (app): JNI, AudioTrack e processamento

> Fonte: `FiiOMusic.apk` (117 MB) decompilado com JADX 1.5.6 (10 337 classes,
> 73 erros de decompilação — normal em app ofuscado) + assinaturas e exports
> das bibliotecas nativas.

## 1. Superfície JNI (confirmada nas duas pontas)

As três bibliotecas registram métodos via `JNI_OnLoad`/`RegisterNatives` (não há
símbolos `Java_*`), então o casamento foi feito por **assinatura** + código Java.

| Classe Java | Biblioteca | Métodos |
|-------------|-----------|---------|
| `com.other.A` | `libfiioa-jni.so` | `func1(int,int,int)` `(III)I`, `func2(ByteBuffer,int)` `(ByteBuffer;I)I`, `func9(ByteBuffer)` `(ByteBuffer;)V`, `func3..func8`, `func10` |
| `com.other.AC` | `libfiioac-jni.so` | `acfunc1/acfunc2/acfunc4/acfunc9` — mesma ABI, instância estática |
| `com.fiio.NativeCdControl` | `libfiiocd-jni.so` | `AudioTrackRead/Seek/SetPerf/getSampleRate/getSector/getChannel/getPerf` — **leitura de CD (CDDA)** |

Detalhe forense: as classes do player vivem no pacote
**`com.example.root.checkappmusic`** (`FiioMediaPlayer`, `FiioAudioTrack`) — nome
de projeto de teste que ficou no build de produção. A UI usa
`com.fiio.music.*`, mas o motor de reprodução é o pacote de exemplo.

## 2. `FiioAudioTrack` — quem realmente abre o dispositivo

`com.example.root.checkappmusic.a` (fonte: `FiioAudioTrack.java`):

```java
a(int streamType, int rate, int channelMask, int encoding, int bufferSize, int mode)
    if (isUseUsbOutput) new n(...)      //  n = saída USB (UAC)
    else                AudioTrack(...) //  caminho interno
```

`[FW]` O caminho USB é uma classe separada (`s1.n`), escolhida por
`com.fiio.product.b.d().c().p()` — o mesmo teste de "USB Audio" que aparece em
todo o código.

## 3. Buffer por taxa (valores reais no código)

Para o encoding `10` (o caso comum do app), o cálculo é:

```java
AudioTrack.getMinBufferSize(rate, 12, 10);   // 12 = CHANNEL_OUT_STEREO
```

Depois há ajustes explícitos por taxa:

| Caso | Buffer |
|------|--------|
| 32k / 64k / 96k / 128k / 192k | 16 384 |
| idem, arquivo `flac` | 65 536 |
| FLAC 176,4 kHz 24-bit | 32 768 |
| FLAC 352,8 kHz 24-bit | 98 304 / 131 072 |
| 352,8 kHz (geral) | 65 536 |
| 176,4 kHz (geral) | 32 768 |
| padrão | `getMinBufferSize` |

## 4. Processamento: `libfiioac-jni` só entra em 4 taxas

`MediaManager` decide se usa o motor de processamento assim:

```java
if (!"MQA".equals(mimetype)
    && ("flac".equalsIgnoreCase(ext) || "wav".equalsIgnoreCase(ext))
    && (rate == 44100 || 48000 || 88200 || 96000)
    && AC.func2(sampleRate, encodingRate, path, length))
```

Ou seja: **MQA nunca passa pelo motor**, e fora de 44,1/48/88,2/96 kHz o app não
processa — vai direto. Isso casa exatamente com o ramo de "passagem direta" que
encontramos na HAL (`docs/20` §1).

No laço de reprodução:

```java
int n = a10.func2(byteBuffer, position) * 4;   // 4 bytes por amostra
this.J.func9(byteBufferN2);                    // entrega o segundo buffer
```

O fator `* 4` indica amostras de 32 bits na saída do processamento.

## 5. MQA

```java
this.J.func1(decodeType, 1, playerConfig.originSampleRate);   // init
this.K = this.J.func7();
this.L = this.J.func8();
```

`decodeType` é 1 ou 2 conforme o dispositivo e a opção
`com.fiio.music.mqa.spdif.option`:

| Contexto | decodeType |
|----------|-----------|
| SPDIF, opção = 0 | 1 ("decoder") |
| SPDIF, opção ≠ 0 | 2 ("authenticator") |
| normal | 1 |
| USB Audio com UA `e()==1` | 2 |
| USB Audio sem decoder | 1 |

Ou seja: **o app escolhe o tipo de decodificação MQA** e passa a taxa original;
a implementação fica na `libfiioaqm.so`, chamada pela HAL (docs/20 §6).

## 6. Propriedades que o app toca

`[FW]` Varredura de todas as strings `persist.*` no APK:

```
persist.music.DSD.format_spdif        (4×)
persist.sys.audio.output.select       (3×)
persist.sys.fiio.config               (1×)
persist.sys.fiio.config.pcm.sample    (1×)
persist.sys.fiio.config.dsd.native    (1×)
persist.sys.eq.exist                  (1×)
persist.sys.dsd2pcm.exist             (1×)
persist.sys.theme / persist.sys.locale
persist.tape.mode / persist.fiio.atmosphere_led_*
```

`[FW]` **O player não escreve** `persist.sys.all.to.dsd`,
`persist.sys.d2p.enable` nem `persist.sys.pcm2dsd.level`. Quem escreve deve ser
o app de configurações / serviço de sistema (`com.fiio.control` ou equivalente)
— `[?]` a confirmar quando o aparelho estiver disponível.

## 7. O que isso fecha

```
FiiOMusic (Java)
  ├─ FiioAudioTrack  → AudioTrack (interno)  ou  s1.n (USB)
  ├─ AC (libfiioac-jni) → EQ/processamento só em 44,1/48/88,2/96 e não-MQA
  ├─ A  (libfiioa-jni)  → init MQA (decodeType, taxa original), process, output
  └─ NativeCdControl    → leitura de CD (setores, rate por faixa)
        |
        v
   AudioFlinger → HAL (libfiioaudio) → kcontrol → dac_core → cs43198
```

O único elo que ainda não tem dono identificado é **quem escreve as
propriedades de DSD**. Todo o resto está fechado.

## 8. Aberto

| Item | Como fechar |
|------|-------------|
| Quem seta `persist.sys.all.to.dsd` / `d2p.enable` | procurar no `com.fiio.control`/settings e nas regras `on property:` |
| Significado dos `func3..func6` e `func10` | descompilar `libfiioa-jni.so` (Ghidra) |
| Encoding `10` do AudioTrack | conferir a constante no app (`AudioFormat`) |
| Se `s1.n` (USB) usa o mesmo protocolo UAC2 do init | ler a classe `n` |
