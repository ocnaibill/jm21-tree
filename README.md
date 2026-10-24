# jm21-tree — engenharia reversa do FiiO JM21

Repositório público do laboratório de RE do **FiiO JM21** (DAP, Snapdragon 680 /
SM6225 "khaje", 2× Cirrus CS43198, FPGA Gowin GW1NZ-1, Android 13, firmware
1.1.1). O objetivo é documentar **com evidência**: cada afirmação tem origem em
leitura de registrador, hash, código decompilado ou medição.

## Estado atual

**Fase 4 concluída** — firmware, aparelho (com root), HAL, kernel, framework,
apps e FPGA mapeados. Todas as 8 issues do repositório estão fechadas.

| Área | Situação |
|------|----------|
| Firmware / partições / AVB | ✅ `docs/02` |
| Kernel / DT / BTF / módulos | ✅ `docs/04`, `docs/10`, `docs/14` |
| HAL de áudio | ✅ `docs/19`, `docs/13` |
| DAC (registradores, volume, topologia) | ✅ `docs/11`, `docs/12`, `docs/27`, `docs/38` |
| Matriz de taxas (44,1 k → 384 k) e DSD 64/128/256 | ✅ `docs/28`, `docs/29` |
| FPGA (ID, bitstream, netlist) | ✅ `docs/30`, `docs/31` |
| Framework / services | ✅ `docs/33` |
| Apps / auditoria | ✅ `docs/32`, `docs/34` |
| Modos de operação | ✅ `docs/37` |
| USB DAC (UAC + DSD nativo) | ✅ `docs/39` |
| Recuperação / riscos | ✅ `docs/07`, `docs/35` |

Perguntas em aberto e o placar:
**[docs/08](docs/08-roadmap-e-perguntas-abertas.md)** e
**[docs/PROGRESSO.md](docs/PROGRESSO.md)**.

## Índice

