# 04 — Kernel, módulos e device tree

## 1. Kernel real

`[DRV]` `vermagic` de 12 módulos FiiO (`cs43198`, `dac_core_module`,
`anolog_board_jm21`, `fiio_*`, `gw-fpga`, `fpga_*`):

```
5.15.41-g9ded8564ff52-dirty SMP preempt mod_unload modversions aarch64
```

Interpretação:

| Campo | Significado |
|-------|-------------|
| `5.15.41` | base Linux |
| `g9ded8564ff52` | commit de base (código CAF/Qualcomm) |
| `-dirty` | árvore com alterações não commitadas na build |
| `preempt` | `CONFIG_PREEMPT` (não é `PREEMPT_RT`, mas é preemptivo) |
| `modversions` | `CONFIG_MODVERSIONS=y` → assinatura CRC por símbolo |
| `aarch64` | 64-bit |

**Correção do dossiê original:** era 5.4; o correto é **5.15.41**. Isso muda a
escolha de árvore para qualquer kernel customizado: `msm-5.15` (não `msm-5.4`).

`[?]` O commit `9ded8564ff52` não foi resolvido contra um repositório público.
Próximo passo: tentar casar com `android13-5.15` / `msm-5.15` CAF e medir o
tamanho do delta.

## 2. Imagens de boot

Headers lidos diretamente (`[FW]`):

| Imagem | Magic | Header ver. | Observação |
|--------|-------|-------------|------------|
| `boot.img` | `ANDROID!` | **4** | kernel + ramdisk genérico |
| `init_boot.img` | `ANDROID!` | **4** | ramdisk de `init` (Android 13) |
| `recovery.img` | `ANDROID!` | **4** | recovery standalone (A/B) |
| `vendor_boot.img` | `VNDRBOOT` | **4** | page 4096 |

`vendor_boot.img`:

```
header_size        = 2128
vendor_ramdisk     = 7 301 426 bytes
dtb_size           = 1 006 645 bytes
dtb_addr           = 0x1F00000
cmdline            = video=vfb:640x400,bpp=32,memsize=3072000 log_buf_len=2M
                     bootconfig buildvariant=user
```

O `vendor_boot` carrega **a DTB base**. Extração:

```bash
python3 - <<'EOF'
import struct
d=open("dumps/fw-1.1.1/vendor_boot.img",'rb').read()
hdr=d[:2128]; page=4096
rsz=struct.unpack('<I',hdr[24:28])[0]; dsz=struct.unpack('<I',hdr[2100:2104])[0]
off=(page+rsz+page-1)//page*page
open("analysis/fw-1.1.1/base.dtb","wb").write(d[off:off+dsz])
EOF
./tools/dt_dump.py analysis/fw-1.1.1/base.dtb --tree > analysis/fw-1.1.1/base-dtb.dts
```

## 3. DTB base — 5 variantes concatenadas

`[FW]` Os 1 006 645 bytes do `dtb_size` contêm **5 DTBs** consecutivos:

| # | Offset | Tamanho | Model |
|---|--------|---------|-------|
| 0 | 0 | 265 319 | Qualcomm Technologies, Inc. **Khaje** SoC |
| 1 | 265 319 | 265 422 | Qualcomm Technologies, Inc. **Khajeg** SoC |
| 2 | 530 741 | 58 769 | Qualcomm Technologies, Inc. **Khajep** QRD |
| 3 | 589 510 | 209 543 | Qualcomm Technologies, Inc. **Khajep** SoC |
| 4 | 799 053 | 207 592 | Qualcomm Technologies, Inc. **Khajeq** SoC |

O bootloader escolhe a base pelo `board-id`/`soc-id` e depois aplica o overlay
do DTBO. `[?]` Qual das 5 é usada no JM21 (provavelmente `Khaje` puro, mas
depende do SKU de modem/PMIC). Confirmar no aparelho:

```bash
adb shell cat /proc/device-tree/model
adb shell ls /proc/device-tree/soc@0 | grep i2c
```

Buses I2C visíveis na DTB base `[FW]` (`analysis/fw-1.1.1/base-dtb.dts`):

```
i2c@4a80000   i2c@4a84000   i2c@4a88000
```

## 4. DTBO — 42 overlays

`[FW]` `dtbo.img`: 8 388 608 bytes, header `0xd7b7ab1e`, 42 entradas.

Famílias de overlay (`--list`):

| Faixa | Conteúdo |
|-------|----------|
| 0–10 | `qcom,khaje*` (idp/qrd/atp) — base Qualcomm + `fiio,dac-core` |
| 11–41 | `qcom,khajeg/khajep/khajeq*` — as três variantes derivadas |
| **12, 22, 31, 40** | overlays que trazem `cirrus,cs43198` + `fiio,anolog_board` |
| **40** | **overlay do JM21** (111 608 bytes, o mais completo) |

`[FW]` Overlay 40, `__symbols__`:

```
cs43198_l  → /fragment@20/__overlay__/cs43198@32
cs43198_r  → /fragment@20/__overlay__/cs43198@31
fpga       → /fragment@20/__overlay__/fpga@36
fpga_audio_interface_hal → /fragment@22/__overlay__/fpga_audio_interface_hal
spitest    → /fragment@21/__overlay__/spitest@0
```

