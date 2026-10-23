# Dossiê de Engenharia Reversa e Desenvolvimento — FiiO JM21

> Índice geral do laboratório. Cada seção resume o estado atual e aponta para o
> documento temático em `docs/`, onde estão os detalhes, comandos e evidências.
>
> Estado: **fase 0 — análise offline do firmware** (JM21 ainda não conectado).
> Firmware de referência: `JM21-update-1.1.1` (baseline versionado do dump).

---

## Legenda de evidência

Toda afirmação neste dossiê carrega a origem. Sem marcador, o dado é derivado de
cálculo ou de documento público e está explicitado no texto.

| Marca | Significado |
|-------|-------------|
| `[FW]` | Lido diretamente de um arquivo do firmware (`img`, `xml`, `prop`, `apk`) |
| `[DRV]` | Lido de módulo de kernel (`.ko`) — strings, símbolos, mensagens |
| `[DT]` | Lido do device tree / DTBO extraído |
| `[PROP]` | Propriedade Android observada em `build.prop` |
| `[FAB]` | Alegação do fabricante ou de review — **não verificada** |
| `[HIP]` | Hipótese de engenharia, a validar no dispositivo |
| `[?]` | Desconhecido / pendência aberta |

---

## Resumo executivo (o que mudou em relação à primeira versão)

1. **O firmware está em mãos e foi extraído.** `fw/JM21-update-1.1.1.zip`
   (1 642 845 150 bytes) contém um OTA **A/B** com `payload.bin` de
   1 642 838 532 bytes. As 19 partições foram extraídas para `dumps/fw-1.1.1/`.
2. **Android 13 (SDK 33)**, build `qti/bengal_515/bengal_515:13/TKQ1.230110.001/
   eng.fiio.20260428.144644:user/dev-keys` `[FW]`, patch de segurança
   **2023-02-05** `[FW]`.
3. **Kernel real é 5.15.41**, não 5.4:
   `vermagic=5.15.41-g9ded8564ff52-dirty SMP preempt mod_unload modversions aarch64`
   `[DRV]`. A árvore tem marca `-dirty`, ou seja, patches locais aplicados por
   cima do tag CAF.
4. **SoC é `khaje` (SM6225)**, mas a árvore vendor é `bengal_515` — os dois nomes
   convivem no firmware e não são sinônimos `[DT]` `[PROP]`.
5. **A HAL de áudio real é `audio.primary.bengal.so` (HIDL 7.0)**, não
   `audio.primary.sm6225.so` `[FW]`. A FiiO injetou símbolos próprios nela.
6. **O caminho de áudio tem um FPGA Gowin no meio** (`gw-fpga.ko`,
   `fpga_audio_interface.ko`, firmware `gw_fpga_firmware_jm21.fw`) `[DRV]` `[DT]`.
   Isso não estava no dossiê original e muda o modelo mental do fluxo de áudio.
7. **Os dois CS43198 são controlados por I2C** em 0x30 e 0x33, com um driver
   dedicado (`cs43198.ko`) que expõe filtros digitais, balanço, ganho PO e
   volume em dB `[DT]` `[DRV]`.
8. **Assinatura `dev-keys`** (não `release-keys`) `[FW]` — implicação direta para
   AVB, flashing e viabilidade de ROM customizada.
9. **AVB lido e dump validado.** `vbmeta` = SHA256_RSA4096, flags 0 (verity e
   verificação ligadas), rollback index **0**; `vbmeta_system` = RSA2048,
   rollback **1 675 555 200** (2023-02-05 em epoch). Os 5 hash descriptors
   (`boot`, `dtbo`, `init_boot`, `recovery`, `vendor_boot`) foram recalculados e
   **batem 5/5** — a extração é byte-idêntica ao que o aparelho verifica.
10. **Procedência confirmada:** o arquivo local é o pacote **completo** oficial
    (`jm21pack.fiio.net/beta/JM21-update-1.1.1.zip`, 1 642 845 150 bytes,
    idêntico ao `Content-Length` do servidor). O nome `JM21-ota-1.1.1.zip` que
    aparece nas props é o **incremental** (92,7 MB).
