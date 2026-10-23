# 07 — Riscos, integridade e recuperação

> Esta é a seção que evita brick. O JM21 ainda não está conectado justamente
> para que tudo isto esteja decidido antes do primeiro comando de escrita.

## 1. Matriz de risco

| Ação | Risco | Reversível? | Pré-requisito |
|------|-------|-------------|---------------|
| `adb shell` leitura | nenhum | — | depuração USB |
| `adb pull` | nenhum | — | — |
| `dumpsys`/`logcat` | nenhum | — | — |
| `i2cdetect` (leitura) | baixo | — | root |
| `tinymix` escrita de controle | baixo | sim (valor antigo) | root, saber o valor |
| `fastboot flashing unlock` | **alto** (apaga `userdata`) | não | decisão consciente |
| `fastboot flash boot` | **alto** | sim, com imagem correta | bootloader desbloqueado |
| `fastboot flash vbmeta` com flags | **muito alto** | depende | backup + entendimento de AVB |
| `fastboot flash dtbo` errado | **muito alto** (não boota) | recovery/EDL | DTBO correto |
| gravar `fiioconfig` | **crítico** | só com backup | backup validado |
| `dd` em partição de bootloader (`xbl`, `abl`) | **crítico/brick** | só EDL | não fazer |

## 2. AVB, assinatura e `dev-keys`

`[FW]` O build é assinado com **`dev-keys`**, não `release-keys`. Implicações:

1. Não existe "chave de fábrica secreta" a preservar — se o bootloader for
   desbloqueável, qualquer imagem assinada com a nossa chave pode ser aceita
   após `--disable-verification` no `vbmeta`.
2. `[?]` O estado do bootloader (locked/unlocked) é desconhecido. Não há como
   saber pelo firmware.
3. `[?]` O conteúdo dos descritores AVB (`rollback_index`, `flags`,
   `dm-verity`) não foi lido — falta `avbtool`.

Próximos passos offline (seguros, sem aparelho):

```bash
pipx install avbtool   # ou clonar AOSP external/avb
avbtool info_image --image dumps/fw-1.1.1/vbmeta.img
avbtool info_image --image dumps/fw-1.1.1/vbmeta_system.img
```

## 3. Rollback / anti-rollback

`[?]` Desconhecido. Sem ler `vbmeta` não se sabe o `rollback_index` nem se há
anti-rollback de bootloader (`xbl` costura isso). **Consequência prática:** não
tentar downgrade antes de resolver esta questão.

O canal de OTA (`jm21pack.fiio.net`) pode indicar versões disponíveis. Sondar
apenas metadados, nunca instalar às cegas.

## 4. Caminhos de recuperação

Ordem de preferência:

1. **Recovery + sideload do OTA original**
   `payload.bin` + `update_engine` (A/B). O pacote é auto-suficiente e assinado
   com as chaves do build.
   ```bash
   adb reboot sideload
   adb sideload fw/JM21-update-1.1.1.zip
   ```
   `[?]` Se o recovery aceita sideload de zip OTA completo neste modelo —
   confirmar antes de precisar.

2. **`fastboot` com imagens do payload** (bootloader desbloqueado)
   ```bash
   fastboot flash boot       dumps/fw-1.1.1/boot.img
   fastboot flash init_boot  dumps/fw-1.1.1/init_boot.img
   fastboot flash vendor_boot dumps/fw-1.1.1/vendor_boot.img
   fastboot flash dtbo       dumps/fw-1.1.1/dtbo.img
   ```
   Slot ativo: `fastboot getvar current-slot`.

3. **EDL (9008) com `prog_firehose_ddr.elf`**
   `[?]` **Não há programmer no pacote OTA.** Os 89 arquivos em
   `/vendor/firmware` do OTA não incluem `prog_firehose*` nem `rawprogram*.xml`
   — isso vem no pacote de serviço/QFIL da FiiO. **Este é o maior risco do
   projeto**: sem programmer, um brick de bootloader só se resolve com
   assistência técnica.
   Ação recomendada: obter o pacote de firmware completo (QFIL) do JM21 antes de
   qualquer flash.

4. **`update_engine` via `adb shell` (root)** — aplicar payload local:
   ```bash
   adb push payload.bin /data/local/tmp/
   adb shell update_engine_client --payload=/data/local/tmp/payload.bin \
     --headers="FILE_HASH=... FILE_SIZE=... METADATA_HASH=... METADATA_SIZE=..."
   ```
   `[?]` Requer que `update_engine_client` exista e que a verificação de
   assinatura aceite o pacote (é o mesmo build, então deve aceitar).

## 5. Partições sem backup no OTA

Não vêm no `payload.bin` e são insubstituíveis:

| Partição | O que guarda | Consequência de perder |
|----------|--------------|------------------------|
| `persist` | calibração de RF/sensores | perda de modem/Wi-Fi |
| `fiioconfig` | configuração FiiO (`fiio_config.ko`) | `[?]` possível perda de parâmetros de áudio/ganho |
| `modemst1`/`modemst2` | estado de modem (IMEI/qcn) | **perda de IMEI** |
| `devinfo` | estado do bootloader/lock | pode travar unlock |
| `misc` | comandos de boot/recovery | boot loop |
| `frp` | proteção de fábrica | — |

**Regra:** o primeiro dump do aparelho é dessas partições — não das grandes.

## 6. Riscos elétricos / operacionais

- Consumption alto com amp em `GAIN_SUPER_OVER_EAR`: não testar carga máxima com
  bateria baixa.
- `[DRV]` O driver tem proteções de **temperatura**, **overload** e **DC** —
  elas desligam a saída. Se a saída "morrer" durante um teste, isso pode ser
  proteção, não falha.
- Não abrir o aparelho nesta fase. Abrir invalida garantia e não é necessário
  para nada do que está planejado.
- Manter o firmware original arquivado fora do repo (o `fw/` é o cofre).

## 7. Ética e escopo

- O trabalho é sobre **equipamento próprio**, para interoperabilidade e
  preservação.
- Não redistribuir blobs proprietários (HAL, `.ko` FiiO, APKs) em repositório
  público. O repo versiona apenas ferramentas e documentação.
- Nada de contornar DRM (MQA/metadados) — o interesse é no caminho de áudio.

## 8. Definir antes do primeiro flash

- [ ] `avbtool info_image` nos dois `vbmeta`
- [ ] Pacote QFIL/EDL do JM21 obtido (ou decisão consciente de assumir o risco)
- [ ] Estado do bootloader documentado (`fastboot getvar all`)
- [ ] Recovery testado (entrar sem alterar nada)
- [ ] Dump validado de `persist`, `fiioconfig`, `modemst*`, `devinfo`, `misc`
- [ ] Hash dos dumps comparado com o esperado