Árvore completa já materializada em `analysis/fw-1.1.1/dtbo-jm21-full.dts`.

### 4.1 Fragmento do barramento I2C (`fragment@20`)

```
qcom,clk-freq-out = 400000        (400 kHz)
fpga@36     compatible = "gowin,fpga_i2c"           reg = 0x36
cs43198@32  compatible = "cirrus,cs43198"           reg = 0x33  id = 0
cs43198@31  compatible = "cirrus,cs43198"           reg = 0x30  id = 1
```

`[DT]` Divergência registrada: o nome do nó (`@32`/`@31`) não bate com `reg`
(`0x33`/`0x30`). **Vale o `reg`.** Confirmar com `i2cdetect`.

### 4.2 Fragmento SPI do FPGA (`fragment@21`)

```
gw-fpga@0   compatible = "qcom,gw-fpga"
            spi-max-frequency = 1000000          (1 MHz)
            spi-cpol; spi-cpha;                  (modo 3)
            qcom,fpga-cs-pin = <gpio 17 0>
            gpio,fpga_pwr_en = <gpio 3 0>
            gw-fpga-fw-name = "gw_fpga_firmware_jm21.fw"
spitest@0   compatible = "fiio,spitest"  status = "disable"
```

O `spitest@0` (spi-max-frequency 4 800 000 `0x493e00`) existe mas está
**desabilitado** — ferramenta de bancada da FiiO.

### 4.3 Placa analógica (`fragment@22`)

```
anolog_board  compatible = "fiio,anolog_board"
  gpio,dac_rst   = <gpio 2>
  gpio,out_sel   = <gpio 29>
  gpio,ang_pwr   = <gpio 75>
  gpio,dac_pwr   = <gpio 79>
  gpio,amp_pwr   = <gpio 85>
  gpio,amp2_pwr  = <gpio 67>
  gpio,sw_en     = <gpio 86>

fpga_audio_interface_hal  compatible = "fiio,fpga-audio-interface-hal"

fiio_headset_jack  compatible = "fiio,jack_det"
  hs-det-delay-ms      = 150
  hs35_det_gpio        = <gpio 102>
  bal44_det            = <gpio 103>
  io-channels          = <&adc 18>   nome "dc_det1"
  hs35-det-threshold   = 1
  ...
```

### 4.4 DAC core (`fragment@41`)

```
fiio,dac-core  compatible = "fiio,dac-core"  status = "okay"
```

Nó sem propriedades: é o ponto de registro do plataforma driver
(`dac_core_module.ko`).

## 5. Ordem de carga dos módulos

`[FW]` `vendor_dlkm/lib/modules/modules.load`, na ordem relevante:

```
fiio_primary_modules.ko
fiio-charger-manager.ko
gw-fpga.ko
fpga_audio_interface.ko
fpga_interface.ko
fiio_headset_jack.ko
fiio_wakeup.ko
fiio_snd_soc_dummy_dai.ko
dac_core_module.ko
cs43198.ko
fiio_gpio_debug_module.ko
anolog_board_jm21.ko
fiio_config.ko
fiio_underlay_modules.ko
fpga-mgr.ko
snd-usb-audio-qmi.ko
snd_event_dlkm.ko
```

Leitura: `gw-fpga` sobe **antes** do DAC; o `dac_core` sobe antes do
`cs43198`; `anolog_board_jm21` sobe **depois** do `dac_core` (o que explica a
mensagem `get anolog_board module failed!` em cenários de ordem errada).
`snd_event_dlkm.ko` aparece duplicado no arquivo (inofensivo, mas é um cheiro de
árvore vendor editada à mão).

`modules.softdep` não tem nada específico de áudio — as dependências FiiO são
resolvidas por *notifier* em runtime, não por softdep.

## 6. Configuração do kernel (extraída)

`[FW]` O `boot.img` traz o kernel **sem compressão** (Image arm64 com *stub*
EFI — os primeiros bytes são `MZ`), e a config está embutida em `IKCFG_ST` …
`IKCFG_ED` (gzip).

```python
import gzip
d = open('dumps/fw-1.1.1/boot.img','rb').read()
i, j = d.find(b'IKCFG_ST'), d.find(b'IKCFG_ED')
open('analysis/fw-1.1.1/kernel.config','wb').write(gzip.decompress(d[i+8:j]))
```

`[FW]` Banner completo:

```
Linux version 5.15.41-android13-8-g9ded8564ff52-dirty (build-user@build-host)
  (Android (8508608, based on r450784e) clang version 14.0.7, LLD 14.0.7)
  #1 SMP PREEMPT Tue Apr 28 08:23:10 UTC 2026
```

Isso fecha a questão do commit: a base é a **`android13-8`** do CAF, tag
`g9ded8564ff52`, compilada com clang 14.0.7 da toolchain Android.

`[FW]` Config (6 934 linhas, `analysis/fw-1.1.1/kernel.config`):