11. **Changelog oficial recuperado** e correlacionado com o código: ALL TO DSD,
    MQA, DoP, switch de DRE e as correções de "pop" explicam rotinas que já
    tínhamos visto nos binários.
12. **EDL é o ponto fraco:** não há `prog_firehose` no pacote e não existe
    pacote de serviço público do JM21. Recuperação hoje = OTA/sideload ou
    `fastboot` destravado.
13. **BTF nos módulos = quase-fonte.** Todos os `.ko` FiiO têm `.BTF`; com
    `pahole` saíram structs, enums e a vtable completos (`snd_dac_dai_ops`,
    `dac_public_data`, `system_mode`, `dac_event_type`, `fpga_config_params`) —
    sem decompilador. Ver `docs/10-abi-kernel-fiio.md`.
14. **`services.jar` decompilado.** Lista real de pacotes FiiO, concessão
    automática de permissões (incluindo um app de teste), ganchos no AMS/OOM,
    USB, power e o `AudioSystem.setMasterVolumeDac` do `AudioService`.
15. **A interface userspace↔kernel é sysfs**, não `/dev`:
    `/sys/devices/platform/soc/soc:fiio_attr/...` (driver `fiio_attr`, dentro de
    `fiio_underlay_modules.ko`).
16. **Kernel config extraída:** `android13-8`, clang 14.0.7, `LTO_CLANG_FULL`,
    `CFI_CLANG`, `SHADOW_CALL_STACK`, `KASAN=y`, `MODVERSIONS`, `KALLSYMS_ALL`.
17. **Pipeline de volume decifrado por disassembly.** A placa tem 5 tabelas de
    121 passos (`vol_table_po_gain_l/m/h/sh/uh`); o código soma
    `tabela[step] + gain_table[pogain]`, faz clamp em 255 e chama
    `ops->set_volume_db`. Curvas diferentes por modo de ganho (sem
    "compensação": hipótese refutada pelo datasheet).
    Dados em `analysis/fw-1.1.1/volume-tables.csv`, análise em
    `docs/11-disassembly-do-audio.md`.
18. **Energia, GPIOs e controles ALSA decompilados.** Mapa dos 7 GPIOs, ordem de
    energia com tempos reais (20/10/10/50 ms), caminho SPDIF que desliga os
    DACs, modo de canal `SPECIAL_MODE_2` (dual DAC paralelo), boot em High gain,
    mapeamento dos registradores reais do CS43198 e as sequências de filtro/DRE:
    `docs/12-energia-e-controles.md`.
19. **Especificações oficiais incorporadas e duas correções.** Potência real é
    **245 mW/canal** no 3,5 mm (não 280) e 700 mW/canal no 4,4 mm; o PCM
    768 kHz / DSD512 é **só do caminho USB Audio** (local fica em 384 kHz /
    DSD256). O 3,5 mm é **compartilhado com coaxial SPDIF**.
20. **Datasheet do CS43198 confirma e corrige o driver.** Endereços do driver são
    os do chip (`0x90000` filtro, `0x90001/2` volume PCM, `0x70000/1` volume
    DSD); a escala é **0x00 = 0 dB e 0xFF = mute**, o que refuta a hipótese de
    "255 = 0 dB" e mostra que step 0 = mute e step 120 = máximo.
21. **HAL → kernel é notifier chain, não ioctl.** Os `PLAYER_*` são eventos
    0–8 de `player_notifier_cb`, com struct própria (rate/format/bits/modo) e
    desligamento por tempo de 3 s. A HAL entra por kcontrols e sysfs. Ver
    `docs/13-eventos-hal-kernel.md`.

---

## 1. Hardware — resumo

