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
