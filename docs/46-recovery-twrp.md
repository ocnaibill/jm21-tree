# 46 — Recovery/TWRP no JM21 (issue #11)

> Estado: **em investigação**. O recovery stock foi mapeado; a primeira tentativa
> de boot com o nosso kernel **não** apresentou a UI (o aparelho voltou ao
> Android). Falta o teste de controle.

## 1. O recovery stock

`dumps/fw-1.1.1/recovery.img` — header v4, **sem kernel** (`kernel_size: 0`),
ramdisk de 14 534 532 B (LZ4). Ou seja: o bootloader do aparelho combina o
**kernel do `boot`** com o **ramdisk do recovery** quando entra em recovery.

Conteúdo do ramdisk (extraído): um AOSP recovery completo —
`system/bin/recovery`, `adbd`, `fastbootd`, `update_engine_sideload`, `init`,
`sepolicy`, `res/`, e `init.recovery.qcom.rc`, que no `on init` escreve o
backlight do painel e liga `sys.usb.configfs 1`.

## 2. Primeira tentativa (com o nosso kernel)

Montamos `rec_ours.img` = **nosso `Image`** + ramdisk do recovery stock:

```
mkbootimg --header_version 4 --kernel Image --ramdisk rec_ramdisk -o rec_ours.img
fastboot boot rec_ours.img
Sending 'boot.img' (53904 KB)  OKAY
Booting                        OKAY
```

O bootloader aceitou, mas o aparelho **voltou ao Android** — sem UI de recovery,
sem USB, sem `adbd`. `[?]` A causa não está isolada.

## 3. Hipóteses

1. **Método**: o `fastboot boot` com kernel **e** ramdisk não funciona neste
   aparelho do jeito que funciona com a imagem só-de-kernel (o `boot.img` stock
   não tem ramdisk). O bootloader pode ignorar o ramdisk ou recusar a
   combinação.
2. **Kernel**: o nosso kernel sobe (já provado), mas o recovery precisa de algo
   que ele não tem — por exemplo, o **vendor ramdisk** (`vendor_boot`) não é
   carregado nesse modo, e o init do recovery depende dele.
3. **Recovery**: o init do recovery falha (mount/verificação) e o aparelho
   reinicia.

## 4. Teste de controle (pronto)

Imagem montada com o **kernel stock** + o mesmo ramdisk de recovery:

```
/tmp/rec_stock.img  (62 MB)
```

Se essa imagem apresentar o recovery, a culpa é do **nosso kernel**; se também
falhar, o problema é o **método** (`fastboot boot` com ramdisk).

## 5. Próximos testes (quando o aparelho estiver disponível)

1. **`adb reboot recovery`** — usa o mecanismo **do próprio aparelho** (boot
   kernel + recovery ramdisk da partição). Não grava nada. Confirma que o
   recovery stock funciona e mostra a UI.
2. **`fastboot boot /tmp/rec_stock.img`** — controle do método.
3. Se o controle funcionar: montar um recovery próprio (busybox + `adbd`, ou
   TWRP) com o **nosso kernel + os módulos necessários**.
4. Só depois considerar **gravar** `recovery_a` (`fastboot flash`) — é write, e
   precisa de aprovação.

## 6. O que um recovery próprio precisa

| Item | Situação |
|------|----------|
| Kernel | ✅ o nosso boota e é ABI-compatível |
| `adbd`/shell | ✅ o ramdisk stock já tem |
| Display (painel ST7703) | 🟨 `msm_drm.ko` + DTB do `vendor_boot`; precisa confirmar no recovery |
| Touch (fts 0x38 / gt9xx 0x5d) | 🟨 módulos em `/vendor_dlkm` (`ts_core`, `goodix_gt9xx_ts`) |
| Descriptografia (FBE) | ⬜ exige keymaster/vendor blobs; um TWRP precisaria disso |
| Partições dinâmicas (`super`) | ⬜ TWRP precisa do suporte a `super`/A/B |

## 7. Riscos

- `fastboot boot` = RAM, nada gravado; se falhar, reiniciar.
- `fastboot flash recovery_a` = write; recuperável com as imagens do OTA
  (`docs/42`).

## 8. O que realmente aconteceu no boot (medido depois)

O aparelho voltou ao Android **rodando o nosso kernel** (`ocnaibill@makise #3`,
`ro.boot.bootreason=bootloader`). Ou seja: o bootloader aceitou a imagem,
carregou o nosso kernel e bootou o **sistema** — usando o ramdisk do
**`init_boot`** e **ignorando o ramdisk do recovery** que estava no `boot.img`.

`[FATO]` Neste aparelho (GKI, header v4), `fastboot boot` com um `boot.img` que
tem ramdisk **não** troca para recovery: o ramdisk usado é o do `init_boot`.

