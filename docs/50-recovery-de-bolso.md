# 50 — Recovery de bolso (etapa A)

> Objetivo: **salvaguarda/rollback confiáveis** no aparelho, com o recovery
> funcionando (shell root por adb), antes de partir para o TWRP completo.

## 1. O que a imagem faz

`tools/build-recovery.sh` gera uma imagem de recovery **sem kernel** (igual ao
stock), a partir do `dumps/fw-1.1.1/recovery.img`, com três patches no ramdisk:

1. `init.recovery.qcom.rc`: `on early-init` → `write /sys/fs/selinux/enforce 0`;
2. policy (`/sepolicy`): `allow init kernel:security setenforce` +
   `allow adbd shell:process setcurrent`;
3. `prop.default`: `ro.debuggable=1`, `ro.secure=0` (habilita `adb root`).

Resultado no recovery: `adb shell` funciona e `adb root` dá `uid=0(root)`.

```
./tools/build-recovery.sh                 # -> /tmp/recovery-jm21.img
fastboot flash recovery_a /tmp/recovery-jm21.img
adb reboot recovery
adb root && ./tools/recovery-tool.sh check
```

## 2. Ferramenta (`tools/recovery-tool.sh`)

Trabalha **com o aparelho no recovery** (root por `adb root`, sem `su`):

| Comando | O que faz |
|---------|-----------|
| `check` | confere root, slot e nº de partições |
| `backup <dir> [--boot\|--all\|parts...]` | puxa as partições com `dd`, confere tamanho e grava `SHA256SUMS` + `MANIFEST.txt` |
| `restore <dir>` | verifica os hashes e regrava (pede `SIM`) |
| `flash <part> <img>` | grava uma imagem na partição (checa tamanho; pede `SIM`) |
| `shell '<cmd>'` | shell root no recovery |

O `--boot` (default) cobre a cadeia de boot + bootloader do slot atual
(`boot`, `init_boot`, `dtbo`, `vendor_boot`, `vbmeta`, `recovery`,
`vbmeta_system`, `xbl`, `abl`). O `--all` puxa as **94** partições (dezenas de
GB) — use só com espaço.

## 3. Testes feitos (2026-10-25)

- `backup` de `dtbo_a` (24 MB) e `vbmeta_a` (64 KB): hashes conferem; o
  `vbmeta_a` e os 8 MB iniciais do `dtbo_a` batem com o clone/OTA.
- `flash vbmeta_a` (mesmo conteúdo): hash na partição confere depois.
- `adb root` → `uid=0(root) context=u:r:su:s0`; leitura de bloco ok.

## 4. Limitações / próximos passos

- **Sem SD card** no JM21: o backup vai para o **host** via adb.
- A UI continua a do **recovery stock** (botões). Um menu próprio exigiria
  mexer no binário de recovery (fica para o TWRP).
- O `--all` inclui `userdata` (criptografado); o backup cru serve para
  rollback, não para leitura.
- **Etapa B (TWRP)**: device tree + `bootable/recovery` (touch: `goodix_gt9xx_ts`
  + `ts_core`; display: `msm_drm`), partições dinâmicas (`liblp`) e a incógnita
  da **decriptação FBE** (keymaster).
