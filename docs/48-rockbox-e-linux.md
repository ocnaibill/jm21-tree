# 48 — Rockbox / Linux mínimo: caminho de áudio e UI (issue #13)

> Análise offline. A parte de áudio se apoia no que foi **provado** no Plano B
> (kernel nosso carrega o stack FiiO — `docs/45`).

## 1. As três opções

| Opção | O que é | Esforço | Áudio |
|-------|---------|---------|-------|
| **A. RaaA** (Rockbox como app) | port do Rockbox para Android/Linux, roda como aplicativo | baixo | via API do Android → HAL; sem controle direto do DAC |
| **B. Linux mínimo + stack FiiO** | initramfs próprio + nosso kernel + módulos vendor + ALSA | alto | direto no ALSA (`hw:0`) |
| **C. Android enxuto** | Android com o framework FiiO, sem apps/serviços | médio | igual ao atual |

## 2. Por que "Rockbox bare-metal" não é opção

O boot é XBL/TrustZone/RPM/ABL; um RTOS bare-metal exigiria reimplementar a
inicialização da Qualcomm. Fora de escopo.

## 3. Opção B: o que o áudio exige

`[FATO]` (medido no Plano B) o nosso kernel carrega:
`fiio_primary_modules`, `cs43198`, `dac_core_module`, `anolog_board_jm21`,
`gw_fpga`, `fpga_audio_interface`, `fpga_interface`, `fiio_config`.

Para o ALSA existir num Linux mínimo, faltam:
1. **Techpack de áudio**: `machine_dlkm`, `bolero_cdc_dlkm`, `wcd937x_dlkm`,
   `swr_ctrl_dlkm`, `spf_core_dlkm`, `adsp_loader_dlkm`… (todos em
   `vendor_dlkm`) — é o que cria a placa `bengal-idp-snd-card`.
2. **Firmware do ADSP** (`adsp.mbn`/`adsp_loader`) — carregado pelo
   `qcom_q6v5_pas`; sem ele, o DSP não sobe.
3. **DTB** correto (`vendor_boot`), incluindo os nós de áudio e o painel.
4. **UCM/`mixer_paths`** do vendor para as rotas.
5. **Touch** (`ts_core`, `goodix_gt9xx_ts`) e o painel para a UI.

## 4. Opção A: o atalho honesto

O port Android do Rockbox usa `AudioTrack` → HAL → nosso caminho de áudio. Ele
**não** tem acesso exclusivo ao DAC (a HAL é dona), então:
- toca PCM (com SRC da HAL/aplicativo, dependendo do caminho);
- **não** faz DSD nativo nem usa o `dac_ctrl`;
- serve para **UI/experiência** e para provar o conceito.

## 5. Recomendação

1. **A primeiro** (RaaA): valida UI, navegação, biblioteca e áudio básico com
   esforço baixo.
2. **B depois**, se o objetivo for bit-perfect/DSD fora do Android: o caminho
   do kernel já está aberto (Plano B); o trabalho é o userspace (initramfs,
   carga dos módulos, UCM, UI).
3. **C** como meio-termo: manter o Android e o framework FiiO, removendo o que
   não interessa.

## 6. Riscos

- B exige um `boot.img`/`vendor_boot` próprios e initramfs — **testável por
  `fastboot boot`** (RAM), sem gravar.
- Sem o ADSP/touch, o Linux mínimo sobe "mudo e cego" — é o primeiro marco a
  validar (console por USB/serial, depois painel).

---

## 7. Inventário verificado no dump (`fw-1.1.1`) — 2026-10-25

Tudo que a §3 listava como "falta" foi conferido nas partições originais. **Nada
precisa ser compilado**: as peças existem no firmware, o trabalho da opção B é
de userspace (initramfs + ordem de carga + ALSA + UI).