| Item | Valor observado | Evidência |
|------|-----------------|-----------|
| SoC | Qualcomm `khaje` / SM6225 (Snapdragon 680) | `[DT]` |
| Árvore vendor / device | `bengal_515` | `[PROP]` |
| GPU | Adreno 610 | `[PROP]`/`[FAB]` |
| Kernel | 5.15.41 + patches locais (`-dirty`) | `[DRV]` |
| DAC | 2x Cirrus Logic CS43198 (L e R, I2C 0x33 e 0x30) | `[DT]` |
| Ponte de áudio | FPGA Gowin via SPI/I2C (`gowin,fpga_i2c`) | `[DT]` |
| Amps | 2x SGM8262 (alimentações `amp_pwr` e `amp2_pwr` separadas) | `[DT]` `[FAB]` |
| Saídas | 3.5 mm SE e 4.4 mm BAL, detecção por GPIO + ADC | `[DT]` `[DRV]` |

Detalhes, barramentos, GPIOs e o mapa de clock: **[docs/01-hardware.md](docs/01-hardware.md)**.

## 2. Firmware e particionamento — resumo

19 partições no payload: `abl`, `boot`, `dtbo`, `init_boot`, `modem`, `odm`,
`product`, `recovery`, `rpm`, `system`, `system_dlkm`, `system_ext`, `vbmeta`,
`vbmeta_system`, `vendor`, `vendor_boot`, `vendor_dlkm`, `xbl`, `xbl_config`.
Não existe partição `super` no payload: o OTA escreve direto nas partições
lógicas `[FW]`. `system` = 2,2 GB; `vendor_dlkm` = 752 MB (dominado por
`qca_cld3_wlan.ko`, 451 MB).

Procedimento de extração, hashes, AVB, política de OTA e layout:
**[docs/02-firmware-e-particionamento.md](docs/02-firmware-e-particionamento.md)**.

## 3. Stack de áudio — resumo

```
App (FiiOMusic) → AudioFlinger → HIDL audio HAL 7.0 (audio.primary.bengal.so)
   ├─ libfiioaudio.so / libfiioaqm.so   (DPA, DSD, MQA, EQ, volume de hardware)
   ├─ PAL / libqc2audio_*               (Qualcomm Platform Audio Layer)
   └─ ALSA (libtinyalsa + /vendor/etc/mixer_paths_*.xml)
        → DAI dummy FiiO (fiio_snd_soc_dummy_dai.ko)
        → FPGA Gowin (gw-fpga.ko, fpga_audio_interface.ko)
        → I2S/TDM → CS43198 L/R → SGM8262 → 3.5 mm / 4.4 mm
           (controle por I2C: cs43198.ko + dac_core_module.ko)
```

Rotas, formatos DSD, MQA, filtros digitais, modos de ganho, política de áudio
("hifi_playback", "direct_pcm", variante *gaming*) e o contrato de ioctl do
`dac_core` estão em **[docs/03-stack-de-audio.md](docs/03-stack-de-audio.md)**.

## 4. Kernel e device tree — resumo

Módulos-chave em `vendor_dlkm`: `cs43198.ko`, `dac_core_module.ko`,
`anolog_board_jm21.ko`, `fiio_primary_modules.ko`, `fiio_underlay_modules.ko`,
`fiio_snd_soc_dummy_dai.ko`, `fiio_headset_jack.ko`, `fiio_config.ko`,
`gw-fpga.ko`, `fpga_audio_interface.ko`, `fpga_interface.ko`.

O DTBO tem 42 overlays; o do JM21 é o índice **40** (111 608 bytes), com
`fiio,dac-core`, `cirrus,cs43198`, `gowin,fpga_i2c`, `qcom,gw-fpga`,
`fiio,anolog_board` e `fiio,jack_det`.

Árvore completa do overlay já extraída em `analysis/fw-1.1.1/dtbo-jm21-full.dts`.
Ferramenta própria: `tools/dt_dump.py`. Análise:
**[docs/04-kernel-e-devicetree.md](docs/04-kernel-e-devicetree.md)**.

