# 51 — Build do TWRP para o JM21 (etapa B) — estado

## O que já está pronto

- **Fonte**: `platform_manifest_twrp_aosp` branch `twrp-12.1` sincronizada em
  `~/twrp` (~33 GB, 249 projetos — o mínimo do TWRP, sem o grupo `pdk`).
- **Device tree**: `device-tree/fiio/jm21/` (neste repo) — copiar para
  `~/twrp/device/fiio/jm21/`.
  - `BoardConfig.mk` (kernel prebuilt, partições, A/B, super, flags TWRP),
    `twrp_jm21.mk`, `AndroidProducts.mk`, `twrp.fstab`.
  - `recovery/root/init.recovery.qcom.rc`: `enforce 0` no early-init + insmod
    da cadeia do touch (`qcom_ipc_logging` → `i2c-msm-geni` →
    `fiio_primary_modules` → `ts_core` → `goodix_gt9xx_ts`).
  - `prebuilt/Image` (kernel do boot.img) e `prebuilt/dtb` (do vendor_boot) —
    não versionados; ver `README` do device tree.
- **Lição que vale**: a imagem de recovery tem de ser **kernel-less** (o ABL
  quebra o boot normal com kernel) → repack pós-build com
  `mkbootimg --ramdisk ... --header_version 4`.

## Onde o build parou (e por quê)

`mka recoveryimage` ainda falha no **parse do soong**: o manifest mínimo do
TWRP **não sincroniza o grupo `pdk`** (junit, kotlin, auto, error_prone,
droiddoc, robolectric…), mas vários projetos **sincronizados** referenciam
esses módulos (testes/apps/docs). O que já foi feito:

1. **Stubs** em `device/fiio/jm21/Android.bp` para os módulos referenciados
   (vts_proto_fuzzer_default, junit, kotlin-stdlib, guava, tradefed…).
2. **Desabilitados** (`.bp.disabled`) projetos não usados no recovery:
   `external/grpc-grpc-java/**`, `packages/providers/MediaProvider/errorprone`,
   `test/vts/testcases/**`, `development/scripts`, `prebuilts/.../robolectric`,
   `tools/platform-compat/**`, testes do `frameworks/base` (powermodel, StagedInstall),
   `external/icu/tools/srcgen/currysrc`, etc.
3. `build/soong/bloaty/Android.bp`: removido **só** o `bloaty_merger_test`
   (mantido o `soong-bloaty`).
4. **Restaurados** os que o loop de limpeza desabilitou por engano e eram
   necessários (`hardware/libhardware/Android.bp`, `external/rust/crates/either`).

**Bloqueio atual**: ainda restam referências a módulos de teste/ferramenta
ausentes (ex.: `EddParser.py`/`hostConfig.py` no `frameworks/av/.../tools`,
`libserde_json` no teste do `either`). A limpeza é **mecânica** (desabilitar os
`.bp` de teste), mas longa.

## Próximos passos

1. Terminar a limpeza (desabilitar os `.bp` de teste restantes) até o parse
   passar; alternativas mais limpas: sincronizar o grupo `pdk`
   (`repo init -g pdk`) ou usar `remove-minimal.xml`.
2. `mka recoveryimage -j8` (build longo; ~1–2 h).
3. **Repack kernel-less** do `recovery.img` gerado e flash em `recovery_a`.
4. Testar: boot, **touch** (goodix), partições (`super`/`liblp`), adb/sideload.
5. **FBE/decriptação**: não prometer (keymaster do vendor; incógnita).

## Atualização 2026-10-25 (2ª parte) — o TWRP do Hovatek e o estado do build

### Descoberta: já existe um TWRP funcional para o JM21
`soumarcelino/twrp-device-fiio-jm21` — TWRP **3.7.1_12 (Team Hovatek)**.
- A imagem é **kernel-less** (confirma nosso achado); a original tem 100 MiB
  (maior que a partição de 96 MiB) → **reempacotamos kernel-less** (24 MB) e
  gravamos em **A e B** (salvaguarda).
- Funciona: touch (`goodix-ts`/event3), shell **root**, 250 módulos carregados
  (o init completo faz o `mount_all` + os módulos do `vendor_dlkm` — os insmods
  manuais que eu tinha posto **não são necessários**).
