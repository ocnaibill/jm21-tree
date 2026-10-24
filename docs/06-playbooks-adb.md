# 06 — Playbooks (offline e on-device)

> Ordem de execução: **somente leitura primeiro**. Nada de flash, nada de
> `remount`, nada de `dd` para fora antes de ter backup.

## 0. Drivers: o que é preciso (Linux × Windows)

**Linux (caso deste laboratório): nenhum driver proprietário da Qualcomm.**

| Recurso | O que o kernel usa | Precisa instalar? |
|---------|--------------------|-------------------|
| `adb` | libusb (userspace) + regra udev | regra udev, não driver |
| `fastboot` | libusb + regra udev | idem |
| EDL 9008 | módulos `qcserial`/`option` → `/dev/ttyUSB*` | já presentes no host |
| DAC USB / MTP | `snd-usb-audio`, `usb-storage` | já presentes |
| Diag/QXDM | `qcserial` (`05c6:900e`) | idem |

Estado do host em 2026-10-23:

- `modinfo qcserial` e `modinfo option` → **presentes** (kernel 7.2.11-cachyos).
- Regras udev Android → **ausentes** (`/etc/udev/rules.d` sem `51-android*`; não
  há referência a `18d1` em `/usr/lib/udev/rules.d`).
- Usuário **não** está em `plugdev` (grupos atuais: `sys network docker
  nopasswdlogin rfkill users video storage lp audio wheel`).

Ação preparada (não aplicada — requer `sudo`):

```bash
sudo install -m 0644 tools/udev/51-android-jm21.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules && sudo udevadm trigger
sudo usermod -aG plugdev "$USER"     # relogar
```

O arquivo `tools/udev/51-android-jm21.rules` cobre `18d1` (Android), `05c6`
(Qualcomm/EDL) e `2972` (FiiO). Alternativa empacotada: `android-udev`
(AUR/extra), que já traz os IDs comuns.

**Windows** — aí sim existem drivers:

- ADB/fastboot: driver "Android ADB Interface" (Google/OEM).
- EDL: **QDLoader HS-USB 9008** (Qualcomm), que vem com o QFIL/QPST.
- Sem esse driver, o aparelho em EDL aparece como "Unknown device" no
  Gerenciador de Dispositivos.

Ou seja: a pergunta dos drivers só pesa se o caminho for Windows. No Linux, o
que falta é **regra udev**, e o bloqueio real continua sendo o
`prog_firehose` (`07-riscos-e-recuperacao.md` §4.3).

## 0.1 Preparação do aparelho (quando conectar)

1. Ativar **Opções do desenvolvedor** → **Depuração USB**.
2. Autorizar a chave do host (`adb devices` deve mostrar `device`, não
   `unauthorized`).
3. Verificar se há root (`adb shell id`). Sem root, vários comandos ficam
   limitados — mas a maior parte do diagnóstico funciona.
4. **Não** desbloquear o bootloader nem dar `flash` nesta etapa.

Definir um prefixo para não esquecer:

```bash
export JM=~/repos/jm21-tree
mkdir -p "$JM/device-baseline"
```

---

## 1. Offline (já executado, reproduzível)

```bash
# listar partições do payload
./tools/bin/payload-dumper-go -l fw/JM21-update-1.1.1/payload.bin

# extrair todas
./tools/bin/payload-dumper-go -o dumps/fw-1.1.1 -c 8 fw/JM21-update-1.1.1/payload.bin

# ler arquivo de dentro de uma imagem
debugfs -R "dump /etc/audio/audio_policy_configuration.xml /tmp/policy.xml" \
  dumps/fw-1.1.1/vendor.img

# listar diretório dentro de imagem
debugfs -R "ls -l /lib64/hw" dumps/fw-1.1.1/vendor.img

# device tree
./tools/dt_dump.py dumps/fw-1.1.1/dtbo.img --list
./tools/dt_dump.py dumps/fw-1.1.1/dtbo.img --dump 40 > analysis/fw-1.1.1/dtbo-jm21-full.dts
./tools/dt_dump.py dumps/fw-1.1.1/dtbo.img --grep "cs43198|fpga|anolog"

# DTB base (5 variantes) a partir do vendor_boot — ver docs/04 §2
```

