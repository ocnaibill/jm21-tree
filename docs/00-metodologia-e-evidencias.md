# 00 — Metodologia, ferramentas e registro de evidências

> Objetivo: garantir que qualquer conclusão deste laboratório possa ser
> reconstruída e contestada. Nada aqui vale "porque o autor lembrou".

## 1. Regra de ouro

Toda afirmação sobre o aparelho tem **tipo de evidência** e **local exato**
(arquivo, offset, comando). A escala usada:

| Marca | O que é | Como se contesta |
|-------|---------|------------------|
| `[FW]` | Observação direta em arquivo do firmware | Reextrair o arquivo e conferir |
| `[DRV]` | Observação em módulo `.ko` (strings/símbolos/mensagens) | `strings`, `readelf`, Ghidra |
| `[DT]` | Observação no FDT/DTBO aplicado | `tools/dt_dump.py --dump <n>` |
| `[PROP]` | Propriedade em `build.prop` | `grep` no prop |
| `[FAB]` | Alegação de terceiro | Só vira fato com evidência primária |
| `[HIP]` | Inferência de engenharia | Precisa de teste no dispositivo |
| `[?]` | Desconhecido declarado | Listado em `08-roadmap` |

Três regras práticas adotadas:

1. **Strings não são comportamento.** Uma string `DAC PO Gain` prova que o
   driver referencia o controle, não prova a faixa de ganho. Faixa de ganho
   exige ler a tabela no binário (fase seguinte) ou medir.
2. **Overlay não é vínculo resolvido.** No DTBO, `target = <0xffffffff>` e
   `phandle = 0xffffffff` são *placeholders* resolvidos pelo bootloader contra a
   DTB base. Número de barramento I2C e GPIO absoluto só se confirmam no
   `/proc/device-tree` do aparelho ou na DTB base.
3. **Nomes de nó podem mentir.** `cs43198@32` tem `reg = 0x33` e `cs43198@31`
   tem `reg = 0x30` `[DT]`. O `reg` é a fonte de verdade; o nome do nó é
   histórico. Anotado como divergência em `04-kernel-e-devicetree.md`.

## 2. Roteamento REA para este alvo

O alvo primário é **firmware OTA Android A/B** (não é app JS nem binário nativo
isolado). Rota adotada:

1. **Inventário do pacote** — `payload.bin` + `payload_properties.txt` +
   `care_map.pb` + `META-INF/com/android/metadata`.
2. **Extração de partições** — `payload-dumper-go` (repo `ssut`, compilado
   localmente com Go).
3. **Inspeção de filesystem** — `debugfs` (leitura ext4 sem root/mount).
4. **Análise de DTBO/FDT** — `tools/dt_dump.py` (parser próprio, sem deps).
5. **Análise de ELF/kernel module** — `readelf`, `strings`, `llvm-objdump -dr`
   (relocations resolvem os símbolos chamados); `pahole` lê o `.BTF`.
   Decompilador (Ghidra/IDA) segue dispensável até agora.
6. **APK/dex** — JADX 1.5.6 (`tools/bin/jadx`) para `services.jar`; `strings`
   para varredura rápida.

### Ferramentas e estado

| Ferramenta | Estado | Impacto |
|------------|--------|---------|
| `payload-dumper-go` | **resolvido** (compilado em `tools/bin`) | — |
| `avbtool` 1.3.0 | **resolvido** (AOSP `external/avb`, em `tools/bin`) | AVB/rollback lidos |
| `openssl` | presente | certificado do OTA lido |
| `jadx` 1.5.6 | **resolvido** (`tools/bin/jadx`) | `services.jar` decompilado |
| `pahole` / `bpftool` | presentes | BTF dos `.ko` → structs/enums |
| `llvm-objdump` | presente | disassembly aarch64 com relocations resolvidas |
| `ghidra` / IDA | ausente | pseudocódigo (ainda não necessário) |
| `dtc` | ausente | substituído por `tools/dt_dump.py` |
| `binwalk` / `unblob` | ausente | não necessário nesta fase |
| `aapt2` | ausente | ler `AndroidManifest` (contornado com `strings`) |
| `adb` | **presente** | pronto para a fase com o aparelho |
| `protoc` | presente | útil para `care_map.pb` |

Nenhuma dessas ausências impede a fase atual. JADX e Ghidra entram na fase de
decompilação (`08-roadmap`, F3/F4).

## 3. Ambiente

- Host Linux, 928 GB no volume `/home` (497 GB livres antes da extração).
- Python 3.14.8 **sem `pip`** — por isso as ferramentas próprias não usam
  dependências externas.
- Go disponível → `payload-dumper-go` compilado do fonte
  (`v0.0.0-20260923043722-c3a50ba8d784`).
- Extração: 19 imagens, ~4,9 GB em `dumps/fw-1.1.1/`.
- Recortes de análise: `analysis/fw-1.1.1/` (~130 MB, a maior parte APKs).

## 4. Reprodução (do zero)

