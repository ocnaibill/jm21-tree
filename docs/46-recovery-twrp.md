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