---

## 2. Baseline do dispositivo (primeiro contato, tudo leitura)

```bash
cd "$JM/device-baseline"

adb shell getprop > props.txt
adb shell dumpsys > dumpsys-full.txt
adb shell dumpsys audio > dumpsys-audio.txt
adb shell dumpsys media.audio_flinger > audio_flinger.txt
adb shell dumpsys media.audio_policy > audio_policy.txt
adb shell dumpsys media.audio_flinger --link > audio_flinger-link.txt 2>/dev/null
adb shell dumpsys package > packages.txt
adb shell pm list packages -s > packages-system.txt
adb shell pm list packages -3 > packages-thirdparty.txt

adb shell cat /proc/version > proc-version.txt
adb shell uname -a > uname.txt
adb shell cat /proc/cmdline > cmdline.txt
adb shell cat /proc/asound/cards > asound-cards.txt
adb shell cat /proc/asound/devices > asound-devices.txt
adb shell cat /proc/asound/pcm > asound-pcm.txt
adb shell cat /proc/interrupts > interrupts.txt
adb shell cat /proc/devices > devices.txt
adb shell ls -l /dev > dev-ls.txt
adb shell ls -l /sys/class > sys-class.txt
adb shell ls /sys/class/sound > sys-sound.txt

adb shell dmesg > dmesg.txt 2>/dev/null || echo "dmesg restrito"
adb shell logcat -d > logcat.txt
```

Verificações de coerência com o dossiê:

```bash
# confirma SoC/board aplicado
adb shell cat /proc/device-tree/model
adb shell cat /proc/device-tree/compatible

# confirma barramento I2C dos CS43198 (resolve a divergência @32/0x33)
adb shell ls /proc/device-tree/soc@0 | grep i2c
adb shell find /proc/device-tree -name "cs43198*" 2>/dev/null
adb shell find /proc/device-tree -name "*fpga*" 2>/dev/null

# confirma kernel/versão
adb shell cat /proc/version
```

---

## 3. Estado de áudio

```bash
# cartões e PCMs
adb shell cat /proc/asound/cards
adb shell cat /proc/asound/pcm
adb shell ls -l /proc/asound/

# mixers (se houver tinymix/tinypcminfo no aparelho)
adb shell which tinymix tinypcminfo tinyplay tinypcap
adb shell tinymix -D 0 > tinymix-d0.txt 2>/dev/null
adb shell tinymix -D 1 > tinymix-d1.txt 2>/dev/null

# controles por sysfs (fallback sem tinymix)
adb shell find /sys/class/sound -maxdepth 3 -name "*DAC*" 2>/dev/null
adb shell find /sys -name "*cs43198*" 2>/dev/null
adb shell find /sys -name "*fiio*" 2>/dev/null

# propriedades FiiO
adb shell getprop | grep -i fiio > props-fiio.txt
adb shell getprop | grep -i -E "audio|dsd|dac|mqa|uac|fpga" > props-audio.txt
```

O que procurar nos resultados:

| Alvo | Confirmar |
|------|-----------|
| `/proc/asound/cards` | nome do cartão (FiiO/CS43198/dummy) |
| `tinymix` | existência dos controles `DAC Playback Volume`, `DAC PO Gain`, `DAC Digital Filter Mode`, `DAC LR Balance` |
| `/proc/device-tree` | bus I2C, GPIOs, `gw-fpga` |
| `dmesg` | logs `[CS43198]`, `[dac_core]`, `[anolog_board]`, `[fiio_headset]` |

---

