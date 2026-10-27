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

### 10.4 Correção da hipótese: o nó não vem do DT

Comparação feita nos dois modos:

| | recovery (TWRP) | Android |
|---|---|---|
| `androidboot.dtbo_idx` | 40 | **40** (igual) |
| `/proc/device-tree/soc` | `snd_soc_dummy` | `snd_soc_dummy` (**igual**) |
| `qcom,bengal-asoc-snd` | ausente | **ausente** |
| `/proc/asound/cards` | vazio | `bengal-idp-snd-card` |

Ou seja: **o nó não é aplicado por overlay em nenhum dos dois**. O DT é o mesmo.
O `machine_dlkm` casa por `alias=platform:bengal-asoc-snd` — o device de
plataforma é criado **em runtime**, não pelo DT.

Consequência: a diferença está na **ordem**. No nosso teste carregamos o
`machine_dlkm` **antes** de subir o ADSP; o probe falhou (device ainda
inexistente / deferred) e nunca foi repetido.

### 10.5 Próximo teste (ordem correta)

1. montar `/vendor`, copiar `adsp.*` para `/lib/firmware`, montar `vendor_dlkm`;
2. carregar `q6*`, `spf_core`, `swr*`, `bolero`, `wcd*` (sem o `machine_dlkm`);
3. `echo start > /sys/class/remoteproc/remoteproc0/state` e confirmar
   `state=running`;
4. **só então** `insmod machine_dlkm.ko` (ou `rmmod` + `insmod` se já estava);
5. verificar `/proc/asound/cards`.

Se a placa nascer, o caminho da opção B está provado de ponta a ponta dentro do
recovery, sem precisar de imagem de boot própria — o que simplifica muito o §10.3.

### 10.6 Teste com ordem corrigida: impasse de ordem circular

Estado medido (TWRP, ADSP `running`, firmware em `/lib/firmware`):

```
/sys/bus/platform/drivers  -> bengal-asoc-snd          (driver REGISTRADO)
/sys/bus/platform/devices  -> (nenhum device asoc)     (device NAO criado)
/proc/asound/cards         -> --- no soundcards ---
dmesg                      -> spf_core_add_child_devices: enumarate machine driver
```

O `spf_core_dlkm`, no próprio init, **enumera e cria o device** do machine
driver. Quando ele carregou, o `machine_dlkm` ainda não estava presente (ele
depende de símbolos do `spf_core`, então não pode vir antes) — e a enumeração
não se repete:

```
rmmod spf_core_dlkm -> "Try again" (em uso por gpr/q6/etc.)
```

Impasse: `machine` precisa do `spf_core` carregado; `spf_core` enumera uma única
vez no init. No Android funciona porque o `init` carrega os módulos **em
paralelo** (`androidboot.load_modules_parallel=true`) e/ou a enumeração é
assíncrona.

### 10.7 Próximo passo

Carregar o conjunto **todo de uma vez** (como o init do Android faz), em vez de
um `insmod` por vez em ordem estrita: um laço único disparando `insmod` sem
`wait`, ou preencher `/lib/modules` com os módulos do `vendor_dlkm` e deixar o
`init` do TWRP carregar tudo no boot (aí a ordem é a paralela do Android).

Se o device nascer, `/proc/asound/cards` deve mostrar `bengal-idp-snd-card`
dentro do recovery — e a opção B fica provada de ponta a ponta sem imagem de
boot própria.

### 10.8 Tentativa "DSP primeiro" — e uma dependência a mais

Invertendo (subir o ADSP antes de carregar qualquer módulo), o `start` **falhou**:
`state=offline`. Motivo: sem o `adsp_loader_dlkm` carregado, o firmware não é
entregue ao `qcom_q6v5_pas` — e o `adsp_loader` depende de símbolos do
`spf_core` (`spf_core_is_apm_ready`), que por sua vez enumera o `machine` no
init.

Ou seja, a ordem real é uma cadeia apertada:

```
spf_core (enumera machine)  ->  adsp_loader  ->  ADSP start  ->  machine bind
```

e o `machine_dlkm` só pode entrar **depois** do `spf_core` (dependência de
símbolo), mas é enumerado **durante** o init dele.

Isso reforça o §10.7: o caminho certo é deixar o **init carregar tudo** (como no
Android, em paralelo, `androidboot.load_modules_parallel=true`), em vez de
reproduzir a ordem à mão. Concretamente: copiar o techpack de `vendor_dlkm` para
`/lib/modules` do ramdisk e deixar o init do TWRP carregar no boot.

### 10.9 Por que a flag `TW_LOAD_VENDOR_MODULES` não resolveu

Configurada no `BoardConfig.mk` com os 18 módulos do áudio. No boot, o log do
TWRP mostra:

```
I:Attempting to load modules
I:Checking directory: /vendor/lib/modules
I:Unable to open module directory: /vendor/lib/modules. Skipping
I:number of modules loaded by init: 249
```

Duas descobertas:

1. **Os módulos disponíveis no boot do recovery não vêm do `vendor_dlkm`.** O
   `/lib/modules` do recovery (251 `.ko`, sem nenhum do techpack) vem do
   **ramdisk do `vendor_boot`** (GKI). O techpack de áudio está só no
   `vendor_dlkm`, que **não está montado** quando o carregador roda.
2. O carregador sai cedo: `modules_loaded >= expected_module_count` (249 já
   carregados pelo init contra 18 pedidos) → não tenta os nossos.

### 10.10 Tentativa de embutir os módulos no ramdisk: limite de tamanho

Injetados os 21 `.ko` (13 MB) direto no ramdisk (sem build): a imagem foi de
27 MB para 31 MB e **não bootou** — o ABL caiu para o fastboot. Com 3 módulos
(27 MB) bootou normal. Ou seja, há um limite entre 27 e 31 MB para esta
imagem de recovery (não é o tamanho da partição, que é 96 MB).

### 10.11 Próximos testes (ordem de custo)

1. **Descobrir o limite real de tamanho** (testar 28/29/30 MB). Se for ~30 MB,
   embutir só o subconjunto essencial pode caber.
2. **Montar o `vendor_dlkm` antes do carregador de módulos** — o caminho do
   TWRP é `/vendor/lib/modules`; se ele estiver montado a tempo, a lista do
   `TW_LOAD_VENDOR_MODULES` funciona (mas o curto-circuito do item 1 precisa
   ser contornado).
3. Copiar o techpack para `/lib/modules` em runtime e recarregar a cadeia com o
   ADSP **já de pé**, resolvendo o problema de enumeração do `spf_core`.

### 10.12 Limite de tamanho da imagem de recovery (medido)

Bisectado com arquivos dummy (dados aleatórios, incomprimíveis), para isolar
tamanho de conteudo:

| imagem | resultado |
|---|---|
| 27,0 MB (base, sem dummy) | boota |
| 29,1 MB (+2 MB) | **boota** (dummy presente no /) |
| 30,68 MB (+3,5 MB) | **nao boota** — ABL cai para o fastboot |

