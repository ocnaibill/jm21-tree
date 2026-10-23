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

`[FW]` Build assinado com **`dev-keys`**; AVB lido com `avbtool 1.3.0`
(detalhes em `02-firmware-e-particionamento.md` §5).

| Item | `vbmeta` | `vbmeta_system` |
|------|----------|-----------------|
| Algoritmo | SHA256_RSA4096 | SHA256_RSA2048 |
| Chave (sha1) | `2597c218…011` | `cdbb7717…17d` |
| Rollback Index | **0** | **1 675 555 200** (2023-02-05) |
| Flags | **0** → verity + verificação **ligadas** | 0 |
| dm-verity | em `odm`, `system_dlkm`, `vendor`, `vendor_dlkm` | em `system`, `system_ext`, `product` |

Consequências:

1. **Verificação ligada.** Com o bootloader travado, qualquer imagem fora do
   `vbmeta` não boota. Com o bootloader destravado, o Android normalmente entra
   em modo "laranja" (verificação desativada no estado unlocked).
2. **Chaves de desenvolvimento.** Não há chave de release no caminho: é o
   cenário mais favorável para ROM customizada **se** o unlock for possível.
3. **`vbmeta` do topo com rollback 0** dá folga contra anti-rollback no nível
   AVB. Mas o anti-rollback do bootloader (`xbl`) é outro mecanismo e continua
   `[?]`.
4. `[?]` Estado do bootloader (locked/unlocked) — só o aparelho responde.

As 5 imagens com hash descriptor (`boot`, `dtbo`, `init_boot`, `recovery`,
`vendor_boot`) já foram **verificadas contra o `vbmeta` e batem** — o dump é
fiel ao que o dispositivo valida.

## 3. Rollback / anti-rollback

`[FW]` O rollback index de `vbmeta_system` é a **data do patch em epoch**
(2023-02-05). Isso é o padrão Qualcomm e implica: firmware com patch mais antigo
tem índice menor.

`[?]` Falta saber se o XBL aplica anti-rollback e qual o valor gravado no
dispositivo. Sem isso, **não tentar downgrade**.

`[FW]` A FiiO não publica links de firmware antigo: o fórum oficial pede o **SN
do aparelho** por e-mail ao suporte. Qualquer downgrade planejado deve começar
por aí, não por um arquivo achado na internet.

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
   `[FW]` **Não há programmer no pacote OTA.** Os 89 arquivos em
   `/vendor/firmware` não incluem `prog_firehose*` nem `rawprogram*.xml` — isso
   vem no pacote de serviço/QFIL da FiiO. **Este é o maior risco do projeto.**

   Pesquisa feita (2026-10-23), resultado honesto:

   - Não existe pacote QFIL/serviço público do JM21 que eu tenha localizado.
   - Loaders de firehose são **amarrados ao hash do dispositivo quando o Secure
     Boot está ligado**; existem loaders públicos de SM6225 (ex.: variante
     `001b80e1` no repositório `bkerler/Loaders`), mas são *patched* e "só
     funcionam em dispositivos sem Secure Boot".
   - Ferramenta de software madura para EDL: [`bkerler/edl`](https://github.com/bkerler/edl)
     (Sahara/Firehose), que ainda depende de um programmer compatível.
   - Loaders públicos de SM6225 catalogados em
     [`bkerler/Loaders`](https://github.com/bkerler/Loaders/issues/97); a
     restrição de Secure Boot está descrita no próprio issue.
   - Referência de procedimento QFIL/EDL:
     [flashguidehub.com/qfil-qualcomm](https://flashguidehub.com/qfil-qualcomm/).
   - `[?]` Se o XBL do JM21 exige programmer assinado só se descobre tentando —
     e tentar às cegas com loader errado pode piorar (estado de Sahara travado).

   **Conclusão operacional:** considerar EDL **indisponível** até que a FiiO
   forneça o pacote de serviço. Planejar a recuperação como se só existissem
   (1) OTA via recovery/sideload e (2) `fastboot` com bootloader destravado.

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