## 4. Barramento I2C (root)

```bash
adb shell ls /dev/i2c-*
# detectar os DACs e o FPGA nas 3 faixas prováveis
for b in 0 1 2 3 4 5 6 7; do
  adb shell "i2cdetect -y -r $b" > i2cdetect-$b.txt 2>/dev/null
done
grep -l -E "\b30\b|\b33\b|\b36\b" i2cdetect-*.txt
```

`i2cdetect` pode não existir. Alternativas:

- `adb shell ls -l /sys/bus/i2c/devices/` (mostra os clientes já instanciados).
- `/sys/bus/i2c/devices/<n>-0030/name` e `...-0033/name`.
- `dmesg | grep cs43198`.

---

## 5. Ver o que o player faz em tempo real

```bash
adb shell logcat -c
# tocar um arquivo e capturar
adb shell logcat -v threadtime | grep -i -E \
  "fiio|cs43198|dac_core|anolog_board|audio_hw|AudioFlinger|pal" > play.log

# em paralelo
adb shell "while true; do cat /proc/asound/card*/pcm*p/sub0/hw_params 2>/dev/null; sleep 1; done" \
  > hw_params.log
```

Objetivo: ver **taxa real**, formato e se o caminho é `hifi_playback`,
`direct_pcm` ou `deep_buffer` (via `dumpsys media.audio_flinger`).

Teste de bit-perfect (quando chegar a hora):

1. Gerar arquivos de teste (44,1/48/96/192/384/768 kHz; DSD64/128/256).
2. Tocar com volume fixo e sem EQ.
3. Conferir `hw_params` — se a taxa é a do arquivo, não há reamostragem até o
   kernel.
4. `[?]` Do kernel ao DAC ainda passa pelo FPGA: bit-perfect até o kernel não
   prova bit-perfect no DAC.

---

## 6. Dump coordenado (fase seguinte, só depois de tudo acima)

Pré-requisito: root **ou** recovery com `adb` + partições legíveis.

```bash
# lista de blocos por nome
adb shell ls -l /dev/block/by-name/ > by-name.txt

# partições pequenas e críticas primeiro
for p in fiioconfig boot_a boot_b init_boot_a dtbo_a vbmeta_a vbmeta_system_a; do
  adb shell "dd if=/dev/block/by-name/$p of=/sdcard/$p.img bs=4M" 2>/dev/null
  adb pull /sdcard/$p.img .
done

# depois as grandes (system/vendor/product/system_ext) — conferir espaço
adb shell df -h
```

Regra dura: **comparar tamanho e hash** do dump com o esperado antes de usar
qualquer coisa como base.

---

## 7. Checklist de segurança antes de qualquer escrita

- [ ] Dump completo de `fiioconfig`, `persist`, `modemst1/2`, `devinfo` (se
      acessíveis)
- [ ] `boot`, `vbmeta`, `vbmeta_system`, `dtbo` dos dois slots
- [ ] Imagem de recovery funcional (a original do OTA basta)
- [ ] Confirmado o caminho de recuperação (ver `07-riscos-e-recuperacao.md`)
- [ ] Bateria > 50%
- [ ] Cabo USB de dados confiável


## Controle de reprodução sem o usuário (autonomia)

O FiiO Music ignora intents de conteúdo, mas responde ao **keyevent de mídia** com
a atividade principal em foco:

```bash
adb shell am start -n com.fiio.music/com.fiio.music.activity.SplashActivity
adb shell input keyevent 126   # MEDIA_PLAY  (127 = pause)
```

Depois do `126`, o `MediaPlayerService` abre a última faixa e a HAL sobe o
stream — verificável no `logcat -s fiioaudio` e no `dmesg` (`snd_dac_startup`).

`tinyplay` **não** serve: o front-end (`PCM_RT_PROXY-RX-1`) exige o grafo do DSP
que só a HAL monta — abre e escreve 0 bytes.