Ou seja: o teto pratico esta entre **29,1 e 30,7 MB**, bem abaixo dos 96 MB da
particao `recovery`. Nao e o tamanho da particao.

Consequencia: embutir os 21 modulos do techpack (13 MB crus, ~4 MB comprimidos)
**nao cabe**. O caminho tem de ser carregar do `vendor_dlkm` em runtime — e para
isso o `vendor_dlkm` precisa estar montado antes do carregador de modulos (no
Android isso e o *first stage mount* do init, que o recovery do TWRP nao faz).

### 10.13 Rebind do `spf_core`: re-executa o probe, mas não cria o device

Ideia nova que funcionou tecnicamente: desligar e religar o driver do
`spf_core` pela sysfs **re-executa o probe** — e portanto a enumeração:

```
echo soc:spf_core_platform > /sys/bus/platform/drivers/spf-core-platform/unbind
echo soc:spf_core_platform > /sys/bus/platform/drivers/spf-core-platform/bind
-> dmesg: spf_core_add_child_devices: enumarate machine driver
```

Isso resolve a questao circular (o `machine_dlkm` nao pode estar carregado
antes do `spf_core` por dependencia de simbolos): carrega-se o `spf_core`,
depois o resto, depois o `machine`, e entao rebinda-se.

Estado medido com **tudo** carregado e o rebind feito:

```
machine_dlkm=1  bolero_cdc_dlkm=1  wcd937x_dlkm=1
adsp = running
dmesg: spf_core_add_child_devices: enumarate machine driver  (t=58,8 -> o rebind)
/sys/bus/platform/devices -> (nenhum asoc)
/proc/asound/cards        -> --- no soundcards ---
```

Ou seja: mesmo a enumeracao rodando **com o driver do machine presente**, nenhum
platform device e criado. O `spf_core` parece esperar que o **device** ja exista
(do DT), e nao cria-lo a partir do driver.

Conclusao: para ir alem aqui precisa do **codigo-fonte do kernel FiiO**
(`spf_core_dlkm`/`machine_dlkm`) para ver a condicao exata de
`spf_core_add_child_devices` — ou seja, cai no plano B do `docs/45`
(pedido GPL / kernel proprio).

### 10.14 O device existe! E a cadeia que falta

Duas correcoes de metodo que destravaram tudo:

1. **O device do machine NAO se chama "asoc"** — no Android ele e
   `soc:spf_core_platform:sound` (filho do `spf_core`). Eu vinha filtrando por
   "asoc" e concluindo "nao existe".
2. **O `remoteproc` muda de indice entre boots** — `echo start > remoteproc0`
   pode estar subindo o **cdsp**, nao o adsp. Tem de ser por nome:
   `for r in /sys/class/remoteproc/*; do ... *adsp* ...`.

Com ADSP de pe (por nome) + rebind do `spf_core`:

```
/sys/bus/platform/devices -> soc:spf_core_platform:sound      <-- CRIADO
/sys/kernel/debug/devices_deferred -> soc:spf_core_platform:sound
/sys/bus/platform/devices/soc:spf_core_platform:sound/waiting_for_supplier -> 0
supplier: platform:1b40000.qfprom (bound)
```

O device nasce, o probe roda e devolve **-EPROBE_DEFER**. A cadeia que falta:

| elo | estado |
|---|---|
| `soc:spf_core_platform:sound` (card) | criado, **deferred** |
| driver `bengal-asoc-snd` | registrado, sem device ligado |
| drivers de codec (`bolero-codec`, `wcd937x_codec`, `swr-wcd`) | registrados, **sem device ligado** |
| bus **SoundWire** | **vazio** (nenhum slave enumerado) |

Ou seja: o card espera o **componente ASoC** (`wcd937x`), que e um slave de
**SoundWire**, e o barramento SoundWire nao tem nenhum slave — falta o master
`swr-wcd` ser ligado.

### 10.15 Proximo passo

Ligar o master SoundWire (`swr-wcd`) — o device dele vem do DT
(`soc:spf_core_platform:...`), e o mesmo truque de rebind do `spf_core` deve
criar os filhos que faltam. Depois disso o `wcd937x` enumera como slave, o card
para de deferir e `/proc/asound/cards` deve mostrar `bengal-idp-snd-card`.

### 10.16 SoundWire: por que o card ainda defere

Comparacao com o Android (mesmo DT, mesmo kernel):

| | Android | recovery (TWRP) |
|---|---|---|
| `.../sound` (card) | bound | criado, **deferred** |
| `rx_swr_ctrl`, `va_swr_ctrl` | **existem** | **nao existem** |
| bus SoundWire | `swr0`, `swr1`, 2x `wcd937x-slave.*` | **vazio** |
| driver `swr-wcd` | bound nos dois ctrl | sem device |

O `modalias` deles revela o no: `of:Nrx_swr_masterT(null)Cqcom,swr-mstr`. E esse
no **nao existe no DT estatico** — os devices `rx_swr_ctrl`/`va_swr_ctrl` sao
criados **dinamicamente pelo `bolero`** durante o probe.

No TWRP o `bolero-codec` esta bound, mas os masters nao foram criados. E nao da
para re-probar:

- o driver tem `suppress_bind_attrs` (nao existe `bind`/`unbind` no sysfs);
- `rmmod bolero_cdc_dlkm` responde "Try again" (em uso).

Tambem testamos carregar o `bolero` **depois** do ADSP de pe (ordem correta):
mesmo assim os masters nao aparecem.

### 10.17 Onde a investigacao para (precisa do fonte)

O que falta e saber **qual condicao** o `bolero` usa para criar os nos
`rx_swr_master`/`va_swr_master` (clocks? `lpass` power domain? callback do
ADSP?). Isso esta dentro de `bolero_cdc_dlkm`, que e binario fechado.

Alternativas sem fonte:
1. Testar ordem com **reboot** para cada variacao (caro; bolero nao recarrega).
2. DTB proprio com os nos `rx_swr_master`/`va_swr_master` estaticos (bypassa a
   criacao dinamica) — promissor, e mexe só no DT do nosso initramfs/boot.

### 10.18 DTB com nos estaticos: descartado por evidencia

Antes de mexer no `dtbo`, verifiquei se os nos existiriam em algum lugar para
copiar. Resultado:

1. `/proc/device-tree/soc/spf_core_platform/rx_swr_master` -> **nao existe** (nem
   no Android, com o audio funcionando);
2. varredura de **todos** os `compatible` da arvore viva do Android procurando
   `swr-mstr` -> **nenhum resultado**;
3. `dtbo.img` tem **32** overlays e o `androidboot.dtbo_idx` e **40**
   (inconsistencia que ja indica que o indice nao aponta para essa tabela).

