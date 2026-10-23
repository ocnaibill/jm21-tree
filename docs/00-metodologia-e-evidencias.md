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
5. **Análise de ELF/kernel module** — `readelf`, `strings`, `objdump`;
   decompilação com Ghidra/IDA **ainda não instalados**.
6. **APK/dex** — `unzip` + `strings`; JADX **ainda não instalado**.

### Ferramentas e estado

| Ferramenta | Estado | Impacto |
|------------|--------|---------|
| `payload-dumper-go` | **resolvido** (compilado em `tools/bin`) | — |
| `avbtool` 1.3.0 | **resolvido** (AOSP `external/avb`, em `tools/bin`) | AVB/rollback lidos |
| `openssl` | presente | certificado do OTA lido |
| `jadx` | ausente | decompilar `FiiOMusic.apk`, `framework.jar`, `services.jar` |
| `ghidra` / IDA | ausente | pseudocódigo de `libfiioaudio.so`, `.ko` |
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

## 6. O que este dossiê **não** prova

- Não prova que o JM21 usa os dois cs43198 em modo mono diferencial nem que o
  FPGA converte/reamostra. O caminho FPGA→DAC é **inferido** de três módulos e
  duas propriedades, não observado em execução.
- Não prova nenhuma taxa máxima real de PCM/DSD. As propriedades
  (`pcm.sample=768000`, `dsd.native=256`) dizem o que o sistema **oferece**.
- Não prova a potência de saída (280 mW / 700 mW continuam `[FAB]`).
- Não cobre a partição `userdata` (não vem no OTA) nem dados de calibração
  gravados em fábrica.

## 7. Higiene

- `fw/`, `dumps/` e binários não são versionados.
- Nenhuma ação de escrita no aparelho foi executada.
- Toda extração é reproduzível a partir do ZIP original.