| Opção | Valor | Por que importa |
|-------|-------|-----------------|
| `CONFIG_PREEMPT` | y | kernel preemptivo |
| `CONFIG_MODULES` / `MODVERSIONS` | y / y | `.ko` com CRC por símbolo |
| `CONFIG_MODULE_SIG_ALL` | y | módulos assinados na build |
| `CONFIG_MODULE_SIG_FORCE` | **ausente** | assinatura **não é exigida** para carregar |
| `CONFIG_LTO_CLANG_FULL` | y | LTO completo — funções inlined/fundidas |
| `CONFIG_CFI_CLANG` / `CFI_CLANG_SHADOW` | y / y | *forward-edge CFI*, daí os símbolos `.cfi_jt` |
| `CONFIG_TRIM_UNUSED_KSYMS` | y | ksymtab enxuta |
| `CONFIG_KALLSYMS` / `KALLSYMS_ALL` | y / y | todos os símbolos no kallsyms |
| `CONFIG_RANDOMIZE_BASE` | y | KASLR |
| `CONFIG_SHADOW_CALL_STACK` | y | *back-edge* CFI |
| `CONFIG_STACKPROTECTOR` | y | canário |
| `CONFIG_SECURITY_SELINUX` | y | SELinux |
| `CONFIG_DM_VERITY` | y | verity (casa com o AVB) |
| `CONFIG_IKCONFIG` | y | permitiu esta extração |
| `CONFIG_DEBUG_INFO` | y | compilado com debug (mas o `vmlinux` não vem no pacote) |
| `CONFIG_KASAN` | **y** | sanitizer de memória **ligado em build de produção** — incomum, cheiro de build de engenharia |
| `CONFIG_SND_USB_AUDIO` | y | áudio USB **built-in**, não módulo |

`[FW]` Só **dois** módulos in-tree: `zsmalloc` e `zram`. Todo o resto é `=y`, e
os `.ko` de `vendor_dlkm` são módulos **out-of-tree** compilados contra essa
árvore — por isso não existe `CONFIG_SND_SOC_CS43198` no config.

### No que isso muda a engenharia reversa

1. **LTO + CFI**: decompilar `.ko` vai gerar código com chamadas indiretas
   mediadas por *jump tables* CFI. Não estranhar `foo.cfi_jt` nem funções
   fundidas. Se Ghidra travar no reconhecimento, desligar a análise de CFI e
   seguir os stubs.
2. **`TRIM_UNUSED_KSYMS`**: a lista de símbolos exportados é mínima — bom sinal:
   o que sobrou ali é o que os módulos realmente usam.
3. **`MODULE_SIG` sem `MODULE_SIG_FORCE`**: tecnicamente um `.ko` não assinado
   poderia carregar, *se* o SELinux e o dm-verity permitirem. Não é o caminho
   recomendado (o `vendor_dlkm` é verity-protegido).
4. **`KASAN=y`**: se aparecer `kasan` no dmesg do aparelho, é esperado.

## 7. Superfície de RE do kernel

Ordem sugerida de análise (do mais informativo ao menos):

| Alvo | Por quê | Ferramenta |
|------|---------|------------|
| `cs43198.ko` | tabela de registradores, `volume_table`, filtros, MCLK | Ghidra (ELF aarch64) |
| `dac_core_module.ko` | contrato de ioctl, máquina de estados de modo | Ghidra |
| `anolog_board_jm21.ko` | sequência de energia/reset, `gain_table` | Ghidra |
| `gw-fpga.ko` | protocolo SPI do FPGA, load de bitstream | Ghidra + lógica |
| `fiio_snd_soc_dummy_dai.ko` | o que o DAI dummy faz de fato | Ghidra |
| `fiio_headset_jack.ko` | thresholds reais de detecção/proteção | Ghidra |
| `fiio_config.ko` | formato da partição `fiioconfig` | Ghidra + dump |

Bônus: como `cs43198.ko` é módulo GPL com `modversions`, os **CRCs de símbolos**
e a tabela `__ksymtab` ficam no ELF e ajudam a reconstruir assinaturas sem
adivinhação.

**Melhor ainda:** todos os `.ko` FiiO carregam `.BTF` com nomes de função,
structs e enums. Antes de abrir qualquer decompilador, leia
**[`10-abi-kernel-fiio.md`](10-abi-kernel-fiio.md)** — grande parte da estrutura
já está recuperada, e o disassembly passa a ser trabalho de lógica, não de
adivinhação.

## 8. Perguntas abertas

1. `[?]` Commit exato da base `9ded8564ff52` e tamanho do delta FiiO.
2. `[?]` Qual das 5 DTB base é aplicada no JM21.
3. `[?]` Número do barramento I2C onde estão `cs43198` e `fpga@36`.
4. `[?]` Conteúdo da partição `fiioconfig` (calibração? serial? modo de ganho?).
5. `[?]` Se `CONFIG_IKCONFIG` está ligado (dá config pronta).
6. `[?]` O `anolog_board_jm21.ko` é específico do JM21 — é o melhor lugar para
   achar constantes de timing do hardware.
