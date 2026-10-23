# 09 — Glossário

Termos usados neste dossiê, com o sentido específico do projeto.

## Plataforma e firmware

| Termo | Definição |
|-------|-----------|
| **Khaje** | Codinome Qualcomm do SoC SM6225 (Snapdragon 680) |
| **Bengal 515** | Nome da árvore vendor/QSSI e do `pre-device` do OTA — não é o SoC |
| **QSSI** | *Qualcomm Single System Image*: `system`/`system_ext`/`product` compartilhados entre variantes |
| **QSSI × vendor split** | Separação entre partições da Qualcomm (qssi) e da BSP (bengal_515) |
| **A/B (seamless)** | Dois slots de boot; OTA grava no slot inativo |
| **`payload.bin`** | Pacote de atualização do `update_engine` (manifesto + blobs) |
| **`super`** | Partição física que hospeda partições lógicas dinâmicas (não vem no OTA) |
| **`init_boot`** | Partição do ramdisk genérico de `init` (Android 13+) |
| **`vendor_boot`** | Ramdisk vendor + DTBs base |
| **DTBO** | *Device Tree Blob Overlay*: camada de DT aplicada em runtime |
| **`-dirty`** | Sufixo de versão indicando árvore com alterações não commitadas |
| **vermagic** | Assinatura de ABI do módulo (`versão + flags + arch`) |
| **AVB** | *Android Verified Boot*: cadeia de assinatura das partições |
| **`dev-keys`** | Assinatura com chaves de desenvolvimento, não de produção |
| **rollback index** | Contador anti-downgrade do AVB |

## Áudio

| Termo | Definição |
|-------|-----------|
| **HAL** | *Hardware Abstraction Layer*: aqui, `audio.primary.bengal.so` (HIDL 7.0) |
| **HIDL / AIDL** | IDLs de interface Android; este aparelho usa HIDL 7.0 |
| **AudioFlinger** | Serviço de mixagem do Android (system) |
| **PAL** | *Platform Audio Layer*: camada de stream da Qualcomm |
| **DPA** | Nome FiiO do seu caminho de áudio proprietário (`persist.sys.fiio.config=FiiODPA`) |
| **dummy DAI** | DAI ASoC "fake" (`fiio_snd_soc_dummy_dai.ko`) que representa o caminho Android |
| **CS43198** | DAC da Cirrus Logic, 32-bit, com filtros digitais e suporte a DSD |
| **Dual DAC** | Dois chips; divisão pode ser L/R ou paralela |
| **DoP** | *DSD over PCM*: DSD empacotado em frames PCM |
| **DSD nativo** | DSD enviado sem empacotamento PCM |
| **Noise shaping** | Modelagem de ruído na conversão PCM→DSD |
| **MQA** | Master Quality Authenticated (codec/DRM de áudio) |
| **PO Gain** | Ganho de saída (*phone out*) |
| **SGM8262** | Amp op da SG Micro (2 unidades no JM21) |
| **SE / BAL** | *Single-ended* (3,5 mm) / *balanced* (4,4 mm) |
| **MCLK** | Clock mestre do DAC (22,5792 / 45,1584 / 90,3168 MHz) |
| **UAC** | *USB Audio Class*: modo DAC USB |
| **LHDC** | Codec Bluetooth de alta taxa (alternativa ao LDAC) |
| **kcontrol / mixer control** | Controle ALSA exposto ao userspace (`tinymix`) |
| **`mixer_paths_*.xml`** | Mapa de rotas e controles ALSA do vendor |
| **`audio_policy_configuration.xml`** | Política de portas/formatos/rotas do Android |

## Engenharia reversa

| Termo | Definição |
|-------|-----------|
| **REA** | *Reverse Engineer Anything*: skill/fluxo de análise baseada em evidência |
| **Evidência** | Observação registrada com origem (arquivo, offset, comando) |
| **Inferência** | Conclusão derivada, marcada `[HIP]`, a validar |
| **Overlay** | Fragmento de DT aplicado sobre a base |
| **`phandle`** | Referência numérica a outro nó do DT |
| **`0xffffffff` em overlay** | Placeholder resolvido na aplicação do overlay |
| **`debugfs`** | Ferramenta e2fsprogs para ler ext4 sem montar |
| **FDT** | *Flattened Device Tree* (formato binário do DT) |
| **bitsream** | Arquivo de configuração do FPGA (`.fw`) |
| **Gowin** | Fabricante do FPGA (`gowin,fpga_i2c`, `gw-fpga`) |

## Convenções deste dossiê

| Marca | Significado |
|-------|-------------|
| `[FW]` | observado em arquivo do firmware |
| `[DRV]` | observado em módulo de kernel |
| `[DT]` | observado no device tree |
| `[PROP]` | observado em `build.prop` |
| `[FAB]` | alegação do fabricante, não verificada |
| `[HIP]` | hipótese |
| `[?]` | desconhecido declarado |
