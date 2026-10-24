# 44 — Atualização pós-root (issue #17)

> Estado medido: slot ativo **`_a`**, **Virtual A/B** (`ro.virtual_ab.enabled=true`),
> bootloader destravado (`orange`, `flash.locked=0`), **Magisk 30.7**.
> Sem firmware novo: **1.1.1 é a versão mais recente** (manifesto
> `beta/patchCN.txt`).

## 1. Como o aparelho atualiza

O app `com.android.fiioupdate` usa a API padrão do Android:

```java
UpdateEngine.applyPayload(url, offset, size, props);
```

`props` são os campos de `payload_properties.txt`:

```
FILE_HASH=kzkSRbXKAhGWdGQVgGpiVMrtYE41mb4/MEouJZfYPXE=
FILE_SIZE=1642838532
METADATA_HASH=zF/jTxnVkCr1xHXRa4ciZ28XY10raju9jJmhlMQJXz4=
METADATA_SIZE=130679
MODEL_NAME=FiiO JM21
```

`[FATO]` O `FILE_HASH` do nosso `payload.bin` **confere**
(`sha256 → base64` = `kzkSRbXK…`), então o pacote local é válido.

O progresso no JM21 é exibido em **duas metades** (50 % + 50 %) — tratamento
específico de `isJM21 && SDK==33` no updater (`docs/32` §8).

## 2. Procedimento

### Antes
1. **Backup** (`docs/42`) — em especial `init_boot_a` (patched) e as imagens do
   OTA.
2. Anotar o slot ativo: `getprop ro.boot.slot_suffix` (hoje `_a`).
3. Baixar o OTA novo pelo manifesto:
   `http://jm21pack.fiio.net/beta/patchCN.txt` → `PatchUrl`.
4. Verificar o pacote:
   ```bash
   openssl dgst -sha256 -binary JM21-update-X.zip | base64 -w0   # comparar
   ```

### Aplicar
**Opção A (recomendada):** o próprio updater da FiiO (Ajustes → Suporte técnico
→ Atualização → Online). Ele faz `applyPayload` e cuida do slot inativo.

**Opção B (manual):** com o `payload.bin` e o `payload_properties.txt` no
aparelho:
```bash
adb push payload.bin payload_properties.txt /data/local/tmp/
adb shell su -c "update_engine_client --update \
  --payload=/data/local/tmp/payload.bin --offset=0 --size=1642838532 \
  --headers=\"FILE_HASH=...,FILE_SIZE=...,METADATA_HASH=...,METADATA_SIZE=...\" \
  --follow"
adb reboot
```

### Depois do reboot (root perdido)
Com **Virtual A/B**, o `init_boot` do slot novo vem **stock** — o root some.
Para re-rootar:

1. Extrair o `init_boot.img` do payload novo
   (`payload-dumper-go -p init_boot payload.bin`).
2. Patchar com Magisk (app → "Instalar" → "Patch a file", ou `magiskboot` no
   host).
3. `fastboot flash init_boot_<slot_novo> init_boot_patched.img`.
4. Verificar: `getprop ro.boot.slot_suffix`, `su -c magisk -v`, e comparar o
   hash do `init_boot` com o patched.

`[HIP]` A opção "instalar no slot inativo" do Magisk pode não funcionar no
Virtual A/B (o slot inativo é um snapshot); o caminho confiável é **re-rootar
depois** do reboot.

### Rollback
- O slot anterior continua existindo (Virtual A/B), mas o rollback de OTA é
  controlado pelo *rollback index* do AVB.
- **Nunca** usar as imagens do slot B do backup — são de um build anterior
  (`docs/42` §2).
- Fallback seguro: `fastboot flash` das imagens **1.1.1 do OTA** (boot,
  init_boot, dtbo, vendor_boot, vbmeta, vbmeta_system) + restaurar `persist` e
  `fiioconfig` do backup.

## 3. Verificação por hash

- `avbtool verify_image --image vbmeta.img` nos `vbmeta` (o OTA já bate 5/5).
- Comparar o prefixo das partições com as imagens do OTA (como em `docs/42`):
  o slot ativo deve ser byte-idêntico, exceto `init_boot` (Magisk).

## 4. Pendência

- **Teste ao vivo** de um ciclo completo (atualizar → reboot → re-root) só é
  possível quando a FiiO publicar uma versão nova. Até lá, o procedimento está
  documentado e o pacote, verificado por hash.
