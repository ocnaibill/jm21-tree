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
22. **`fiio_primary_modules.ko` é o SDK do stack.** 19 cadeias de notificação,
    registro de módulos por nome, hub de atributos sysfs, helpers de I2C/regmap
    e `report_playing_info`. Ver `docs/14-arquitetura-kernel-fiio.md`.
23. **Pesquisa externa cruzada.** Acrescentou o part number do FPGA
    (**GW1NZ-1**, review, não confirmado), o driver upstream `cs43130.c` como
    referência e a leitura por bits do filtro; corrigiu nossa tabela de filtros
    e explicou `0x20000` (Power Down Control) e `0x10010` (pop-free/DXD).
    Conflito registrado sobre a topologia SE/BAL.
24. **Conflito de topologia resolvido por código.** Os dois CS43198 recebem o
    mesmo estéreo, mas o chip "R" é escrito com `0x90004 = 0x0C`
    (`PCM_INV_A|PCM_INV_B`) — é um **par diferencial**, não uma divisão L/R.
    `amp2_pwr` só liga em `output_type >= 3`, coerente com BAL usando os dois.
25. **Ganho: quase tudo é digital.** Só há um efeito de hardware ligado ao
    volume — `+1dB_EN` (`0x80000` bit 0) no volume máximo com `output_type 0`.
    `OUT_FS` nunca muda; `gain_pwr_update` existe mas não é lido em nenhum
    módulo decompilado. Ver `docs/15-conflitos-e-metodo-de-prova.md`.
26. **FPGA é o clock master.** `fpga_set_mclk()` seleciona 22/24, 45/49 ou
    90/98 MHz para os DACs; o SoC não fecha o clock.
27. **Pesquisa externa auditada item por item.** Confirmados: kernel 5.15.41,
    layout GKI, `init_boot`, swapfile de 512 MB + zram lz4, MGLRU
    (`CONFIG_LRU_GEN`), splash BMP em offset 16384. Refutados: partição `super`
    no payload e partição `splash`. Sem evidência: "bootloader desbloqueado de
    fábrica" e "SELinux permissive" (build `user`, `ro.debuggable=0`, AVB com
    verificação ligada). Ver `docs/16-auditoria-pesquisa-externa.md`.
28. **Kallsyms do kernel recuperado (152 139 símbolos).** Não existe nenhum
    símbolo `snd_dac_*` nem `fiio_*` no `Image`: os 4 `EXPORT_SYMBOL_GPL` do
    `dac_core` são **código morto** neste firmware, e o techpack de áudio da
    Qualcomm está em módulos, não no kernel.
29. **PDF externo auditado.** Confirmou o mapa de registradores e os 5 filtros;
    **refutado** em três pontos: `resourcemanager_bengal_idp.xml` **não** fixa
    192 kHz (`fractional_sr=1`, só 8k/16k/44,1k/48k no arquivo), o driver
    **não** varia `OUT_FS` em runtime, e a posição dos bits de `0x90000` está
    trocada (bit 2 = WBF, bit 1 = high-pass, bit 0 = de-emphasis).
30. **Pedido GPL redigido + plano B.** Todos os módulos FiiO declaram
    `license=GPL`/`GPL v2`; o repo público da FiiO é Linux 2.6.31 (Ingenic), não
    o JM21. Pedido pronto para envio e plano de escalonamento/fallback em
    `docs/17-pedido-gpl-e-plano-b.md`.
31. **Superfície sysfs completa mapeada.** O `init.fiio.common.rc` faz `chmod
    0666` em ~50 nós de `soc:fiio_attr` — essa é a API. Mapeamos nó → módulo →
    papel, os gatilhos `on property:` reais e os serviços (`fiiouac`,
    `fiio_init.sh`, `system_ctrl.sh`…). Ver `docs/18-superficie-sysfs.md`.
32. **HAL decompilada e caminho fechado.** A `libfiioaudio.so` **não** usa sysfs:
    fala por kcontrols ALSA. Recuperamos a tabela de `fiio_adev_set_codec_param`
    (12 nomes, dos quais só 7 existem no JM21) e o fio completo do volume:
    `AudioService` → mixer `DAC Playback Volume` → `dac_core` → tabela →
    `cs43198` (I2C). Ver `docs/19-hal-de-audio.md`.
33. **DSD, DoP, D2P e MQA mapeados.** `match_audio_process_mode` decide o modo a
    partir de 7 propriedades e do dispositivo de saída; ALL TO DSD troca o
    formato para `0x1a000002` (DSD_U16_LE) e usa 1,25 MB de estado; o caminho
    DSD nativo só empacota bits (TBL NEON 8→16, reordenação 16→32); MQA vem de
    `libfiioaqm.so` via `aqm_*`. Ver `docs/20-dsd-mqa.md`.
34. **App FiiOMusic decompilado.** Três JNI (`fiioa`, `fiioac`, `fiiocd` — esta
    última é leitura de **CD**), player no pacote `com.example.root.checkappmusic`,
    processamento só em 44,1/48/88,2/96 kHz e nunca em MQA, MQA com
    `decodeType` 1/2 escolhido pelo app. O player **não** escreve as
    propriedades de DSD — falta achar o dono. Ver `docs/21-fiiomusic-app.md`.