### Consequências para a #11
Para rodar um recovery, restam dois caminhos (ambos exigem o aparelho em mãos):
1. **`fastboot flash recovery_a`** + `adb reboot recovery` (write; recuperável
   com as imagens do OTA).
2. Trocar temporariamente o **`init_boot`** pelo ramdisk de recovery
   (`fastboot flash init_boot_a`) — mais invasivo; o backup tem o `init_boot`
   stock e o patcheado (`docs/42`).

## 9. WARN observado no nosso kernel (benigno)

```
WARNING: CPU: … at kernel/workqueue.c:3102 __flush_work
Call trace:
  __flush_work → __cancel_work_timer → cancel_work_sync
  qseecom_suspend+0x100/0x130 [qseecom_dlkm]
  platform_pm_suspend → … → pm_suspend → state_store
```

`[FATO]` O aviso vem do driver vendor `qseecom_dlkm`, no caminho de **suspend**,
e não impede o suspend/resume. É independente do áudio e do Plano B; fica
registrado como ruído esperado do stack Qualcomm com o nosso kernel.

## 10. Teste `adb reboot recovery` (2026-10-24) — o recovery **entra**

```
adb reboot recovery
adb devices  →  39dc45d6  recovery
```

`[FATO]` O aparelho **entra no recovery stock** e ali permanece (estável, sem
reiniciar). O problema é o **adbd do recovery**:

```
adbd F shell_service.cpp:380] Could not set SELinux context for subprocess
libc: Fatal signal 6 (SIGABRT) ... pid 436 (adbd)
```

Todo comando de shell derruba o adbd (novo pid, mesmo erro). `adb reboot`
funciona (protocolo do host, não passa pelo shell) e devolve ao Android.

**Conclusão:** o caminho de **entrada** no recovery funciona; o que falta é um
**adbd/UI utilizável** — o recovery stock é mínimo (ramdisk sem kernel, sepolicy
incompleta). É exatamente o que um recovery próprio/TWRP resolve — e não há mais
mistério sobre "não entrar": ele entra.

## 11. Teste de controle (2026-10-25) — confirma o ramdisk ignorado

Receita usada:
```bash
unpack_bootimg --boot_img dumps/fw-1.1.1/boot.img     --out /tmp/boot_stock   # kernel 48M, ramdisk 0
unpack_bootimg --boot_img dumps/fw-1.1.1/recovery.img --out /tmp/rec_stock    # kernel 0,  ramdisk 14M
mkbootimg --kernel /tmp/boot_stock/kernel --ramdisk /tmp/rec_stock/ramdisk \
  --header_version 4 --os_version 13.0.0 --os_patch_level 2023-02 \
  --pagesize 4096 --output /tmp/rec_stock.img
fastboot boot /tmp/rec_stock.img
```

`[FATO]` Kernel **stock** + ramdisk de **recovery stock** → o aparelho voltou ao
**Android**. Ou seja: **não é o nosso kernel nem o nosso empacotamento** — o
bootloader do JM21, no `fastboot boot`, usa o ramdisk do `init_boot` e ignora o
do `boot.img`. Bate com o §8.

`[FATO]` O recovery stock **sobe pela partição** (combo **Volume− + Power**,
segurando bastante): menu "Android Recovery / qti/bengal_515 / 13/… / user/dev-keys".
O que não funciona é o **adbd** dele (§10).

**Consequência:** um recovery próprio tem de ir para a **partição** (`fastboot
flash recovery_a`) — e o alvo prático é consertar o **adbd do ramdisk**
(SELinux), não o kernel.

## 12. Tentativa de ramdisk modificado (permissivo) — não resolveu

Patch aplicado em `init.recovery.qcom.rc` (dentro do cpio newc, para preservar
tudo):

```
on early-init
    write /sys/fs/selinux/enforce 0
```

Imagem = kernel stock + ramdisk patchado (LZ4 legacy), gravada em
`recovery_a`; `fastboot reboot recovery` **entrou** no recovery, mas:

- **adbd continuou quebrando** (`Could not set SELinux context for subprocess`
  → SIGABRT) — permissivo não resolve;
- **tela preta** (só backlight) — a UI do recovery não desenhou.

`[HIP]` O erro de `setcon` é contexto **inexistente/incompatível** (não uma
negativa que o permissivo libere) — o adbd do `/system` não serve para o
recovery como está; um recovery próprio (TWRP) traz o **seu** adbd/política.

## 13. INCIDENTE: `fastboot erase misc` quebrou o slot

`[FATO]` O `misc` guarda o **`struct bootloader_message_ab`**: além do comando
(`command[32]`), ele contém `slot_suffix` e os flags de slot. Apagar a partição
inteira **zerou os metadados de slot** → o bootloader foi para o **slot B**
(sem sistema válido) e marcou **`slot-unbootable:a: yes`** → bootloop para o
recovery.