Ou seja: os devices `rx_swr_ctrl`/`va_swr_ctrl` **nao vem do DT**. O `bolero`
os cria por codigo (`platform_device_register` com nome/modalias sintetizados).
Nao ha no para copiar, e `CONFIG_OF_OVERLAY` esta **desligado** no kernel stock.

### 10.19 Conclusao da #13-B (fim desta linha)

A cadeia completa medida no recovery:

```
spf_core -> (rebind) -> sound (card, deferred)
                          |
                          +-> precisa do componente wcd937x
                                +-> precisa de slave SoundWire  <-- AQUI
                                      +-> precisa do master swr
                                            +-> criado por bolero (fechado)
```

O `bolero` esta bound no recovery mas **nao cria os masters**. A hipotese mais
provavel (coerente com tudo): o bring-up de audio QCOM exige que o **userspace**
vote os clocks do `lpass` (o HAL faz isso no Android). Sem HAL — que e
exatamente o que a opcao B tira — nao ha quem faca o voto.

Caminhos daqui:
1. **Fonte GPL da FiiO** (`docs/45`, pedido, issue #17) — destrava `bolero`/
   `spf_core`/`machine`.
2. **Reimplementar o voto de clock/power do lpass em userspace** (equivalente ao
   HAL via QMI/GLINK) — projeto grande, e o oposto do "Linux minimo".
3. **Opcao A (RaaA)**: o Rockbox como app usa a HAL pronta — nao precisa de nada
   disso, mas perde acesso direto ao DAC/DSD.

### 10.20 GRANDE AVANCO: SoundWire de pe no recovery

Duas descobertas que mudaram tudo:

1. **Os nos `rx_swr_master`/`va_swr_master` EXISTEM no DT** — estao mais fundo do
   que eu procurei:
   `/soc/spf_core_platform/bolero-codec/rx-macro@a600000/rx_swr_master`
   (o `of_node` do device no Android aponta para la). O DTB nao precisa ser
   mexido.
2. **Faltava o `pinctrl_lpi_dlkm`.** Sem ele, o `msm-cdc-pinctrl` defer para
   sempre e o `va_macro` falha com `failed to get swr pin state` — o que
   cascateia em `rx_macro: va-macro not registered yet, defer`.

Carregando `pinctrl_lpi_dlkm` **antes** dos macros, com o ADSP de pe:

```
msm-cdc-pinctrl: bound em cdc_dmic01/23, msm_cdc_pinctrl@18, pri_mi2s, rx_swr
rx-macro -> rx_macro      va-macro -> va_macro      tx-macro -> tx_macro
rx_swr_ctrl / va_swr_ctrl  -> criados
/sys/bus/soundwire/devices -> swr0, swr1, wcd937x-slave.a01170223, ...224
```

**Igual ao Android.** A receita completa esta em `tools/audio-bringup.sh`.

### 10.21 O elo final que falta

`/sys/bus/soundwire/drivers/` esta **vazio** e os dois `wcd937x-slave` nao tem
driver. Sem o driver SoundWire do codec, o componente ASoC `wcd937x` nao
registra, o card `soc:spf_core_platform:sound` nao probeia e
`/proc/asound/cards` continua vazio.

Proximo passo: descobrir por que o `wcd937x_dlkm` nao registra o `swr_driver`
(ele registra um `platform_driver` `wcd937x_codec`, visivel em
`/sys/bus/platform/drivers/`, mas nao o driver de barramento SoundWire).
Possivelmente depende do `swr_ctrl` estar com `digital_cdc_rsc_mgr_hw_vote_enable`
ok (o dmesg mostra `return 0` nos dois masters, entao o vote passou).

### 10.22 Ordem final da cadeia (e o elo que sobrou)

Depois de varias rodadas, a ordem que faz o SoundWire enumerar:

```
pinctrl_lpi_dlkm -> swr_dlkm -> swr_ctrl_dlkm -> bolero_cdc_dlkm
 -> va_macro_dlkm -> rx_macro_dlkm -> tx_macro_dlkm
 -> mbhc_dlkm -> wcd9xxx_dlkm -> wcd_core_dlkm
 -> wcd937x_dlkm -> wcd937x_slave_dlkm -> machine_dlkm
```

Cada erro de ordem que apareceu no caminho:

| faltando antes | erro |
|---|---|
| `pinctrl_lpi_dlkm` | `msm-cdc-pinctrl` defer -> `va_macro: failed to get swr pin state` |
| `swr_dlkm`/`swr_ctrl_dlkm` | `va_macro_dlkm: Unknown symbol swrm_wcd_notify` |
| `mbhc_dlkm` | `wcd937x_dlkm: Unknown symbol wcd_mbhc_init` |

Com a ordem certa:

```
va_swr_ctrl criado
/sys/bus/soundwire/devices: swr0 + wcd937x-slave.a01170223 -> driver wcd937x-slave
```

### 10.23 O elo final: voto de clock do lpass falha

```
swr-wcd va_swr_ctrl: swrm_request_hw_vote: lpass audio hw enable failed
swr-wcd va_swr_ctrl: swrm_core_vote_request: core vote request failed
```

E exatamente a hipotese do §10.19: sem o **voto de clock do lpass**, o master
SoundWire nao habilita o hardware, o codec nao completa o registro e o card nao
nasce. (Numa rodada anterior o mesmo voto retornou 0 — entao ele depende do
estado de ordem/energia do lpass, nao e impossivel.)

Proximo: achar quem liga o `lpass` (GDSC/`lpass_audio_hw` clock controller) e se
da para faze-lo pelo sysfs antes dos macros.

### 10.24 Voto do lpass: causa e o que ficou funcionando

O erro `init failed or vote handle NULL` tem causa clara:

```
[45.675] va_macro: digital_cdc_rsc_mgr_hw_vote_enable: return 0     <- OK
... rebind do spf_core ...
[45.678] digital_cdc_rsc_mgr_hw_vote_enable: init failed or vote handle NULL
```

**O rebind do `spf_core` destroi o handle de voto do RSC.** Ele e necessario para
criar o device `sound`, mas derruba o estado do `bolero-clk-rsc-mngr`.

Recarregando os macros **depois** do rebind (novo probe contra o manager novo),
o estado final fica completo:

```
rx_swr_ctrl, va_swr_ctrl            criados
/sys/bus/soundwire/devices          swr0, swr1, wcd937x-slave .223 e .224
                                    (ambos ligados no driver wcd937x-slave)
sound (card)                        existe, mas SEM driver
/proc/asound/cards                  vazio
devices_deferred                    vazio (nao e defer)
```

### 10.25 Onde travou (e por que)

O device `sound` casa com o driver (`modalias` = `of:NsoundT(null)Cqcom,bengal-asoc-snd`,
alias do driver igual), `driver_override` aceito, `drivers_probe` retorna 0 —
**e nada acontece: sem bind, sem mensagem no dmesg, sem deferred**.

Ou seja: o probe do `bengal-asoc-snd` roda (ou e chamado) e retorna sem registrar
o card, silenciosamente. Sem log e sem fonte do `machine_dlkm`, nao da para saber
a condicao que falta.

Suspeitas, em ordem: `qcom,msm_audio_ssr_devs` (SSR) nao pronto; alguma
`asoc-codec-names` nao registrada como componente ASoC; ou o driver so registrar
o card quando o `fe_be_cc`/`lpass` estiver em estado especifico.

Receita ate aqui: `tools/audio-bringup.sh` (com a ordem critica documentada).

### 10.26 Kprobes: a ferramenta que faltava

O kernel stock tem `CONFIG_KPROBES=y` e `CONFIG_KPROBE_EVENTS=y` (mas
`CONFIG_FUNCTION_TRACER` esta off). Montando tracefs da para tracar funcoes de
modulo por **nome**:

```
mount -t debugfs none /sys/kernel/debug
mount -t tracefs nodev /sys/kernel/debug/tracing
echo 'p:mp msm_asoc_machine_probe'          >> tracing/kprobe_events
echo 'r:mr msm_asoc_machine_probe ret=$retval' >> tracing/kprobe_events
echo 'r:sc snd_soc_register_card ret=$retval'   >> tracing/kprobe_events
```

Trace obtido ao forcara o probe do card:

```
mp: msm_asoc_machine_probe+0x0
sc: snd_soc_register_card ret=0xfffffdfb   <-- -517 = -EPROBE_DEFER
mr: msm_asoc_machine_probe ret=0xfffffdfb
```

**O probe do machine roda e defere dentro de `snd_soc_register_card`.**

### 10.27 Por que defere: componentes ASoC faltando

O DT (`/proc/device-tree/.../sound/asoc-codec-names`) exige tres codecs:

```
msm-stub-codec.1
bolero-codec
fiio_codec
```

Mas `/sys/kernel/debug/asoc/components` so tem:

```
soc:fiio,dac-core
soc:snd_soc_dummy  (x2)
snd-soc-dummy      (x2)
```

**Nenhum dos tres.** Sem eles o `snd_soc_register_card` nunca completa.

### 10.28 Armadilha descoberta: recarregar os macros quebra o bolero

Num ciclo com `rmmod`/`insmod` dos macros apareceu:

```
bolero-codec: ASoC: error - multiple DAI ... registered with no name
bolero-codec: ASoC: Failed to register DAIs: -12
tx_macro: bolero_register_macro: register codec failed
```

Registrar os macros duas vezes no mesmo boot duplica as DAIs e **impede o
bolero de registrar o codec**. Ou seja: a receita tem de ser passada unica, sem
recarga — o que conflita com o rebind do `spf_core` (que recria os filhos).

### 10.29 Proximo passo

1. Verificar, numa passada limpa, se `bolero_register_macro` aparece para os tres
   macros (nesta ultima rodada nao apareceu — pode ter faltado dependencia).
2. Entender por que o `bolero-codec`, estando bound, nao registra componente
   ASoC (kprobe em `snd_soc_register_component`).
3. O `fiio_codec` vem da stack FiiO (`soc:fiio,dac-core` ja registra componente,
   mas com outro nome) — comparar com o nome que o DT pede.

### 10.30 Componentes ASoC: comparacao Android x recovery

Android (com audio funcionando, `debugfs` montado):

```
soc:spf_core_platform:bolero-codec
btfmslim_slave
soc:qcom,msm-stub-codec
soc:fiio,dac-core
soc:snd_soc_dummy x2, snd-soc-dummy x2
```

O DT do card pede (`asoc-codec-names`): `msm-stub-codec.1`, `bolero-codec`,
`fiio_codec`.

Descobertas desta rodada:

| componente | como obter | estado |
|---|---|---|
| `soc:qcom,msm-stub-codec` | **`stub_dlkm.ko`** (nao estava na nossa lista) | OK apos carregar |
| `soc:spf_core_platform:bolero-codec` | registra **so depois** que os 3 macros registram (`bolero_register_macro`) | OK numa passada limpa |
| `btfmslim_slave` | `bt_fm_slim.ko` | falha: precisa de `btpower` (`btpower_*`), que tambem falhou |
| `fiio_codec` | vem da stack FiiO (`soc:fiio,dac-core` e componente, mas com outro nome) | a mapear |

### 10.31 O no a desatar: o rebind derruba os componentes

O device `sound` so e criado pela enumeracao do `spf_core` — e ela so acontece
no **probe** dele. Como o `spf_core` carrega antes do `machine_dlkm` (dependencia
de simbolos), o rebind e necessario.

Mas o rebind **derruba os filhos** (bolero, macros) e, ao reprobar, o
`bolero-codec` **nao volta a registrar** como componente (nem com os macros
sendo descarregados antes e recarregados depois). Resultado: ou temos `sound`
sem componentes, ou componentes sem `sound`.

Caminhos para o proximo round:
1. Fazer o `sound` nascer no **primeiro** probe do `spf_core` — exigiria o
   `machine_dlkm` carregado antes, o que hoje e impossivel por simbolo.
   Alternativa: descobrir se ha outro gatilho para `spf_core_add_child_devices`
   (um notifier de SSR, por exemplo).
2. Instrumentar com kprobe o `snd_soc_register_component` no ciclo
   rebind+reload para ver onde o bolero desiste.
3. Confirmar se `bt_fm_slim`/`fiio_codec` sao realmente necessarios para o card
   (o DT lista, mas talvez o probe so precise de bolero+stub).

### 10.32 SSR nao re-dispara a enumeracao (kprobe)

Hipotese do passo 1: existiria outro gatilho para `spf_core_add_child_devices`
(um notifier de SSR). Medido com kprobe:

```
p:e spf_core_add_child_devices
p:p spf_core_platform_driver_probe
```

Procedimento: subir o ADSP (`state=running`), zerar o trace, `stop` + `start` no
remoteproc do adsp (SSR), esperar.

Resultado: **0 eventos `e:`** — o restart do ADSP nao chama a enumeracao.

Conclusao: o unico gatilho e o **probe** do driver. Entao a escolha
"`sound` sem componentes" x "componentes sem `sound`" continua, e o proximo
passo e entender por que o `bolero-codec` nao re-registra componente depois do
rebind (kprobe em `snd_soc_register_component`).

### 10.33 Componentes ok, card ainda defere — e faltam as DAIs q6

Depois de acertar os componentes, o estado ficou **igual ao Android** (menos
`btfmslim_slave`):

```
soc:spf_core_platform:bolero-codec
soc:qcom,msm-stub-codec
soc:fiio,dac-core  (+ dummies)
```

E, mesmo assim, o trace continua:

```
mp: msm_asoc_machine_probe
sc: snd_soc_register_card ret=0xfffffdfb   (-EPROBE_DEFER)
mr: msm_asoc_machine_probe ret=0xfffffdfb
```

Olhando as **DAIs** registradas (`/sys/kernel/debug/asoc/dais`, 18 no total):

```
tx_macro_tx1..3, rx_macro_rx1..6, rx_macro_echo, va_macro_tx1..2
msm-stub-rx, msm-stub-tx
soc:fiio,dac-core
fiio-snd-soc-dummy-dai
snd-soc-dummy-dai
```

**Zero DAIs `q6`/AFE** (`grep -ic q6` = 0). O card do bengal liga as rotas nos
DAIs do **Q6 AFE** (`msm-dai-q6-afe*`), que vem do `audio_pkt_dlkm`/`q6_dlkm` —
carregados, mas sem registrar DAI.

Proximo passo: comparar a lista de DAIs com o Android (qual `msm-dai-q6-*`
existe la) e descobrir qual modulo registra essas DAIs — provavelmente o mesmo
padrao: falta carregar algo (`audio_pkt_dlkm` ja esta) ou a ordem.

### 10.34 DAIs: a diferenca com o Android (medida)

`/sys/kernel/debug/asoc/dais` nos dois lados:

| | Android | TWRP |
|---|---|---|
| `tx_macro_tx1..3` | 3 | 3 |
| `rx_macro_rx1..6` + echo | 7 | 7 |
| `va_macro_tx1..2` | 2 | 2 |
| **`va_macro_tx3`** | **sim** | **nao** |
| **`btfm_*` (4 DAIs)** | **sim** | **nao** |
| stub/fiio/dummy | sim | sim |
| total | 22 | 18 |

Duas diferencas, com pesos bem diferentes:

1. **`btfm_*`** vem do `bt_fm_slim`, que precisa do `btpower`, que precisa de
   `cnss_utils_update_device_type` (stack de WLAN). Carregar conectividade no
   recovery e outro projeto — e essas DAIs sao de **Bluetooth SCO/FM**, nao de
   playback. Provavelmente nao sao o bloqueio.
2. **`va_macro_tx3`** falta mesmo com `bolero_register_macro: successful:3`.
   E a diferenca que sobra do lado do audio.

### 10.35 Proximo passo

Descobrir por que o `va_macro` registra 2 DAIs em vez de 3. Suspeitas: numero de
DMICs lido do DT (`va-macro@a730000`), ou ordem de registro dos macros (o
`tx_macro`/`rx_macro` entram antes e ocupam indices).

Metodo: comparar as propriedades do no `va-macro@a730000` (Android x TWRP, que
devem ser iguais por virem do mesmo DT) e tracar `snd_soc_register_dai` durante
o probe do `va_macro` para ver quantas chamadas acontecem e com que retorno.

### 10.36 Dependencia circular suspeita entre machine e macros

Ao tentar tracar o registro de DAIs do `va_macro`, o `insmod` falhou com:

```
va_macro_dlkm: Unknown symbol msm_cdc_pinctrl_get_state
va_macro_dlkm: Unknown symbol msm_cdc_pinctrl_select_active_state
```

Procurando quem define esses simbolos nos modulos do `vendor_dlkm`:

| modulo | ocorrencias do simbolo |
|---|---|
| `pinctrl_lpi_dlkm` | 0 |
| `pinctrl_msm` | 0 |
| **`machine_dlkm`** | **3** |

Ou seja: os macros dependem de simbolos que aparecem no `machine_dlkm`, e o
`machine_dlkm` depende de simbolos dos macros (`bolero_register_wake_irq`,
`wcd937x_*`). Isso **parece** circular.

Observacao importante: numa rodada anterior os macros carregaram normalmente com
o `machine_dlkm` ainda **nao** carregado — entao a dependencia real deve estar em
outro lugar (talvez `pinctrl_lpi_dlkm` exporte com nome diferente, ou o
`machine_dlkm` apenas **importe** esses simbolos e o exportador seja o kernel
base).

### 10.37 Onde paramos

Estado confirmado em rodadas anteriores: componentes ASoC iguais ao Android,
`sound` criado, card deferindo por DAI/codec faltante; diferenca de DAIs reduzida
a `va_macro_tx3` + 4 DAIs de Bluetooth (estas inviaveis: `bt_fm_slim` ->
`btpower` -> `cnss_utils` da WLAN).

Proximo passo objetivo: numa passada limpa **sem** `machine_dlkm`, verificar se
os macros carregam e se `va_macro_tx3` aparece; e confirmar com
`grep -l msm_cdc_pinctrl_select_active_state` em todos os `.ko` do vendor_dlkm
qual e o exportador real.

### 10.38 A ordem correta e: machine ANTES dos macros

Confirmado por medicao: `msm_cdc_pinctrl_*` **nao existe** no kernel rodando
(`grep -c` em `/proc/kallsyms` = 0) e, entre os `.ko` do `vendor_dlkm`, so
aparece em **importadores** (`machine_dlkm`, `rx/va/tx_macro_dlkm`,
`wcd937x_dlkm`). Quem exporta e o **`machine_dlkm`**.

Logo a ordem certa e:

```
... bolero -> mbhc -> wcd9xxx -> wcd_core -> wcd937x -> wcd937x_slave
    -> machine_dlkm            <-- exporta msm_cdc_pinctrl_*
    -> va_macro / rx_macro / tx_macro
```

Testado: com essa ordem os tres macros carregam (`va=1 rx=1 tx=1`).

### 10.39 Novo detalhe: a enumeracao do spf_core nao criou filhos

Nessa mesma rodada, depois do rebind, `/sys/bus/platform/devices` ficou **sem
nenhum filho** do `spf_core` (nem os pinctrl, nem o `sound`) — e o `dmesg` nao
mostrou `enumarate machine driver`. O driver `spf-core-platform` continua bound.

Nas rodadas anteriores o rebind criava `sound`. Hipotese: a enumeracao depende
do ADSP ja estar `running` no momento do probe do `spf_core` (nesta rodada o
ADSP sobe depois do `spf_core` carregar).

Proximo passo: subir o ADSP antes do `spf_core` carregar — o que exige o
`adsp_loader`, que depende do `spf_core`. Se confirmar-se o ciclo, a saida e
rebindar o `spf_core` **depois** do ADSP estar de pe e conferir o `dmesg` da
enumeracao imediatamente.

### 10.40 Duas regras de ordem provadas (e o estado final da rodada)

1. **`machine_dlkm` antes dos macros** — ele exporta `msm_cdc_pinctrl_*`; com ele
   carregado primeiro, `va/rx/tx_macro` carregam.
2. **ADSP `running` antes do rebind do `spf_core`** — sem o DSP de pe a
   enumeracao **nao roda** (0 filhos, nenhuma linha `enumarate` no dmesg). Com o
   ADSP de pe:

```
adsp=running
rebind -> spf_core_add_child_devices:enumarate machine driver
        -> 11 filhos criados (incluindo sound)
```

Com isso + `stub_dlkm`, os componentes ficaram **identicos ao Android** (menos
`btfmslim_slave`):

```
soc:qcom,msm-stub-codec
soc:spf_core_platform:bolero-codec
soc:fiio,dac-core  (+ dummies)
```

### 10.41 Onde esta o bloqueio agora

Mesmo com filhos, componentes e `sound` presentes, o card continua sem driver e
`/proc/asound/cards` vazio. O kprobe precisa ser rearmado a cada boot (tracefs
some) — a proxima rodada comeca rearmando e medindo `snd_soc_register_card` de
novo.

Suspeita principal agora: **`btfmslim_slave`**, a unica peca do Android que
ainda nao temos. Se o `snd_soc_register_card` continuar deferindo sem ele, ou
aceitamos o custo de carregar `bt_fm_slim`(+`btpower`+`cnss_utils`) ou o card nao
fecha.

---

## 11. MARCO: a placa de audio sobe DENTRO do recovery

Medido no aparelho, sem Android:

```
/proc/asound/cards:
 0 [bengalidpsndcar]: bengal-idp-snd- - bengal-idp-snd-card
                      bengal-idp-snd-card

/dev/snd/controlC0, pcmC0D0c ... pcmC0D14p ...
/proc/asound/pcm:
 00-05: CODEC_DMA-LPAIF_RXTX-RX-0 rx_macro_rx1-5 : : playback 1
```

O driver `bengal-asoc-snd` esta bound ao device
`soc:spf_core_platform:sound` e o card registrou.

### 11.1 A peca que faltava: a stack de Bluetooth

O ultimo `-EPROBE_DEFER` vinha de `snd_soc_add_pcm_runtime` num **DAI link de BT
SCO**. `snd_soc_find_dai` sempre achava a DAI (0 falhas), mas o **codec** do link
(`btfmslim_slave`) nao existia.

Cadeia necessaria:

```
cnss_utils (cnss_utils_update_device_type) -> btpower -> bt_fm_slim
```

`btpower` sobe depois do `cnss_utils`; `bt_fm_slim` registra o componente
`btfmslim_slave` e as 4 DAIs (`btfm_fm_slim_tx`, `btfm_bt_sco_slim_tx`,
`btfm_bt_sco_a2dp_slim_rx`, `btfm_bt_split_a2dp_slim_rx`).

### 11.2 Receita final

`tools/audio-bringup.sh` — 9 blocos, com a ordem medida:

```
1. montar /vendor, /vendor_dlkm, copiar adsp.* -> /lib/firmware
2. base DSP (spf_core antes de adsp_loader)
3. ADSP start POR NOME (o indice do remoteproc muda entre boots)
4. pinctrl_lpi -> swr -> swr_ctrl -> bolero -> mbhc -> wcd* -> MACHINE
5. rebind do spf_core (SO com ADSP running)
6. macros va/rx/tx
7. stub_dlkm
8. cnss_prealloc -> cnss_utils -> btpower -> bt_fm_slim
9. drivers_probe no device 'sound'
```

### 11.3 O que isso significa para a opcao B

O audio **existe e funciona fora do Android**: kernel stock, modulos do vendor,
ALSA com PCM de playback. Nao foi preciso kernel proprio nem HAL.

O que falta para "Linux minimo tocando":
1. um `aplay`/player no userspace (o TWRP nao tem);
2. a rota de mixer (escrever `mixer_paths_bengal_idp.xml` nos kcontrols) — o
   card existe, mas a rota precisa ser aberta;
3. UI/initramfs proprio (o TWRP serviu de bancada).

Ou seja: o item mais arriscado da opcao B (audio sob Linux) **deixou de ser
risco**.

### 11.4 Player e mixer funcionando; playback barrado por um gate do driver

`tinyplay` e `tinymix` compilados do AOSP (`external/tinyalsa`) e empurrados
para o ramdisk do TWRP (sem reflashar):

```
$ tinymix
Mixer name: 'bengal-idp-snd-card'
Number of controls: 160
... DAC Playback Volume / DAC PO Gain / DAC Digital Filter Mode   <- controles do cs43198
```

Ou seja: **mixer 100% acessivel**, incluindo os controles do DAC da FiiO.

Ao tentar tocar (`tinyplay test440.wav -D 0 -d N`), todos os PCMs recusam com:

```
bengal-asoc-snd ...: check_userspace_service_state: pcm_id 5 state 0
  -> tinyplay: "Error playing sample"
```

O `machine_dlkm` **exige que o "userspace audio service" esteja registrado**
antes de abrir qualquer PCM. E o gate e interno:

- nao ha parametro de modulo (`/sys/module/machine_dlkm/parameters` nao existe);
- nao ha atributo em sysfs no device do card;
- nao ha property lida (as strings do modulo nao mostram nenhuma);
- a mensagem companheira e `"%s userspace service crashed"`, tipica de SSR do
  audio.

Hipotese: esse flag e setado pelo **HAL** (userspace QCOM) via ioctl/notifier no
`audio_pd` do ADSP. Ou seja: mais um gate que existe justamente porque o HAL
"avisa" que esta vivo.

### 11.5 Onde a opcao B para (e o que faltaria)

Estado: card ✓, mixer ✓, PCM nodes ✓, player ✓ — **falta o gate do
`check_userspace_service_state`**.

Caminhos:
1. Descobrir o canal do "userspace service" (kprobe em
   `check_userspace_service_state` para ver o que ele le; ou procurar o misc
   device que o machine driver cria quando o `audio_pd` sobe).
2. Implementar um "stub de HAL" minimo que faca esse registro (pode ser so abrir
   um device/ioctl uma vez).

### 11.6 Investigando o gate do userspace service (sem sucesso ainda)

Tentativas desta rodada:

| caminho | resultado |
|---|---|
| parametros de modulo | `/sys/module/machine_dlkm/parameters` **nao existe** |
| atributo sysfs no card | so os dirs de PCM + padroes (`uevent`, `power`...) |
| property lida pelo modulo | as strings nao mostram nenhuma (`props`/`property` so em mensagens de DT) |
| simbolo no `.ko` | `check_userspace_service_state` **nao esta** no symtab (80 FUNC) — foi inlinado; so existe como texto de log |
| desmontagem | a string esta em `.rodata+0x44` e em `.debug_str`; o `objdump -dr` nao resolveu a referencia de forma util |

Conclusao: o flag e interno ao `machine_dlkm` e e setado por algo externo
(provavelmente o HAL, quando o **`audio_pd`** do ADSP sobe e o servico de audio
do userspace se registra — a mensagem companheira e
`"%s userspace service crashed"`, tipica de SSR).

Proximo passo mais promissor: **comparar `/dev` e `/sys` entre Android e TWRP**
procurando o canal de registro (um misc device ou um notifier de `audio_pd` que
existe no Android e nao no recovery).

### 11.7 Gate do userspace service: mais testes negativos

| teste | resultado |
|---|---|
| diff completo de `/dev` (Android x TWRP) | nenhuma diferenca de device de audio |
| abrir `/dev/aud_pasthru_adsp` e entao tocar | `state 0` continua — nao e esse device |
| receita completa + probe | card sobe, mas o probe precisa de **retry** (rodada em que o BT ainda subia) |

Aprendizados operacionais ja incorporados em `tools/audio-bringup.sh`:
- o passo 9 agora **insiste** no `drivers_probe` (ate 10x, 2 s);
- o script avisa que `tinyplay`/`tinymix`/`libtinyalsa.so` e o WAV de teste **nao
  vivem no ramdisk** — precisam de push a cada boot (ou entrar na imagem).

### 11.8 CORRECAO: o gate nao era o `userspace_service` (REA/Ghidra no `machine_dlkm.ko`)

Desmontagem com REA/Ghidra 12.1.2 do `machine_dlkm.ko` (sha256 `259c8c3d...`).

**O que o `check_userspace_service_state` realmente e:** um helper *inline*,
usado dentro de `msm_common_snd_shutdown` (0x109fa0), que apenas **relata** o
estado de streaming daquele PCM:

```c
plVar14 = mach_data;
_dev_info(dev, "%s: pcm_id %d state %d\n", "check_userspace_service_state",
          pcm_id, *(char *)(*plVar14 + pcm_id));
if (*(char *)(*plVar14 + pcm_id) == 1) {          /* == "estava tocando" */
    printk("%s userspace service crashed\n", ...);
    spf_core_apm_close_all();
    msm_audio_ion_crash_handler();
    *(char *)(*plVar14 + pcm_id) = 0;              /* limpa */
}
```

Ou seja: `state 0` significa **"esse PCM nao estava tocando"** — e nao
"servico ausente". O `shutdown` roda porque o open falhou depois. **A mensagem
era um relatorio, nao o portao.**

**Canal kernel<->userspace que existe de fato** (`snd_card_sysfs_init`, 0x1093c0):

```c
kobject_init_and_add(pdata, &snd_card_ktype, kernel_kobj, "snd_card");
sysfs_create_file_ns(pdata, &card_state_attr, 0);
/* store: sscanf(buf, "%d", &pdata->card_status); sysfs_notify(..., "card_state"); */
```

=> `/sys/kernel/snd_card/card_state` (existe no TWRP, leitura inicial **1**).
E o canal **kernel -> userspace** (`snd_card_notify_user` seta o status e
notifica). Nao e o registro do HAL.

**Onde a falha realmente esta (kprobes):**

| funcao | retorno |
|---|---|
| `snd_pcm_open` | **0** (abre!) |
| `msm_common_snd_startup` | **0** |
| `msm_common_snd_hw_params` | **0** |
| prepare / trigger / write | *(nao medido — proximo passo)* |

O `tinyplay` falha em **"Error playing sample"** depois de todos esses passarem:
o PCM abre, o machine driver aceita, e a falha esta em **prepare/trigger/write**
— isto e, o DSP recusa iniciar o stream, nao o ALSA.

Consequencia pratica: a frente "stub de HAL" que eu propus **nao e o caminho**.
O caminho e achar por que o `spf_core`/DSP recusa o `RUN` (provavelmente
topologia/calibracao ACDB ausente, que e justamente o que o HAL carregaria).

### 11.9 Onde exatamente falha: write devolve -EINVAL

Instrumentamos o `tinyplay` (`pcm_get_error`) e medimos a cadeia ALSA com kprobes:

| etapa | retorno |
|---|---|
| `snd_pcm_open` | 0 |
| `msm_common_snd_startup` | 0 |
| `snd_pcm_hw_params` / `msm_common_snd_hw_params` | 0 |
| `snd_pcm_prepare` | 0 |
| **write (`SNDRV_PCM_IOCTL_WRITEI_FRAMES`)** | **-EINVAL** (`cannot write initial data: Invalid argument`) |
| `snd_pcm_trigger` | nunca chamado |

Periodo minimo do device: 512 frames (`-p 256` e recusado com
"device only supports >= 512 frames"); com 512/1024/2048 o erro e sempre o
mesmo `-EINVAL`. Ou seja, **nao e tamanho de buffer**.

Leitura: o stream do DSP nunca foi realmente aberto no `hw_params` — o machine
driver devolve 0 sem configurar o `spf_core`, e o `copy` do PCM falha com
EINVAL porque o runtime nao tem DMA/stream do lado do ADSP. E exactamente o que
o HAL faria antes de qualquer `write`.

Nota de metodo: os simbolos `audio_pcm_*` do kallsyms sao do gadget USB (UAC),
nao do DSP — nao servem para tracar este caminho.

### 11.10 CAUSA RAIZ: falta o *platform component* do ASoC (o DSP nao tem ops)

```
$ cat /sys/kernel/debug/asoc/platforms
                                  <-- VAZIO

$ cat /sys/kernel/debug/asoc/components
btfmslim_slave
soc:qcom,msm-stub-codec
soc:spf_core_platform:bolero-codec
soc:fiio,dac-core
soc:snd_soc_dummy  (x2) ...
                                  <-- NAO existe componente spf_core/platform
```

O driver `spf-core-platform` **esta** registrado e vinculado ao device
`/sys/bus/platform/devices/soc:spf_core_platform` (modulo `live`, refcnt 8), mas
ele **nao registrou o platform component no ASoC core**.

Consequencia mecanica, que explica todos os numeros da §11.9:

| etapa | com platform component | sem platform component |
|---|---|---|
| `snd_pcm_open` | 0 | 0 |
| `hw_params` | configura o DSP | **no-op** (devolve 0) |
| `prepare` | 0 | 0 |
| `write` | entrega ao DSP | **-EINVAL** (sem `dma_area`/`copy`) |

Ou seja: nao havia gate nenhum — o PCM estava **oco**. O `check_userspace_service_state`
da §11.8 era apenas o boletim do shutdown, como o Ghidra ja tinha mostrado.

Proximo passo: no `spf_core_dlkm.ko`, ver sob que condicao o
`devm_snd_soc_register_component` e chamado (provavelmente amarrado ao
`spf_core_is_apm_ready`), e o que falta para o APM subir.

### 11.11 O kernel do JM21 nao tem *platform component* nenhum (card e uma casca)

Varreduras no aparelho com o card de pe:

```
$ ls /sys/bus/platform/drivers | grep -i pcm      -> (vazio, entre 264 drivers)
$ cat /sys/kernel/debug/asoc/platforms            -> (vazio)
$ ls /sys/kernel/debug/asoc/<card>/               -> btfmslim_slave, soc:fiio,dac-core,
                                                     soc:qcom,msm-stub-codec,
                                                     soc:snd_soc_dummy (x2),
                                                     soc:spf_core_platform:bolero-codec
```

Os 12 filhos do `spf_core_platform` **todos** tem driver (`spf-core-platform`,
`bolero-codec`, `msm-cdc-pinctrl` x6, `qcom-lpi-pinctrl`, `msm-audio-ion`,
`bengal-asoc-snd`). O `spf_core_dlkm.ko` **nao importa**
`devm_snd_soc_register_component` — so faz `of_platform_populate` — entao ele
nao registra platform nenhum: quem deveria registrar sao os filhos, e nenhum
registra.

Nos 219 `.ko` do firmware nao existe nenhum driver de PCM de DSP
(`msm-pcm-q6-v2` e afins). Os modulos que registram componente ASoC sao:
`bolero_cdc`, `bt_fm_slim`, `dac_core_module` (FiiO), `fiio_snd_soc_dummy_dai`
(FiiO), `stub_dlkm`, `wcd937x`, `wsa881x`.

E nenhum deles importa `snd_pcm_lib_*` (alocacao de DMA) — ou seja, **nenhum
deles e um platform de PCM**.

Consequencia: o card `bengal-idp-snd-card` monta (codecs + DAIs) mas usa o
platform *dummy*; por isso `hw_params` e no-op, `prepare` e no-op e **qualquer**
PCM devolve `-EINVAL` no write — testamos 5, 6, 14, 16, 18: todos iguais.

Proximo passo (precisa de reboot para Android): descobrir **por onde o Android
toca de verdade** — `/proc/asound/cards` (tem mais de um card?),
`/proc/asound/pcm`, e qual processo segura o PCM aberto. O caminho do DAC da
FiiO (`cs43198.ko` + `fpga_audio_interface.ko` + `gw_fpga`) pode nao ser ALSA.

### 11.12 DESCOBERTA: o audio do JM21 nao passa por ALSA — e FPGA -> cs43198

Comparacao Android x TWRP no mesmo boot/card:

| | Android | TWRP |
|---|---|---|
| `/proc/asound/cards` | 1 card (`bengal-idp-snd-card`) | igual |
| `/proc/asound/pcm` | mesmos 25 PCMs (**com `msm-stub-rx`**) | igual |
| `/sys/kernel/debug/asoc/platforms` | **arquivo nao existe** | existe e vazio |
| `/sys/kernel/debug/asoc/components` | mesmos codecs | igual |

O Android tambem **nao tem platform component**. Ou seja: nenhum dos dois toca
por ALSA PCM — os PCMs do card sao stubs de verdade.

O caminho real, encontrado nos devices/processos do Android:

```
/dev/usb_dac            misc 10:121, root, criado por gw-fpga.ko
                        (fpga_enter_usb_dac_mode, ioctls FPGA_AUDIO_*)
processos               android.hardware.audio.service_64, audioadsprpcd,
                        uaudio_svc, media.audio.qc.codec
```

`gw-fpga.ko` expoe uma **API de audio por ioctl**:

```
FPGA_AUDIO_PCM  FPGA_AUDIO_DSD  FPGA_AUDIO_DOP
FPGA_I2S_BIT_16 / _24 / _32      FPGA_I2S_FORMAT_L ...
FPGA_AUDIO_HAL_CH_I2S_CH_{SOC,UAC,BT,HDMI,OPT,SPDIF}
FIIO_CONFIG_FPGA_CONTRL_{POWER_ON,READ_REG,GET_INFO}
```

Leitura: o caminho de playback e **userspace -> /dev/usb_dac (ioctl) -> FPGA ->
I2S -> cs43198**. O `DAC Playback Volume`/`DAC PO Gain` que vimos no `tinymix` sao
o controle do codec; o *transporte* e o FPGA.

Consequencia para a opcao B: **nao e ALSA que falta — e um cliente do FPGA.**
O caminho minimo passa a ser: abrir `/dev/usb_dac`, por o FPGA em modo DAC
(`fpga_enter_usb_dac_mode`), selecionar canal I2S SOC/bit depth e alimentar
`FPGA_AUDIO_PCM` com os frames.

Proximo passo: extrair o ABI dos ioctls (struct sizes/campos e numeros) por
REA/Ghidra no `gw-fpga.ko`.

### 11.13 O caminho de audio real: HAL -> /dev/aud_pasthru_adsp (pacotes GPR) -> ADSP

O que o HAL de audio do Android tem aberto (pid 1054,
`android.hardware.audio.service_64`):

```
/dev/aud_pasthru_adsp     <-- o caminho de dados
/dev/msm_audio_ion         <-- buffers ION
/dev/snd/control           <-- so controle de mixer
```

Confirmacao por `audio_pkt_dlkm.ko` (quem cria o device). O `write()` do
dispositivo recebe um **pacote GPR** (`audio_pkt_write`, 0x1018b0):

```c
count >= 0x18 && count <= 0x1000
hdr.header >> 8   == tamanho minimo exigido
hdr.opcode == 0x100100c   -> pacote de dado:
       count >= 0x2c
       audpkt_chk_and_update_physical_addr(pkt)   /* VA -> PA, buffer ION */
gpr_send_pkt(handle, pkt)                          /* -> ADSP */
```

E no lado do FPGA (`fpga_audio_interface.ko`, driver **I2C** do FPGA):

```
"AUDIO_LINK: set input channel to soc|xmos|bt"
"AUDIO_LINK: pcm mode, rate %d, bits %d"
AUDIO_DAC_MCLK_22 / _45 / _90
FIIO_CONFIG_FPGA_CONTRL_POWER_ON / READ_REG / GET_INFO
```

Isto e: o SoC manda I2S, o FPGA chaveia/relogia (MCLK, formato) e entrega ao
cs43198. O `hw_params` de verdade acontece **no APM do ADSP**, via pacotes.

### 11.14 Consequencia para a opcao B (avaliacao honesta)

O que falta para tocar audio fora do Android **nao e um driver de ALSA** — e um
**cliente GPR/APM minimo**:

1. alocar buffer ION (`/dev/msm_audio_ion` ou `dma_heap`);
2. `open("/dev/aud_pasthru_adsp")`;
3. enviar os pacotes de controle (media format / shared-mem map / run) com
   `opcode` e `hdr.header >> 8` corretos;
4. enviar `opcode 0x100100c` com os frames, atualizando VA->PA;
5. configurar o FPGA por I2C (`set input channel to soc`, mclk, bits).

O passo 3 e o dificil: os opcodes/campos do APM nao estao documentados no
modulo (so existe o caso `0x100100c`), e teriam de ser descobertos por
observacao do HAL em execucao (kprobe em `audio_pkt_write` para capturar os
pacotes que o Android envia durante um playback real).

**Rota mais barata para descobrir o protocolo:** kprobe em `gpr_send_pkt` /
`audio_pkt_write` no Android durante uma musica, despejando os primeiros bytes
de cada pacote. Isso da o vocabulario exato sem engenharia reversa as cegas.