```bash
# 1. ferramenta de payload
GOBIN="$PWD/tools/bin" go install github.com/ssut/payload-dumper-go@latest

# 1b. avbtool oficial (AOSP external/avb)
curl -sS "https://android.googlesource.com/platform/external/avb/+/refs/heads/main/avbtool.py?format=TEXT" \
  | base64 -d > tools/bin/avbtool.py
python3 tools/bin/avbtool.py version    # 1.3.0

# 2. listar partições antes de extrair
./tools/bin/payload-dumper-go -l fw/JM21-update-1.1.1/payload.bin

# 3. extrair tudo (8 threads)
./tools/bin/payload-dumper-go -o dumps/fw-1.1.1 -c 8 fw/JM21-update-1.1.1/payload.bin

# 4. ler um arquivo de dentro de uma imagem, sem montar
debugfs -R "dump /etc/audio/audio_policy_configuration.xml /tmp/policy.xml" \
  dumps/fw-1.1.1/vendor.img

# 5. listar/apagar overlay de device tree
./tools/dt_dump.py dumps/fw-1.1.1/dtbo.img --list
./tools/dt_dump.py dumps/fw-1.1.1/dtbo.img --grep "cs43198|fpga"

# 6. strings de bibliotecas
strings -n 6 analysis/fw-1.1.1/vendor/lib64/libfiioaudio.so | sort -u
```

## 5. Ledger de evidências (firmware 1.1.1)

Hashes em `analysis/fw-1.1.1/SHA256SUMS.txt`. Identidade do pacote:

| Campo | Valor |
|-------|-------|
| `MODEL_NAME` | `FiiO JM21` |
| `FILE_SIZE` (payload) | 1 642 838 532 |
| `METADATA_SIZE` | 130 679 |
| `ota-type` | `AB` |
| `pre-device` | `bengal_515` |
| `post-sdk-level` | 33 |
| `post-security-patch-level` | `2023-02-05` |
| `post-build` | `qti/bengal_515/bengal_515:13/TKQ1.230110.001/eng.fiio.20260428.144644:user/dev-keys` |
| `post-build-incremental` | `eng.fiio.20260428.144644` |
| `post-timestamp` | 1 777 358 737 (≈ 2026-04-28) |
| `ro.product.version` | `1.1.1` `[PROP]` |
| `ro.vendor.build.version.incremental` | `eng.fiio.20260428.154610` `[PROP]` |
| `apex_info.pb` | 0 bytes (nenhum APEX no payload) `[FW]` |

**Atestado de integridade:** os 5 hash descriptors do `vbmeta`
(`boot`, `dtbo`, `init_boot`, `recovery`, `vendor_boot`) foram recalculados
(`SHA256(salt || imagem)`) e **batem 5/5**. O material extraído é
byte-idêntico ao que o dispositivo verifica. Saídas: `analysis/fw-1.1.1/avb-*.txt`
e `ota-cert.txt`.

## 6. Fontes externas usadas

| Fonte | Uso |
|-------|-----|
| [FiiO JM21 — parâmetros oficiais](https://www.fiio.com/jm21_parameters) | potência, SNR, taxas máximas por caminho, saídas, modos |
| [Fórum FiiO — tópico de firmware do JM21](https://forum.fiio.com/note/showNoteContent.do?id=202412181641298410115&tid=17) | changelog e links oficiais completo × incremental |
| [Cirrus Logic CS43198 — datasheet DS1156F2](https://statics.cirrus.com/pubs/proDatasheet/CS43198_DS1156F2.pdf) | mapa de registradores, escala de volume, filtros, NOS |
| [bkerler/edl](https://github.com/bkerler/edl) e [bkerler/Loaders](https://github.com/bkerler/Loaders/issues/97) | viabilidade de EDL/Sahara |
| `sound/soc/codecs/cs43130.c` (upstream Linux) | driver de referência do CS43198 (regmap 24 bits, TLV de volume, bits de filtro) |
| Review do JM21 citando FPGA Gowin GW1NZ-1 | `[EXT]` part number e topologia analógica — não verificado por nós |

O PDF do datasheet fica em `analysis/datasheets/` (fora do git, por licença) e
o texto extraído é usado só como referência de leitura.

**Nota de utilidade:** `alldatasheet.com` com o termo "JM21" **não serve** — ele
retorna a família NJM21xx (op-amps e reset ICs da Nisshinbo), sem relação com o
DAP. Para este projeto os datasheets que importam são CS43198, SGM8262 e a
documentação do SM6225.

## 7. O que este dossiê **não** prova

- Não prova que o FPGA converte/reamostra. O caminho FPGA→DAC é **inferido** de
  três módulos e das structs de configuração, não observado em execução.
- Não prova a potência de saída: os números do §`01` §6 são do fabricante, com
  condições de teste declaradas (High gain, USB DAC), não medidos por nós.
- Não cobre a partição `userdata` (não vem no OTA) nem dados de calibração
  gravados em fábrica.

## 7. Higiene

- `fw/`, `dumps/` e binários não são versionados.
- Nenhuma ação de escrita no aparelho foi executada.
- Toda extração é reproduzível a partir do ZIP original.