- **Não decifra o `/data`** (`Failed to mount '/data' (Invalid argument)` — a
  metadata encryption/FBE). Backup só cru (o nosso `recovery-tool.sh`/o "image
  backup" do TWRP).
- Config extraída: `recovery.fstab` = o **stock**; `twrp.flags` com as lógicas
  (`logical;slotselect;backup=1;flashimg=1`), `/data`, `/metadata`, `/boot`,
  `/misc`.

### Nosso build (estado)
- Device tree atualizado com os fatos deles; `prebuilt/` + os módulos do touch
  no lugar; `local_manifests/pdk-tools.xml` com os projetos podados que o parse
  precisa (`junit`, `kotlinc`, `auto`, `error_prone`, `guava`, `mockito`,
  `testng`, `hamcrest`, `doclava`, `jsilver`, `javaparser`, `javapoet`, `ply`,
  `python/{parse_type,pyfakefs}`, `rust/serde_json`, `prebuilts/tools`,
  `test/vts-testcase/fuzz`, `cts`).
- **Stubs documentados** em `device/fiio/jm21/Android.bp` (14 até agora) para as
  lacunas dos **forks** do upstream (ex.: `hardware/interfaces` do LineageOS
  19.1 sem `neuralnetworks_utils_defaults`; tradefed/compatibility do
  `test/vts`/`cts`).
- **Bloqueio atual**: o `test/vts` do AOSP 12.1 referencia prebuilts Python/Java
  que o `remove-minimal.xml` do TWRP podou — cauda longa. Caminho escolhido:
  **remover os projetos de teste não usados** (`<remove-project>` no local
  manifest: `test/vts`, `cts` que adicionamos) + **stubs** só para os módulos
  referenciados por projetos **necessários** (o `frameworks/base`).

## Onde a cauda realmente está (raiz do problema)

O manifest **mínimo** do TWRP (`twrp-12.1`) remove 828 projetos
(`remove-minimal.xml`) e troca alguns pelos forks do LineageOS/TeamWin — mas os
projetos **mantidos** do AOSP 12.1 referenciam módulos que ficaram de fora em
**testes, docs e ferramentas** (`test/vts`, `cts`, `dalvik/dx` docs,
`frameworks/av` audio-policy tools, crates Rust de teste, etc.). Cada correção
(stub ou projeto re-sincronizado) revela mais 1–2. Isso é **inconsistência do
tree mínimo do TWRP nesta tag**, não do nosso device tree.

### Números desta sessão
- Projetos re-sincronizados via `local_manifests/pdk-tools.xml`: ~25
  (junit/kotlinc/auto/error_prone/guava/mockito/testng/hamcrest/doclava/
  jsilver/javaparser/javapoet/ply/python/serde/itoa/ryu/serde_derive/
  antlr/tagsoup/escapevelocity/prebuilts/tools/jsr305/javassist/
  modules-utils…).
- Stubs **documentados** (`device/fiio/jm21/Android.bp`): 20 (só para o parse;
  nada deles vai para a imagem).

### Duas rotas para terminar o nosso build
1. **Continuar a cauda** (stubs/projetos até o parse fechar). Mecânico, mas não
   se sabe quantos faltam (a cada rodada aparecem 1–3).
2. **Árvore AOSP 12.1 completa** + o fork do `bootable/recovery` do TWRP +
   nosso device tree. É o que os builds "de verdade" fazem: o AOSP completo é
   **consistente** por construção (nada de referência a módulo podado). Custa
   ~150–200 GB e horas de sync, mas elimina a cauda de uma vez. O disco tem
   440 GB livres.

---

# 16. Build própria do TWRP: sobe (e por que antes não subia)

## 16.1 Causa raiz do "compila, flasha e trava na logo"

O kernel estava **saudável**; o que morria era o linker do `/system/bin/recovery`:

```
CANNOT LINK EXECUTABLE "/system/bin/recovery":
  library "libresetprop.so" not found: needed by main executable
```

Cadeia: `TW_OVERRIDE_SYSTEM_PROPS` (no BoardConfig) → `Android.mk` liga
`TW_INCLUDE_LIBRESETPROP` → o binário `recovery` passa a ter `DT_NEEDED
libresetprop.so` → mas a lib só era instalada em `system/lib64`, nunca no
ramdisk. O `init` iniciava o serviço, o linker abortava, `init` reiniciava:
crash-loop invisível (a logo ficava na tela porque o fb nunca era inicializado).

Correção (`external/magisk-prebuilt/resetprop/Android.bp`):

```
cc_library {
    name: "libresetprop",
    recovery: true,          # <-- faz instalar em recovery/root/system/lib64
    recovery_available: true,
```

Método de diagnóstico que achou isso: com a imagem no aparelho, `adb` **sobe
mesmo com o TWRP travado** (`adb devices` mostra estado `recovery`); então
`adb shell /system/bin/recovery` imprime o erro do linker direto.

## 16.2 Outras três diferenças que impediam o uso

| Sintoma | Causa | Correção |
|---|---|---|
| tela preta com backlight | `TW_MAX_BRIGHTNESS := 2047` / `TW_DEFAULT_BRIGHTNESS := 1024`, mas o painel aceita 0–255 (`/sys/class/backlight/panel0-backlight/max_brightness`) → escrita rejeitada, fica em 0 | `255` / `128` |
| fundo vermelho, azul estourado | `TARGET_RECOVERY_PIXEL_FORMAT := "ABGR_8888"` → `DRM_FORMAT_RGBA8888`. O build do Hovatek usa `DRM_FORMAT_XBGR8888` | `"RGBX_8888"` |
| o TWRP ignora todo o fstab | O parser do `Process_Fstab_Line` trata linha começando com `/` como formato **TWRP** (`mountpoint fstype device`); o nosso fstab estava em formato **AOSP** (`device mountpoint fstype`) | usar nome de partição na 1ª coluna (ex.: `system /system ext4 ...`) ou caminho `/dev/block/...` |

## 16.3 Empacotamento da imagem (kernel-less)

O `build-recovery.sh` chamava o `mkbootimg` do **AOSP** (o `lunch` põe
`out/host/linux-x86/bin` no PATH), que injeta **4096 bytes de assinatura AVB
zerada**. A imagem do Hovatek tem `signature size: 0`. O script agora:

1. descompacta o ramdisk do `recovery.img` (que sai gzip);
2. recomprime em **LZ4 legacy** (`lz4 -l -12 --no-frame-crc`);
3. empacota com `/usr/bin/mkbootimg` (o do sistema).

Kernel sempre **ausente**: o ABL do JM21 usa o kernel do `boot_a`.

## 16.4 Estado atual

- `ro.twrp.version = 3.7.1_12-jm21-billzinho`, GUI sobe, cores certas,
  brilho correto, fstab lido sem erros, adb root em recovery.
- `TW_INCLUDE_CRYPTO` está **desligado**: com ele ligado o TWRP trava na
  inicialização esperando a HAL do keymaster (ver §17).

## 16.5 Pendências no build system (documentadas, não "burlando")

- `libminuitwrp` não entrava no ramdisk sozinha. `recovery: true` no
  `minuitwrp/Android.bp` **quebra** o `libguitwrp` (módulo estático usado nas
  duas variantes). Solução aplicada: incluí-la em
  `RECOVERY_LIBRARY_SOURCE_FILES` (`bootable/recovery/prebuilt/Android.mk`).
- `libresetprop`: `recovery: true` funciona (não tem consumidor de sistema).

---

# 17. `/data`: o que falta para decifrar (próxima sessão)

## 17.1 O travamento

Com crypto ligado, o log termina em:

```
Using additional fstab for decryption /etc/additional.fstab
```

e o processo `recovery` fica com **1 thread** em `futex_wait` — é o
`wait_for_keymaster` do `system/vold`, que bloqueia indefinidamente se a HAL
não registra.

## 17.2 O que o aparelho tem (lido do `dumps/fw-1.1.1/vendor.img`)

| HAL | Binário (`/vendor/bin/hw`) |
|---|---|
| KeyMint (AIDL, Android 13) | `android.hardware.security.keymint-service-qti` |
| Keymaster 4.0 (HIDL, compat) | `android.hardware.keymaster@4.0-service-qti` |
| Gatekeeper | `android.hardware.gatekeeper@1.0-service-qti` |
| TEE | `vendor.qti.hardware.qseecom@1.0-service` + `/vendor/bin/qseecomd` |

O TWRP 3.7.1 fala HIDL até keymaster 4.1 → alvo é o **4.0-qti**.

## 17.3 O que já foi feito (e por que ainda não basta)

- `qseecomd` e `android.hardware.keymaster@4.0-service-qti` extraídos para
  `recovery/root/system/bin/`.
- Fecho de dependências (só 7 libs de vendor + 2 do sistema) copiado para
  `recovery/root/system/lib64/`: `libqtikeymaster4`, `libkeymasterdeviceutils`,
  `libkeymasterutils`, `libQSEEComAPI`, `libdrmfs`, `libqcbor`, `libdiag`,
  `libdmabufheap`, `libion`.
- `init.recovery.qcom.rc` ganhou os serviços e `setprop keymaster_ver 4.0`.

Resultado: o **keymaster sobe** (`init.svc.keymaster-4-0-qti = running`), mas o
`qseecomd` **sai com status 255 em 10 ms** quando iniciado pelo `init` — embora
rode normalmente à mão. Sem qseecomd não há TEE, o HAL não registra e o TWRP
continua esperando.

## 17.4 Próximos passos sugeridos

1. Descobrir por que `qseecomd` falha sob o `init` (status 255 imediato):
   comparar ambiente/argv com a execução manual, ver `dmesg`/`logcat` do
   processo, testar sem `oneshot` e com `class core` + restart.
2. Verificar se falta `/firmware`/keybox (`/vendor/firmware`, `/vendor/keymaster`)
   ou o `vendor.qti.hardware.qseecom@1.0-service`.
3. Alternativa mais barata: montar `/vendor` **antes** de `Decrypt_Data()` e
   usar o caminho padrão do `device/qcom/twrp-common` (que espera
   `ro.crypto.state` + `sys.listeners.registered` — este último nunca é setado
   no nosso init).