| Peça | Onde está | Evidência |
|---|---|---|
| Techpack de áudio | `/vendor_dlkm/lib/modules/` | `machine_dlkm.ko`, `bolero_cdc_dlkm.ko`, `wcd937x_dlkm.ko`, `wcd_core_dlkm.ko`, `swr_ctrl_dlkm.ko`, `swr_dlkm.ko`, `spf_core_dlkm.ko`, `q6_dlkm.ko`, `q6_pdr_dlkm.ko`, `q6_notifier_dlkm.ko`, `audio_pkt_dlkm.ko`, `audio_prm_dlkm.ko`, `adsp_loader_dlkm.ko` |
| Carregador do ADSP | idem | `qcom_q6v5_pas.ko`, `qcom_q6v5.ko` |
| Firmware do ADSP | `/vendor/firmware/` | `adsp.b00`…`adsp.b04` (formato `.b*` segmentado, carregado pelo `qcom_q6v5_pas`) |
| Nó do sound card no DTB | `prebuilt/dtb` (de `dtbo.img`) | `qcom,bengal-asoc-snd`, `bengal_snd`, `/soc/spf_core_platform/qcom,msm-audio-ion` |
| Rotas do codec | `/vendor/etc/` | `mixer_paths_bengal_idp.xml` (a placa é IDP), `mixer_paths_bengal_qrd.xml`, `mixer_paths_scubaidp.xml`, `mixer_paths_scubaqrd.xml` |
| Política de áudio | `/vendor/etc/audio/` | `audio_policy_configuration.xml` |
| Touch | `/vendor_dlkm/lib/modules/` | `ts_core.ko`, `goodix_gt9xx_ts.ko` |
| Stack FiiO | já provado no Plano B (`docs/45`) | `cs43198`, `dac_core_module`, `anolog_board_jm21`, `gw_fpga`, `fpga_audio_interface`, `fiio_config` |

### 7.1 Consequência para o plano

A ordem de carga deixa de ser incógnita: `adsp_loader_dlkm` → `qcom_q6v5_pas`
(+ `adsp.b*`) → techpack (`bolero`/`wcd*`/`swr*`/`spf_core`/`machine`) → a placa
`bengal_snd` aparece → stack FiiO (`cs43198`/`dac_core`/`anolog_board`) → ALSA
`hw:0`.

O primeiro marco testável continua sendo o mesmo e é barato: **boot por
`fastboot boot` com initramfs próprio, console por USB, e ver a placa de som
nascer no `dmesg`** — sem gravar nada, sem tela ainda.

### 7.2 Opção A (RaaA), situação do host

Não há Android SDK nem NDK na máquina (`~/Android/Sdk` inexistente, nenhum
`ndk-build`), e o Rockbox não está clonado. Para a opção A seria preciso baixar
SDK + NDK e compilar o port Android do Rockbox — é o único caminho que depende
de download novo.

---

## 8. Experimento 1 (opção B): TWRP como bancada de áudio

Ideia: **não** é preciso construir initramfs para o primeiro teste. O TWRP roda
com o **kernel stock** do `boot_a` (a imagem é kernel-less), então os módulos do
`vendor_dlkm` casam com o `vermagic` — dá para carregar o techpack de dentro do
recovery e ver a placa de som nascer no `dmesg`.

Ordem de carga prevista:

```
adsp_loader_dlkm -> qcom_q6v5_pas (+ adsp.b*) -> q6_dlkm, q6_pdr_dlkm,
q6_notifier_dlkm, spf_core_dlkm, swr_ctrl_dlkm, swr_dlkm, bolero_cdc_dlkm,
wcd9xxx_dlkm, wcd_core_dlkm, wcd937x_dlkm, wcd937x_slave_dlkm,
audio_pkt_dlkm, audio_prm_dlkm, machine_dlkm
```

Passos:
1. `adb reboot recovery`
2. montar `/vendor` (TWRP já faz) e `/vendor_dlkm` (`/dev/block/mapper/vendor_dlkm`
   — se não estiver mapeado, o TWRP mapeia ao montar; alternativa: `mount` do
   `dm-*` correspondente)