Recuperação:
```
fastboot set_active a     # volta ao slot A e limpa o unbootable
fastboot reboot
```
`[FATO]` Voltou ao Android no slot A, e o `recovery_a` stock foi restaurado
(hash conferido).

**Regra:** nunca `erase misc` neste aparelho. Para limpar um comando de BCB,
zerar **só o campo `command`** (primeiros 32 bytes) — ou usar o "Reboot system
now" do próprio recovery, que limpa corretamente.

## 14. Sessão 2026-10-25 — lições do adbd e do slot

### O que foi confirmado
- **`adb reboot recovery` entra** no recovery stock; o **combo Volume− + Power**
  (segurando bastante) também, com a **UI funcionando**.
- O **adbd do recovery quebra** em qualquer shell:
  `selinux_android_setcon("u:r:shell:s0")` falha → `LOG(FATAL)` em
  `shell_service.cpp:380` (bloco `__ANDROID_RECOVERY__`). O **file sync
  funciona** (usamos para puxar `/prop.default`, `/sepolicy`,
  `/system/bin/adbd`, `/sys/fs/selinux/enforce`, `/proc/mounts`).
- **Permissivo não foi obtido**: o cmdline `androidboot.selinux=permissive` da
  imagem é **ignorado** pelo ABL (enforce continuou 1) e o
  `write /sys/fs/selinux/enforce 0` no `init.recovery.qcom.rc` **não tem
  efeito** (provavelmente negado pela policy). `fastboot oem selinux` →
  "unknown command".
- **`fastboot boot` ignora o ramdisk** (confirmado de novo com kernel stock +
  ramdisk de recovery stock → Android).

### O erro que custou tempo: **slot B**
`getvar current-slot` = **b** em certo momento: as imagens iam para
`recovery_a`, mas o boot usava **`recovery_b`** (stock) — por isso o adbd ao
vivo continuava o original. Regra: **conferir `current-slot` antes e depois de
cada flash**.

### Formato do cpio (armadilha)
O padding do newc é relativo a **`110 + namesize`** (não só ao nome). O primeiro
rebuild gerou 351/472 entradas → recovery com tela preta. O rebuild corrigido
(473 listagens) é válido, mas a **imagem final não bootou** pelo ABL (voltou ao
fastboot) — motivo a investigar; o stock foi restaurado.

### Estado final
- Android no **slot A**; `recovery_a` e `recovery_b` com o **stock**
  (hash `a4119d50…` nos dois).
- Para um recovery utilizável: **TWRP-style** (com adbd e policy próprios) ou
  patch de policy (`allow adbd shell:process setcurrent;`) — `libsepol` já
  instalado no host para isso.

## 15. RECOVERY FUNCIONAL — shell por adb (2026-10-25)

### Achado de bônus: o **stock Android é permissivo**
`getenforce` = **Permissive** no boot stock; o `dmesg` mostra
`init: Error: Apex SEPolicy failed signature check`. O **recovery** stock, ao
contrário, sobe **enforcing** — é por isso que só lá o adbd quebra.

### A causa real do adbd
`selinux_android_setcon("u:r:shell:s0")` falha. O `sepol_compute_av` mostrou:
- `adbd → shell:process setcurrent` **negado**;
- `init → kernel:security setenforce` **negado** → o `write enforce 0` do init
  era barrado (por isso permissivo nunca funcionava).

### Receita que funciona (auto-contida no ramdisk)
1. `init.recovery.qcom.rc`: bloco `on early-init` com
   `write /sys/fs/selinux/enforce 0`.
2. `/sepolicy` do ramdisk, com `tools/sepolicy-patch.c`:
   - `allow init kernel security setenforce`
   - `allow adbd shell process setcurrent` (dispensável com permissivo,
     mas idempotente).
3. Repack do cpio (padding relativo a `110 + namesize`) + LZ4 **legacy**
   (`lz4 -l`).
4. Imagem **sem kernel** (`mkbootimg --ramdisk ... --header_version 4`),
   igual ao stock.
5. `fastboot flash recovery_a` + **`adb reboot recovery`** (o
   `fastboot reboot recovery` é não confiável neste ABL).

Resultado:
```
adb shell → uid=2000(shell) ... context=u:r:shell:s0
getenforce → Permissive
```

### Regras aprendidas
- Recovery **com kernel** quebra o **boot normal** (o ABL espera kernel-less).
- O `vbmeta` inclui o hash da `recovery`; a imagem kernel-less modificada é
  **tolerada** no boot normal. Quando for preciso mexer nos descritores, o
  vbmeta pode ser re-assinado com a **testkey do AOSP** (o aparelho é dev-keys:
  a chave pública do vbmeta é `2597c218…`).
- **Nunca** `erase misc` (metadados de slot) — §13.

Ferramenta: `tools/sepolicy-patch.c` (adiciona regra allow a policy binária;
compila com `libsepol.a`).
