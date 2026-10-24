# 35 — ISO do driver MTP (issue #6) e pacote QFIL/EDL (issue #5)

## 1. `fiio_mtp_driver.iso` (issue #6)

`/system/etc/fiio_mtp_driver.iso` — 34 406 400 bytes, FAT16 (volume declarado de
40 MB), SHA-256 `8ddc57cf…`.

Conteúdo:

| Caminho | Bytes | O que é |
|---------|-------|---------|
| `autorun.inf` | 43 | autostart do CD no Windows |
| `fiio.ico` | 67 646 | ícone |
| `Windows/USB DAC driver/FiiO_v4.47.0_2018-08-03_setup.exe` | 2 327 920 | **driver USB DAC** (v4.47.0, 2018-08-03), SHA-256 `c8e30eb4…` |
| `Windows/…教程.pdf` | 828 957 | tutorial em chinês |
| `Mac/…MTP…pdf` (2 arquivos) | ~317 KB | instruções de MTP no Mac |
| `Mac/MAC OS MTP Client/Android File Transfer.dmg` | 3 708 690 | cliente MTP do Google |

**Como é (ou não é) exposto:** o `init.fiio.usb.rc` referencia o ISO nos modos
`mtp_msc` e `mtp_adb_msc` (`mass_storage.0/lun.0/file` + `cdrom 0`), mas
**todas essas linhas estão comentadas** neste firmware. Ou seja: o aparelho
**não** monta o CD virtual de drivers — o ISO é só um resíduo de build. O driver
Windows serve para o modo USB DAC no PC.

## 2. Pacote QFIL/EDL (issue #5)

O que foi procurado e **não** existe no material disponível:

| Item | Onde se procurou | Resultado |
|------|------------------|-----------|
| `prog_firehose_ddr.elf` | `payload.bin`, todas as partições extraídas | ausente |
| `rawprogram*.xml` / `patch*.xml` | OTA e dumps | ausente |
| Pacote QFIL do JM21 | OTA 1.1.1 | ausente |

`[FATO]` O OTA é A/B puro (`payload.bin` + `payload_properties.txt`), sem
programador de EDL.

O que **existe**:

- `xbl.img` contém o protocolo **Sahara** (`Sahara: Hello pkt sent`,
  `Sahara: Hello Response Received`, `sbl1_sahara.c`) — o suporte a
  EDL/Firehose está no bootloader, como em qualquer SM6225.
- O bootloader está **desbloqueado** (`flash.locked=0`, `verifiedbootstate=orange`),
  então o caminho de recuperação normal é **fastboot** (boot/recovery/partições),
  não EDL.

`[HYP]` Para ter QFIL seria preciso o pacote de serviço da FiiO (mesmo canal do
pedido de GPL) ou um firehose genérico de SM6225 — este último é **risco real de
brick** e não deve ser tentado sem o pacote correto. `fastboot` cobre os casos
de recuperação que nos interessam.

**Conclusão da issue #5:** não há pacote EDL público no firmware; o caminho
seguro de recuperação é o fastboot (bootloader desbloqueado). Se precisarmos de
EDL, é pedido à FiiO junto com o GPL.