3. `insmod` em ordem, checando `dmesg` a cada passo
4. marco: `dmesg | grep -i "bengal_snd\|asoc-snd\|sound card"` e `ls /proc/asound`

Se a placa nascer, o resto da opção B é userspace (ALSA + UI). Se não, o
primeiro suspeito é o `adsp_loader` (firmware/`adsp.b*` fora do caminho) ou a
ordem.

Instrumentação: script `tools/audio-harness.sh` (a escrever) que recebe o
caminho do `vendor_dlkm` e faz a carga com log por etapa.

---

## 9. Experimento 1 executado (2026-10-25) — resultado parcial

Rodou com o TWRP em recovery e adb ativo (após desabilitar o MTP, ver
`docs/51` §20).

### 9.1 O que o TWRP já carrega sozinho

Surpresa boa: o ramdisk do TWRP carrega **257 módulos** de `/lib/modules` e,
entre eles, a stack FiiO inteira:

```
cs43198  dac_core_module  anolog_board_jm21  gw_fpga  fpga_audio_interface
fpga_interface  fpga_mgr  fiio_config  fiio_headset_jack  fiio_primary_modules
fiio_charger_manager  fiio_underlay_modules  fiio_gpio_debug_module ...
qcom_q6v5  qcom_q6v5_pas  frpc_adsprpc        <- ADSP/PAS já de pé
```

E o `dmesg` mostra `[dac_core]: snd_dac_load_work: Enter!` — ou seja, o driver
do DAC executa no recovery.

### 9.2 O que faltava e o que foi carregado

O techpack **não** está no ramdisk (só 257 dos 219+ de `vendor_dlkm`); está em
`vendor_dlkm`, que o TWRP não mapeia como `/vendor/lib/modules` (e `/vendor` é
read-only, não dá para montar sobre ele). Montado em `/mnt/vdlkm`:

- carregaram: `q6_dlkm`, `q6_pdr_dlkm`, `snd_event_dlkm`, `mbhc_dlkm`,
  `gpr_dlkm`, `swr_dlkm`, `wcd_core_dlkm`, `wcd937x_slave_dlkm`, `spf_core_dlkm`
  (o `dmesg` confirma com `spf_core_platform_driver_probe`);
- falharam com `ENOENT` (símbolo não resolvido): `machine_dlkm`,
  `bolero_cdc_dlkm`, `wcd937x_dlkm`, `wcd9xxx_dlkm`, `swr_ctrl_dlkm`,
  `audio_pkt_dlkm`, `audio_prm_dlkm`, `adsp_loader_dlkm`, `pinctrl_lpi_dlkm`.

Resultado: `--- no soundcards ---` (a placa não nasceu ainda).

### 9.3 Próximo passo

A ordem de `modules.load` não basta: o que resolve `ENOENT` é a ordem
**topológica** de `modules.dep`. Caminhos:
1. usar `modprobe` com `-d /mnt/vdlkm` (resolve `.dep`) em vez de `insmod`;
2. ou carregar `modules.dep` em ordem inversa de dependência.

Detalhe importante: `insmod` reporta `ENOENT` mesmo quando o módulo **entra** —
`spf_core` provou isso (`spf_core_platform_driver_probe` no dmesg). Então o
critério de sucesso tem de ser `/proc/modules` + `dmesg`, nunca o código de
retorno do `insmod`.

### 9.4 Ordem topológica: carregou tudo, mas o DSP não sobe

Calculado o fecho de dependências de `machine_dlkm`/`adsp_loader_dlkm` a partir
de `/mnt/vdlkm/lib/modules/modules.dep` (20 módulos) e carregado nessa ordem.
Resultado: **todos entraram** (`adsp_loader_dlkm`, `audio_pkt_dlkm`,
`audio_prm_dlkm`, `bolero_cdc_dlkm`, `wcd9xxx_dlkm`, `wcd937x_dlkm`,
`machine_dlkm`, `swr_ctrl_dlkm` …), e os que já estavam deram `File exists`.