| # | Documento |
|---|-----------|
| 00 | [Metodologia e evidências](docs/00-metodologia-e-evidencias.md) |
| 01 | [Hardware](docs/01-hardware.md) |
| 02 | [Firmware e particionamento](docs/02-firmware-e-particionamento.md) |
| 03 | [Stack de áudio](docs/03-stack-de-audio.md) |
| 04 | [Kernel e device tree](docs/04-kernel-e-devicetree.md) |
| 05 | [Framework e apps (base)](docs/05-framework-e-apps.md) |
| 06 | [Playbooks ADB](docs/06-playbooks-adb.md) |
| 07 | [Riscos e recuperação](docs/07-riscos-e-recuperacao.md) |
| 08 | [Roadmap e perguntas abertas](docs/08-roadmap-e-perguntas-abertas.md) |
| 09 | [Glossário](docs/09-glossario.md) |
| 10 | [ABI do kernel (BTF)](docs/10-abi-kernel-fiio.md) |
| 11 | [Volume: tabelas e pipeline](docs/11-disassembly-do-audio.md) |
| 12 | [Energia, GPIOs e controles](docs/12-energia-e-controles.md) |
| 13 | [Eventos HAL ↔ kernel](docs/13-eventos-hal-kernel.md) |
| 14 | [Arquitetura do kernel FiiO](docs/14-arquitetura-kernel-fiio.md) |
| 15 | [Conflitos e método de prova](docs/15-conflitos-e-metodo-de-prova.md) |
| 16 | [Auditoria de pesquisa externa](docs/16-auditoria-pesquisa-externa.md) |
| 17 | [Pedido GPL e plano B](docs/17-pedido-gpl-e-plano-b.md) |
| 18 | [Superfície sysfs](docs/18-superficie-sysfs.md) |
| 19 | [HAL de áudio](docs/19-hal-de-audio.md) |
| 20 | [DSD, DoP, D2P e MQA](docs/20-dsd-mqa.md) |
| 21 | [App FiiOMusic (base)](docs/21-fiiomusic-app.md) |
| 22 | [Settings e controle](docs/22-settings-e-controle.md) |
| 23 | [Sessão 1: baseline](docs/23-sessao-1-baseline.md) |
| 24 | [Root com Magisk](docs/24-root-magisk.md) |
| 25 | [Sessão 2: root](docs/25-sessao-2-root.md) |
| 26 | [`fiioconfig`](docs/26-fiioconfig.md) |
| 27 | [`dac_ctrl` e topologia](docs/27-dac-ctrl-e-topologia.md) |
| 28 | [Matriz de estados](docs/28-matriz-de-estados.md) |
| 29 | [DSD e 352,8/384 kHz](docs/29-dsd-e-384k.md) |
| 30 | [FPGA: bitstream](docs/30-fpga-bitstream.md) |
| 31 | [FPGA: netlist](docs/31-fpga-netlist.md) |
| 32 | [Apps restantes](docs/32-apps-restantes.md) |
| 33 | [Framework e services](docs/33-framework-services.md) |
| 34 | [Auditoria de apps](docs/34-auditoria-apps.md) |
| 35 | [ISO do MTP e EDL](docs/35-mtp-iso-e-edl.md) |
| 36 | [FiiO Music: JNI e DSD/MQA](docs/36-fiiomusic-jni.md) |
| 37 | [Modos de operação](docs/37-modos-de-operacao.md) |
| 38 | [Ganho analógico](docs/38-ganho-analogico.md) |
| 39 | [Modo USB DAC](docs/39-usb-dac.md) |
| 40 | [MQA: detecção e render](docs/40-mqa.md) |
| 41 | [Modo host USB](docs/41-usb-host.md) |
| 42 | [Backup completo (F2)](docs/42-backup-completo.md) |
| 43 | [`jm21ctl` (controle userspace)](docs/43-jm21ctl.md) |
| 44 | [Atualização pós-root](docs/44-atualizacao-pos-root.md) |
| 45 | [Plano B: kernel próprio](docs/45-plano-b-kernel.md) |
| 46 | [Recovery/TWRP](docs/46-recovery-twrp.md) |

O índice narrativo completo (histórico de descobertas, item por item) está em
**[dossie.md](dossie.md)**.

## Ferramentas

| Ferramenta | Função |
|------------|--------|
| `tools/dt_dump.py` | parser de FDT/DTBO (sem dependências) |
| `tools/fpga_fw_to_fs.py` | converte o bitstream Gowin da FiiO (`.fw`) para o formato do Apicula |
| `tools/collect-baseline.sh` | coleta de baseline (read-only e com root) |
| `tools/rate-register-capture.sh` | monitor de taxa (`0x1000B` + HAL + FPGA) |
| `tools/jm21ctl.sh` | controle por userspace: volume, ganho, filtro, registradores |
| `tools/udev/51-android-jm21.rules` | regras udev para `18d1`, `05c6`, `2972` |

## Convenções

- **Evidência obrigatória.** Marcadores: `[FW]` firmware, `[DRV]` módulo de
  kernel, `[DT]` device tree, `[PROP]` propriedade, `[FAB]` fabricante (não
  verificado), `[HIP]` hipótese, `[?]` aberto.
- **Correções ficam registradas.** Quando uma conclusão cai, o erro é mantido no
  texto com a explicação — não é apagado.
- Binários grandes, dumps e saída de decompilador **não** entram no git
  (`.gitignore`); só scripts, hashes e documentos.
- Commits **sem co-autoria**; autor é o dono do repositório.

## Referência

- Firmware de referência: **1.1.1** (tag `fw-1.1.1-baseline`).
- Origem do pacote: `http://jm21pack.fiio.net/beta/JM21-update-1.1.1.zip`
  (confirmado pelo manifesto `beta/patchCN.txt`).
- Sessões com o aparelho: serial USB `3fa90f5`, root via Magisk em `init_boot_a`.
