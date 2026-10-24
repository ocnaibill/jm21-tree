# 49 — Roteiro da sessão 3 (o que rodar no aparelho)

> Ordem de execução quando o JM21 estiver disponível (USB preferido; Wi-Fi como
> alternativa). Cada item tem o comando e o resultado esperado. Tudo aqui é
> **read-only** ou RAM-boot, salvo onde marcado **(write, pedir aprovação)**.

## 0. Preparação
```bash
adb devices            # esperado: 18d1:4ee2 (USB) ou IP:porta
adb shell uname -r     # 5.15.41-g9ded8564ff52-dirty (stock ou nosso? ver data)
adb shell cat /proc/version   # a data de compilação diz qual kernel está rodando
```

## 1. #22 — térmica e USB (frio × quente)
**Frio (agora):**
```bash
adb shell 'cat /sys/class/power_supply/battery/temp; cat /sys/class/power_supply/cw221X-bat/temp'
adb shell 'dumpsys battery | grep temperature'
adb shell 'for z in /sys/class/thermal/thermal_zone*; do echo -n "$(cat $z/type)="; cat $z/temp; done'
adb shell 'getprop sys.usb.config; dumpsys usb | head -20'
```
**Quente (após uso/carga):** repetir os mesmos comandos e comparar. Objetivo:
ver se `sys.usb.config` muda, se o `dumpsys usb` perde o dispositivo e o que o
`dmesg` diz (`thermal`, `throttl`, `usb.*disable`).
```bash
adb shell su -c "dmesg | grep -iE 'thermal|throttl|temp|usb.*(suspend|disable)' | tail -30"
```
**Carregador turbo:**
```bash
adb shell su -c "dmesg | grep -iE 'sgm4154|fusb302|PD |vbus' | tail -30"
adb shell 'cat /sys/class/power_supply/battery/input_current_limit; cat /sys/class/power_supply/battery/voltage_now'
```
Esperado (pelo código): PD em **5 V** (`fusb302`), JEITA do `sgm4154x` atuando;
`battery/temp` deve continuar **-61** (bug do DT) e `cw221X-bat` real.

## 2. #11 — recovery
```bash
adb reboot recovery            # mecanismo do aparelho (não grava)
```
- Se aparecer o recovery stock (ou "No command"): o caminho existe; seguir.
- Se voltar ao Android: o aparelho não entra por esse comando (ou o recovery
  está quebrado/ausente).

**Controle por fastboot (precisa de você por perto):**
```bash
adb reboot bootloader
fastboot boot /tmp/rec_stock.img    # kernel stock + ramdisk de recovery (controle)
fastboot boot /tmp/rec_ours.img     # nosso kernel + ramdisk de recovery
```
- Se o **controle** mostrar recovery e o nosso não → problema no nosso kernel.
- Se **nenhum** mostrar → o bootloader ignora o ramdisk (já observado: ele usa
  o do `init_boot`); aí só resta **(write)** `fastboot flash recovery_a` + `adb reboot recovery`.

## 3. #12 — fatos para a GSI
```bash
adb shell 'getprop ro.treble.enabled; getprop ro.vndk.version; getprop ro.product.first_api_level'
adb shell su -c 'lpdump | head -40'      # espaço livre no super
adb shell 'ls -l /dev/block/mapper/'
adb shell 'getprop ro.boot.dynamic_partitions'
```
Esperado: Treble verdadeiro, SDK 33; conferir se cabe uma GSI (~1–2 GB).

## 4. Áudio — pendências de medição
```bash
# 384k e DSD no kernel atual (se ainda for o nosso):
adb shell 'am start -a android.intent.action.VIEW -d file:///sdcard/Music/testtones/tone_384000_24.flac -t audio/flac -n com.fiio.music/com.fiio.music.activity.SplashActivity'
# DSD nativo por USB (bug): repetir com o Sonata e conferir se há som
# MQA: tocar o ny0s79 (16 bits) com analyze_mqa ligado e ver mqa.audio.type
```

## 5. `jm21ctl` (smoke test)
```bash
./tools/jm21ctl.sh status
./tools/jm21ctl.sh gain get; ./tools/jm21ctl.sh filter get
./tools/jm21ctl.sh reg read 0x90001
```

## 6. Rollback (se qualquer coisa sair do controle)
- `fastboot flash` das imagens do OTA (`boot`, `init_boot`, `dtbo`,
  `vendor_boot`, `vbmeta`, `vbmeta_system`) — `dumps/fw-1.1.1/`.
- `persist`/`fiioconfig` do backup (`device-baseline/clone-full/`).
- **Nunca** usar as imagens do slot B (build antigo).