Mesmo assim: `--- no soundcards ---`.

Causa encontrada:

```
/sys/class/remoteproc/remoteproc0  ab00000.remoteproc-adsp  state=offline
/sys/class/remoteproc/remoteproc1  b300000.remoteproc-cdsp  state=offline
/sys/class/remoteproc/remoteproc2  6080000.remoteproc-mss   state=offline
```

**O ADSP nunca foi iniciado.** Sem o DSP de pé, o `machine_dlkm` não faz bind e
a placa `bengal_snd` não nasce. `/vendor` está montado e
`/vendor/firmware/adsp.b00` existe, então não é falta de firmware — é ninguém
ter disparado o remoteproc.

`echo start > /sys/class/remoteproc/remoteproc0/state` **não** mudou o estado
(segue `offline`, sem mensagem no dmesg).

### 9.5 Próximo passo (retomada)

1. Descobrir o que inicia o ADSP no Android: provavelmente `qcom_q6v5_pas` com
   `qcom,auto-boot` no DTB, ou um serviço de init que escreve em
   `/sys/class/remoteproc/*/state`. Comparar com o `init.rc`/`vendor` do stock.
2. Verificar por que a escrita em `state` não pega (dmesg completo no momento
   da escrita, não o tail).
3. Alternativa: escrever no `state` do `qcom_q6v5_pas` via
   `/sys/module/qcom_q6v5_pas/parameters/...` ou usar `remoteproc` do
   subsistema correto (o `ab00000.remoteproc-adsp` é o certo).

Se o ADSP subir, o resto do caminho já está carregado — é só ver a placa nascer.

## 10. ADSP subiu; o próximo muro é o DT (2026-10-26)

### 10.1 Firmware: a causa era o caminho, não a falta

`echo start > /sys/class/remoteproc/remoteproc0/state` falhava com:

```
remoteproc0: Direct firmware load for adsp.mdt failed with error -2
remoteproc0: request_firmware failed: -2
```

O `request_firmware` procura em `/lib/firmware` (ramdisk), **não** no `/vendor`
montado depois. Com `/vendor` montado e o firmware copiado:

```
cp /vendor/firmware/adsp.* /lib/firmware/     # 36 arquivos
echo start > /sys/class/remoteproc/remoteproc0/state
-> state=running
-> "lpass subsystem is up" / "remote processor ab00000.remoteproc-adsp is now up"
-> qcom_smd_qrtr_probe: SMD QRTR driver probed
-> fastrpc_rpmsg_probe: opened rpmsg channel for lpass
```

**O ADSP sobe fora do Android.** Foi o primeiro marco do §7.1 cumprido.

### 10.2 A placa ainda não nasce: falta o nó no DT

Mesmo com ADSP de pé e os 20 módulos do techpack carregados:

```
/proc/asound/cards -> --- no soundcards ---
/proc/device-tree/soc -> ... snd_soc_dummy, slim@a5c0000, vote_lpass_audio_hw
                          (NAO existe qcom,bengal-asoc-snd)
/sys/bus/platform/devices -> snd-soc-dummy, soc:snd_soc_dummy
                             (NAO existe o device do machine driver)
```

Ou seja: **o overlay do `dtbo` com o nó de áudio não é aplicado no boot de
recovery.** O `machine_dlkm` carrega, mas não tem device para fazer bind.

Isso muda o desenho da opção B: não basta um initramfs — é preciso bootar com o
**DT completo** (dtb do `boot_a` + overlay do `dtbo`), o que implica uma imagem
de boot própria, não o slot de recovery.

### 10.3 Próximo passo

1. Montar a imagem de boot do experimento com o `dtb` + `dtbo` corretos
   (temos os dois no dump) e um initramfs mínimo.
2. Verificar no `dmesg` do boot se `qcom,bengal-asoc-snd` aparece em
   `/proc/device-tree` **antes** de carregar os módulos.
3. Só então o `machine_dlkm` terá onde fazer bind e a placa `bengal_snd` nasce.
