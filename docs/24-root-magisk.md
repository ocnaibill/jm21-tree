# 24 — Root no JM21 (Magisk em `init_boot`) — avaliação e procedimento

> **Status: preparado, não executado.** Nenhuma escrita foi feita no aparelho.

## 1. Vale a pena? — avaliação honesta

| O que o root destrava | Já temos sem root? | Ganho |
|-----------------------|--------------------|-------|
| Lista real de kcontrols (`tinymix`) | não | **confirma** os 7 de 12 da HAL |
| Dump de regmap (`OUT_FS`, `+1dB_EN`, código de volume) | não | **confirma** o modelo de registrador |
| Conteúdo da `fiioconfig` (`mmcblk0p71`) | não | **desconhecido real** |
| `i2cdetect` | sim (via `/sys/bus/i2c/devices`) | nenhum |
| Topologia / ganho analógico | — | **não depende de root** (é medição) |
| Modo de processamento, taxas, volume | — | **não depende de root** (logcat/sysfs) |

Conclusão: root é **útil, não bloqueante**. O único item que ele resolve e que
não temos por outro caminho é o **layout da `fiioconfig`**; o resto é confirmação
de modelo.

**Ordem recomendada:** primeiro a rodada sem root (só falta o fone), depois o
root. Se algo sair do previsto no root, já teremos os dados de bancada salvos.

## 2. Risco real

| Risco | Probabilidade | Impacto | Mitigação |
|-------|---------------|---------|-----------|
| `init_boot` patchado não boota | baixa | bootloop recuperável | `fastboot flash init_boot` com o original (temos, hash conferido) |
| Flashar slot errado | baixa | slot errado não boota | slot atual é **`_a`**; comando explícito `init_boot_a` |
| Imagem patchada errada | baixa | bootloop | patch feito **no próprio aparelho** pelo Magisk, a partir do `init_boot` do build exato |
| Perder dados | nula | — | não formatamos nada; `userdata` intocado |
| Brick de bootloader | **nula** | — | `abl`/`xbl`/`vbmeta` **não são tocados** |

Pré-condições já verificadas `[FW-DEV]`:

```
slot ativo           : _a
verifiedbootstate    : orange        (bootloader destravado)
flash.locked         : 0
Android              : 13
kernel               : 5.15.41-android13-8-g9ded8564ff52-dirty
init_boot (OTA 1.1.1): 858655e7e516224aebc441ea782c3a41c5b9ac87d0e8deb285842e8c0deedbd4
AVB digest conferido : 8621c46e...6e4e  (bate com salt)
```

## 3. Procedimento (quando decidirmos)

### 3.1 Preparar no aparelho

```bash
# 1. enviar o init_boot ORIGINAL do build 1.1.1 para o Download
adb push dumps/fw-1.1.1/init_boot.img /sdcard/Download/init_boot.img

# 2. instalar o Magisk oficial (APK baixado do repo topjohnwu/Magisk v30.7)
adb install -r analysis/magisk/Magisk-v30.7.apk
```

No aparelho: abrir **Magisk → Instalar → “Selecionar e corrigir um arquivo”** →
escolher `Download/init_boot.img` → ele grava
`Download/magisk_patched-<timestamp>.img`.

```bash
# 3. trazer a imagem patchada
adb pull /sdcard/Download/magisk_patched-XXXXX.img .
ls -l init_boot.img magisk_patched-XXXXX.img    # tamanhos devem ser próximos
```

### 3.2 Flashar (única escrita)

```bash
adb reboot bootloader
fastboot devices                 # deve listar o aparelho
fastboot getvar current-slot     # confirmar "_a"
fastboot flash init_boot_a magisk_patched-XXXXX.img
fastboot reboot
```

### 3.3 Verificar

```bash
adb shell su -c id               # uid=0(root)
adb shell getenforce             # continua Permissive
adb shell magisk -v 2>/dev/null || adb shell su -c 'magisk -v'
```

### 3.4 Rollback (se qualquer coisa sair errada)

```bash
# ainda com fastboot acessível (o bootloader não é afetado)
fastboot flash init_boot_a dumps/fw-1.1.1/init_boot.img
fastboot reboot
```

Se o `fastboot` não responder, o caminho é o de sempre: recovery + sideload do
OTA 1.1.1 (assinado, já validado por AVB).

## 4. O que faremos — e o que NÃO faremos

**Faremos, com root:**
1. `tinymix -D 0` → lista de kcontrols (fecha 7 de 12).
2. `cat /sys/kernel/debug/regmap/*/registers` → `0x80000`, `0x90000-0x90004`,
   `0x70000-0x70004` e validação do código de volume.
3. `dd if=/dev/block/by-name/fiioconfig` → dump do blob (layout, SN/NB, checksum).
4. `i2cdetect` como confirmação independente (já temos via sysfs).
5. Conferir o `init_boot_a` do aparelho contra o nosso (fecha a dúvida de build).

**NÃO faremos:** `fastboot flashing unlock/lock`, flash de `boot`, `vbmeta`,
`abl`, `xbl`, `modem`, `persist`, `userdata`; `reboot edl`; `remount`; escrita
em partição alguma além de `init_boot_a`.

## 5. Pré-requisitos de decisão

- [ ] Rodada sem root concluída (com fone plugado) e dados salvos
- [ ] Confirmação de que o aparelho pode ser formatado (já confirmado pelo dono)
- [ ] `adb` e `fastboot` funcionando com as regras udev
- [ ] `analysis/magisk/Magisk-v30.7.apk` (sha256 `e0d32d21…ebd5`) disponível