35. **Dono das propriedades encontrado.** `Settings` (`com.android.settings.fiio.audio`)
    é o painel real e escreve `persist.sys.all.to.dsd` e
    `persist.sys.audio.output.select`; `Scrcpy` (`com.android.fiio.scrcpy`) é
    **serviço de controle remoto** e injeta os mesmos ajustes. A ponte é
    `AudioSystem.setCodecParam(type, valor)` (API oculta no `framework.jar`),
    com type 2 = PO Gain, 3 = filtro, 1 = balanço, 19 = flag de play config.
    Ver `docs/22-settings-e-controle.md`.
36. **Sessão 1 no aparelho (read-only) — e duas correções minhas.**
    **SELinux é Permissive** e o **bootloader está destravado**
    (`orange`, `flash.locked=0`): a pesquisa externa estava certa e minha
    auditoria errada. Também confirmado: I²C bus 2 com DACs em **0x30/0x33** e
    FPGA em **0x36**; GPIOs absolutos (base TLMM 389); dois MCLKs no FPGA;
    `board_vol_dac=255` (mute) ocioso; `dac_vol=69`. Ver
    `docs/23-sessao-1-baseline.md`.
37. **Limite de acesso atual:** `tinymix`/`tinyplay` existem, mas `/dev/snd` é
    `0660 system:audio` — sem root não há leitura de kcontrols nem dump de
    regmap. Decisão sobre root fica explícita e adiada.
38. **Root feito, com segurança.** Magisk em `init_boot_a` (slot `a`, bootloader
    já destravado), verificado por hash: o slot A é a imagem patchada; o slot B
    está em build anterior. **Kcontrols reais: 8** (Playback Volume 30, LR
    Balance 20, PO Gain 2 = High, Filter 2, POLO 3…), e os 4 "fantasma"
    realmente não existem. **Registradores vivos** (`dac_read_reg`): tocando a
    44,1 kHz/vol 30 → `0x90002 = 0x90001 = 93` (tabela `h[30]`),
    `0x90000 = 0x42` (filtro 2), `0x20000 = 0xAE` (power-up), `0x80000 = 0x30`
    (+1dB off). **`fiioconfig`**: 10 MB, só 48 KB usados, SN em `0x1800`,
    marcadores `0xcac1`/`0xcac3`. Ver `docs/25-sessao-2-root.md`.

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

## 13. Arquitetura do stack FiiO no kernel

O "SDK" do kernel (19 cadeias, registro por nome, hub `soc:fiio_attr`) e o
cruzamento com a pesquisa externa — o que confirmou, o que corrigiu e o que
conflita:
**[docs/14-arquitetura-kernel-fiio.md](docs/14-arquitetura-kernel-fiio.md)**

## 14. Conflitos e método de prova

As hipóteses rivais (topologia, ganho, FPGA), o que já foi decidido por código,
o que ainda exige bancada e os critérios de aceitação:
**[docs/15-conflitos-e-metodo-de-prova.md](docs/15-conflitos-e-metodo-de-prova.md)**

## 15. Auditoria de pesquisa externa

Veredito item por item das alegações de terceiros (bootloader, SELinux,
partições, splash, swap, kernel) contra o firmware 1.1.1:
**[docs/16-auditoria-pesquisa-externa.md](docs/16-auditoria-pesquisa-externa.md)**

## 16. Pedido GPL e plano B

E-mail pronto (inglês), identificadores do build, hashes dos módulos e o plano
de escalonamento/fallback técnico:
**[docs/17-pedido-gpl-e-plano-b.md](docs/17-pedido-gpl-e-plano-b.md)**

## 17. Superfície sysfs e gatilhos

A API completa de `soc:fiio_attr`, o mapa nó → módulo → função e as
propriedades que disparam ações:
**[docs/18-superficie-sysfs.md](docs/18-superficie-sysfs.md)**

## 18. HAL de áudio (`libfiioaudio.so`)

A API real (`fiio_adev_set_codec_param`), a tabela de controles, o caminho do
volume ponta a ponta e a distinção kcontrol × sysfs:
**[docs/19-hal-de-audio.md](docs/19-hal-de-audio.md)**

## 19. DSD, DoP, D2P e MQA

A decisão de modo (`match_audio_process_mode`), o ALL TO DSD, o empacotamento
DSD nativo e o MQA via `libfiioaqm.so`:
**[docs/20-dsd-mqa.md](docs/20-dsd-mqa.md)**

## 20. App FiiOMusic

JNI (áudio, EQ/CD), `FiioAudioTrack`, buffers por taxa, MQA e as propriedades
que o app toca:
**[docs/21-fiiomusic-app.md](docs/21-fiiomusic-app.md)**

## 21. Settings, Scrcpy e o plano de controle

Quem escreve o quê: o pacote `com.android.settings.fiio`, o serviço de controle
remoto Scrcpy, a ponte `AudioSystem.setCodecParam` e os modos de operação:
**[docs/22-settings-e-controle.md](docs/22-settings-e-controle.md)**

## 22. Sessão 1 com o aparelho (baseline)

O que o hardware confirmou, o que corrigiu da auditoria e onde o acesso para sem
root:
**[docs/23-sessao-1-baseline.md](docs/23-sessao-1-baseline.md)**

## 23. Sessão 2: root e hardware real

Magisk em `init_boot`, kcontrols reais, registradores do CS43198 lidos ao vivo e
a estrutura inicial da `fiioconfig`:
**[docs/25-sessao-2-root.md](docs/25-sessao-2-root.md)**

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
