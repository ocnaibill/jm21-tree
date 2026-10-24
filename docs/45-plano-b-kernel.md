# 45 — Plano B: kernel próprio + módulos vendor (issue #19)

> Objetivo: descobrir se dá para ter um kernel compilado por nós (CAF público)
> que **carregue os `.ko` da FiiO**, sem depender do código-fonte deles.

## 1. O que já temos

| Item | Valor |
|------|-------|
| Kernel | `5.15.41-android13-8-g9ded8564ff52-dirty` |
| Compilador | clang **14.0.7** (Android r450784e), LLD 14.0.7 |
| Vermagic | `5.15.41-g9ded8564ff52-dirty SMP preempt mod_unload modversions aarch64` |
| `.config` | **`/proc/config.gz` disponível** → salvo em `analysis/kernel/config-5.15.41-jm21.txt` (6.934 linhas) |
| Assinatura | `CONFIG_MODULE_SIG=y`, **`MODULE_SIG_FORCE` não setado**, sem `module.sig_enforce` no cmdline → **módulo sem assinatura é aceito** (os vendor aparecem com taint `OE`) |
| LTO/CFI | `LTO_CLANG_FULL=y`, `CFI_CLANG=y`, `CFI_CLANG_SHADOW=y` |
| Modversions | `CONFIG_MODVERSIONS=y` (o `.ko` carrega `__versions` com CRCs) |

## 2. A ideia central (e por que ela pode funcionar)

Com `MODVERSIONS`, o kernel recusa um módulo se o **CRC** de um símbolo usado
não bater. O CRC é gerado pelo `genksyms` a partir da **assinatura de tipo** do
símbolo — **não do corpo da função**.

`[HIP]` Consequência: uma árvore 5.15 **mais nova** (ex.: 5.15.180) com o
**mesmo `.config`** pode produzir os mesmos CRCs, desde que as estruturas e
protótipos exportados não tenham mudado. O ponto sensível é `module_layout`
(CRC do `struct module`): se a FiiO não alterou a struct, ele bate.

## 3. Árvores candidatas (GitHub)

| Repo | Observação |
|------|------------|
| `MvgWooF/msm-5.15_bengal` | 5.15.**180**, com `bengal_GKI.config`; clone raso feito (1,5 GB) |
| `LineageOS/android_kernel_motorola_sm6225` | base CAF sm6225 (khaje), branch `lineage-24.0` |
| `AndroDumb/android_kernel_motorola_sm6225_5.15` | descrição "bengal family (khaje)"; repo vazio no momento |

O commit `9ded8564ff52` **não existe publicamente** (busca no GitHub: 0) — é
interno da FiiO. Por isso o plano é **forçar o vermagic**:

1. `Makefile`: `SUBLEVEL = 41`, `EXTRAVERSION =`.
2. `CONFIG_LOCALVERSION_AUTO=n` e `CONFIG_LOCALVERSION="-g9ded8564ff52-dirty"`.
   Isso reproduz a string de vermagic exata que o kernel compara.

## 4. Passos

1. **Toolchain**: baixar `clang-r450784e` (AOSP prebuilts, ~1 GB) + LLD da mesma
   versão.
2. **Árvore**: clonar a candidata e aplicar o `.config` do aparelho.
3. **Build**: `make ARCH=arm64 LLVM=1` (LTO full é caro — horas; precisa de
   ~20 GB).
4. **Teste decisivo**: compilar um **módulo trivial** e `insmod` no aparelho.
   - Carrega → os CRCs batem; o caminho está aberto.
   - `disagrees about version of symbol module_layout` → a struct mudou; aí é
     Plano C (ou GPL).
5. **Se carregar**: tentar carregar um `.ko` da FiiO (`cs43198.ko`) no kernel
   nosso, num boot por `fastboot boot` (sem gravar).

## 5. Por que isso importa

Se o passo 4 funcionar, ganhamos:
- capacidade de compilar módulos novos (drivers customizados);
- um kernel com debug (`ftrace`, `kprobes`) para observar o stack;
- independência do GPL para a **ABI**.

Se falhar, a resposta é objetiva: a única rota é o código-fonte (GPL) ou a
reimplementação clean-room (Plano C, `docs`/issue #20).

## 6. Custo

- Download do toolchain: ~1 GB.
- Clone da árvore: 1,5 GB.
- Build com LTO full: ~20 GB e horas de CPU.

Por isso o passo 2 pode ser feito já, mas o build completo deve ser agendado.

## 7. Resultado (medido)

### Build
- Árvore pública 5.15.180 com o `.config` do aparelho, **LTO thin** (o full
  estourava os 15 GB de RAM com `-j16`), `-j8`.
- Vermagic: o `setlocalversion` acrescentava `+`; a correção é compilar com a
  variável **`LOCALVERSION=`** definida (vazia), o que desliga o `+`. Resultado:
  `5.15.41-g9ded8564ff52-dirty` — **idêntico ao aparelho**.

### Teste 1 — módulo trivial no kernel da FiiO
```
insmod hello.ko   -> rc=0
dmesg: jm21abi: loaded
lsmod: hello  16384  0
rmmod hello       -> jm21abi: unloaded
```
`[FATO]` O kernel da FiiO aceitou um módulo compilado na árvore pública →
**vermagic e CRCs de modversions batem**. (Só o BTF do módulo falhou: `-22`,
opcional.)

### Teste 2 — CRCs exigidos pelos módulos da FiiO
`tools/abi-check.py` compara a seção `__versions` de cada `.ko` com o nosso
`Module.symvers` (15 233 símbolos):

| Módulo | Símbolos | CRC errado | Faltando |
|--------|----------|------------|----------|
| `fiio_primary_modules.ko` | 47 | **0** | **0** |
| `anolog_board_jm21.ko` | 25 | **0** | 10 |
| `cs43198.ko` | 18 | **0** | 6 |
| `dac_core_module.ko` | 39 | **0** | 13 |
| `gw-fpga.ko` | 55 | **0** | 11 |
| `fpga_audio_interface.ko` | 15 | **0** | 9 |

`[FATO]` **Nenhum CRC divergente.** Os símbolos faltantes são os exports da
própria FiiO (`fiio_device_*`, `fiio_regmap_*`, `fpga_*`, `report_playing_info`,
`dac_set_gpio_value*`), fornecidos pelo `fiio_primary_modules.ko` — que é
**100 % compatível** e é o primeiro a carregar.

### Conclusão
O **Plano B é viável**: um kernel compilado por nós (CAF público + config do
aparelho) tem a **mesma ABI** dos módulos vendor. O próximo passo é bootar esse
kernel por `fastboot boot` (imagem de boot com o nosso `Image.gz` + ramdisk/DTB)
e carregar o stack FiiO.