## 5. Framework e aplicativos — resumo

Aplicativos FiiO em `/system/app`: `FiiOMusic` (117 MB), `FiiOTape` (133 MB),
`FiiOEq`, `FiiOCast`, `FiiOIpod`, `FiiOMarket`, `FiiOUpdate`, `AboutFiio` `[FW]`.

Não existe `fiio-framework.jar`: as modificações estão **dentro** de
`framework.jar` (38 MB) e `services.jar` (17 MB), o que exige diff contra a
AOSP/qssi-13 `[FW]` `[HIP]`.

JNI e bibliotecas nativas do player, permissões e alvos de decompilação:
**[docs/05-framework-e-apps.md](docs/05-framework-e-apps.md)**.

## 6. Playbooks

- Comandos ADB/on-device (passivo → diagnóstico) e comandos offline já usados:
  **[docs/06-playbooks-adb.md](docs/06-playbooks-adb.md)**
- Riscos, AVB, desbloqueio, EDL e recuperação:
  **[docs/07-riscos-e-recuperacao.md](docs/07-riscos-e-recuperacao.md)**

## 7. Roadmap e perguntas abertas

Fases com portões de decisão, o que já está respondido e o que continua
desconhecido: **[docs/08-roadmap-e-perguntas-abertas.md](docs/08-roadmap-e-perguntas-abertas.md)**

Glossário: **[docs/09-glossario.md](docs/09-glossario.md)**

## 8. Metodologia (REA) e registro de evidências

Como cada conclusão foi obtida, o que é observação vs. inferência, limites das
ferramentas e o ledger de evidências:
**[docs/00-metodologia-e-evidencias.md](docs/00-metodologia-e-evidencias.md)**

## 9. ABI interna dos módulos (BTF)

Structs, enums, vtable e o contrato entre `dac_core`, `cs43198`, `anolog_board`,
`headset_jack`, `mode_select` e FPGA — recuperados sem decompilador:
**[docs/10-abi-kernel-fiio.md](docs/10-abi-kernel-fiio.md)**

## 10. Disassembly do caminho de volume

Tabelas de volume/ganho extraídas do `.rodata`, pipeline reconstruído a partir
de `anolog_board_update_volume`, e o que ainda falta no driver do DAC:
**[docs/11-disassembly-do-audio.md](docs/11-disassembly-do-audio.md)**

## 11. Energia, GPIOs e controles ALSA

Sequência de energia com tempos, mapa dos GPIOs, caminho SPDIF, modo de canal,
registradores de filtro/DRE e o mapeamento real do CS43198:
**[docs/12-energia-e-controles.md](docs/12-energia-e-controles.md)**

## 12. Eventos HAL ↔ kernel

A notifier chain que liga a HAL ao `dac_core` (eventos 0–8, struct de
notificação, formatos DSD privados e desligamento por tempo):
**[docs/13-eventos-hal-kernel.md](docs/13-eventos-hal-kernel.md)**

---

## Inventário local (fora do git)

| Caminho | Conteúdo | Tamanho |
|---------|----------|---------|
| `fw/JM21-update-1.1.1.zip` | OTA original A/B | 1,6 GB |
| `fw/JM21-update-1.1.1/` | payload extraído + metadados | 1,6 GB |
| `dumps/fw-1.1.1/` | 19 imagens de partição | ~4,9 GB |
| `analysis/fw-1.1.1/` | recortes pequenos: configs, `.so`, `.ko`, DTS, props | ~130 MB |
| `tools/bin/payload-dumper-go` | binário recompilável | 12 MB |
| `tools/dt_dump.py` | parser FDT/DTBO próprio (sem dependências) | — |

## Restrições do laboratório

- O JM21 **não está conectado**; nada aqui depende do aparelho.
- Nada de escrita no dispositivo nesta fase. Somente leitura offline.
- `fw/`, `dumps/` e binários grandes não entram no git (ver `.gitignore`).
- Sem co-autoria em commits; autor é o usuário do git.
