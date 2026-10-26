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

## 17.5 Avanço da sessão seguinte (o que já funciona)

Aplicadas e verificadas no aparelho:

1. **`/vendor` montado antes do decrypt** — `partitionmanager.cpp` (`Setup_Data_Partition`)
   agora monta `/vendor` antes de chamar `Decrypt_Data()`. Sem isso o
   `/vendor/firmware` (86 arquivos, `a610_zap.*` etc.) não existe e o TEE não carrega.
2. **SELinux permissivo** — o `init.recovery.qcom.rc` que realmente vai para o
   ramdisk NÃO tinha `write /sys/fs/selinux/enforce 0`. Sem isso o `qseecomd`
   saía com status 255 em 10 ms. Com o `enforce 0`: `init.svc.qseecomd = running`.
3. **Keymaster 4.0 QTI** — `init.svc.keymaster-4-0-qti = running` e o processo
   fica em `binder_wait_for_work` (registrado, ocioso), não mais em `nanosleep`.

## 17.6 O bloqueio atual (diagnóstico fechado)

O `recovery` continua parado em `futex_wait` logo depois de
`Using additional fstab for decryption`. O `dmesg` mostra a causa:

```
init: Control message: Could not find
      'aidl/android.system.keystore2.IKeystoreService/default' for ctl.interface_start
init: starting service 'keystore2'...
init: Service 'keystore2' (pid 573) received signal 11
```

O TWRP espera o **`keystore2`**, e o `keystore2` está em crash-loop
(SIGSEGV sob o init, SIGABRT quando rodado à mão; todas as libs estão
presentes, então é abort de runtime).

Ou seja: no Android 13 o `keystore2` fala **KeyMint (AIDL)** —
`android.hardware.security.keymint.IKeyMintDevice/default` — e não o
keymaster 4.x HIDL. O TWRP 3.7.1 monta o stack de keymaster HIDL, não de
KeyMint. Por isso o `keystore2` não sobe e o decrypt fica esperando para sempre.

### Caminhos possíveis para o `/data`
1. Portar o suporte a **KeyMint AIDL** para o `bootable/recovery` (o ramo
   TWRP 12.1 não tem; versões mais novas do TWRP têm).
2. Tentar o `keystore2` com o HAL `android.hardware.security.keymint-service-qti`
   do `/vendor` e ver se o abort some (falta saber por que ele aborta — não é
   linker).
3. Usar a rota antiga: `vold` do Android 12 (`TW_INCLUDE_FBE`) em vez do
   `MetadataCrypt` do 13.

### Estado entregue
- `recovery_a` com a build **funcional** (crypto desligado): GUI, cores,
  brilho, fstab e adb root ok. `/data` não monta (igual ao Hovatek).
- Todo o material de keymaster (binários + 9 libs + serviços + patch do
  vendor mount) está no device tree, pronto para retomar.

## 17.7 Segunda rodada: até onde a rota A chegou

Com `logd`/`logcat` ligados (`TWRP_INCLUDE_LOGCAT`, `TARGET_USES_LOGD`) deu para
ver a cadeia inteira. Ordem dos bloqueios encontrados e o que foi corrigido:

| # | Erro | Correção |
|---|---|---|
| 1 | `keystore2` SIGSEGV: `Unrecognized manifest.version 5.0 (libvintf@4.0)` | `system/libvintf/include/vintf/constants.h`: `kMetaVersion{5,0}` |
| 2 | `VINTF parse error: /odm/etc/vintf/manifest.xml: Too many symbolic links` | montar `/odm` antes do decrypt (no ramdisk `/odm/etc -> /vendor/odm/etc` e no vendor `/vendor/odm -> /odm`) |
| 3 | `keymint` não achava `android.hardware.security.keymint-V2-ndk.so` | libs NDK do Android 13 extraídas do `system.img` para o ramdisk |
| 4 | `libkm_compat.so` pedia `android.system.keystore2-V2-ndk.so` / `android.security.compat-ndk.so` | idem |
| 5 | `keymint-qti` SIGABRT sob o init como `user system` | rodar como `user root` |

Estado depois disso:
- `getDeviceHalManifest: Successfully processed VINTF information` ✔
- `/vendor` e `/odm` montados ✔
- `keymint-qti` roda e registra os 4 serviços (`IKeyMintDevice`,
  `ISecureClock`, `ISharedSecret`, `IRemotelyProvisionedComponent`) ✔
- `keystore2` sobe e lê o VINTF ✔

**Bloqueio final:** o `keystore2` (pid vivo, em `nanosleep`) fica em
`Waiting for service 'android.hardware.security.keymint.IKeyMintDevice/default'`
e o `servicemanager` responde
`Could not find 'aidl/android.system.keystore2.IKeystoreService/default' for
ctl.interface_start`. Ou seja: o `init` do 12.1 não faz a ponte de
lazy-AIDL-service que o Android 13 usa (o `keystore2.rc` também não declara
`interface aidl ...`).

### Conclusão honesta sobre A vs C

A rota A (graft do stack 13 no ramdisk 12.1) andou muito — VINTF, vendor, odm,
KeyMint — mas cada camada puxa a próxima, e a última é o próprio modelo de
serviços AIDL do `init`. **Não é mais um flag, é o `init`.**

Rota C (AOSP 13 + TWRP `android-13`) tem tudo isso pronto:
- branches existentes: `android-13`, `android-14`, `android-14.1`;
- o `bootable/recovery` do `android-13` já relinca `libkeymint*`,
  `keymint-V1-ndk`, `libkm_compat`, `libkeymint_support`;
- o `vold` do 13 (repo `android_system_vold`, branch `android-13`) tem
  `Keystore.cpp`/`Keystore.h` com suporte a KeyMint.
Custo: ~130 GB de sync (há 308 GB livres) + refazer o device tree.

Artefatos desta rodada: imagem experimental com crypto em
`/tmp/recovery-jm21-twrp-crypto-exp.img`; build funcional (crypto off) em
`/tmp/recovery-jm21-twrp-nocrypt-ok.img`.

---

# 18. Rota C — AOSP 13 + camada TWRP (estaca 0)

## 18.1 Por que 13 e o que o TWRP tem de fato

O aparelho é Android 13; o stack que falta:
- `keystore2` fala **KeyMint (AIDL)** e usa o modelo de **lazy AIDL service**
  do `init` (`ctl.interface_start`), que o `init` do 12.1 não tem;
- o `vold` do 13 (repo `android_system_vold`, branch `android-13`) tem
  `Keystore.cpp`/`Keystore.h` com KeyMint.

O que **não** existe: nenhum branch do TWRP está completo para 13 ou 14.
Matriz verificada com `git ls-remote`:

| repo | android-13 | android-14 |
|---|---|---|
| android_bootable_recovery | sim | sim |
| android_build | **sim** | não |
| android_build_soong | sim | sim |
| android_system_core | sim | sim |
| android_system_vold | sim | sim |
| android_vendor_twrp | sim | sim |
| android_external_icu / sqlite | sim | sim |
| android_packages_modules_adb | sim | não |
| android_device_qcom_twrp-common | **não** | sim |
| external_magisk-prebuilt | não | não (só 12.1/master) |
| android_external_libxml2 / system_libhidl / libhwbinder / update_engine / extras / external_zip | não | parcial |

Conclusão: **AOSP 13 completo** (`android-13.0.0_r84`) e sobrescrever só o que
tem branch 13. O resto fica AOSP (consistente por construção).

## 18.2 Árvore criada

`~/twrp13` — `repo init -u platform/manifest -b android-13.0.0_r84 --depth=1`
+ `.repo/local_manifests/twrp13.xml`:

- TeamWin **android-13**: bootable/recovery, build/make, build/soong,
  external/icu, external/sqlite, packages/modules/adb, system/core,
  system/vold, vendor/twrp
- TeamWin **android-14**: device/qcom/twrp-common (única versão existente)
- TeamWin **android-12.1**: external/magisk-prebuilt (única com libresetprop)
- LineageOS **lineage-20.0** (= Android 13): external/bash, external/libncurses,
  external/nano, prebuilts/tools-lineage, hardware/interfaces
- sem `external/zip` (não existe em 13/14; entra depois se o build pedir)

## 18.3 Artefatos preservados (fora do /tmp)

`~/jm21-artifacts/`:
- `twrp-jm21-build-own-funcional.img` — build nossa que sobe (crypto off),
  cores/brilho/fstab certos.
- `twrp-jm21-crypto-experimental.img` — a da rota A (trava no splash, mas com
  keymint + keystore2 subindo; útil para continuar o diagnóstico).

(`*.img` está no `.gitignore`, por isso ficam fora do repo.)

---

# 19. Rota C em andamento — AOSP 14 (`twrp-14`)

## 19.1 Base escolhida

O TWRP **nao tem** manifest para Android 13 (`twrp-11`, `twrp-12.1`,
`twrp-14`, `twrp-14.1`). O 13 foi abandonado e fomos para o manifest oficial
`minimal-manifest-twrp/platform_manifest_twrp_aosp`, branch **`twrp-14`**
(AOSP `android-14.0.0_r17` + forks TeamWin).

## 19.2 Problema estrutural do manifest

O manifest mistura forks de snapshots diferentes: `build/make` e
`android-14.1` (epoca QPR3) enquanto o resto do AOSP fica em `r17` (14 inicial).
Isso gera uma cascata de incompatibilidades. Resolvido fixando **todo o lado
AOSP em `r50`** (`.repo/local_manifests/` + `default revision` alterado em
`.repo/manifests/default.xml`).

Overrides criados em `~/twrp14/.repo/local_manifests/`:

| arquivo | funcao |
|---|---|
| `build-bazel.xml` | `build/bazel` em r50 (r17 nao tem `utils/schema_validation.scl`) |
| `build-release.xml` | adiciona `platform/build/release` (release configs) |
| `extra-projects.xml` | `toolchain/pgo-profiles` em r50 |
| `r50-fallbacks.xml` | 264 projetos sem tag r50 (crates de Rust etc.) -> branch `android14-release`, gerado por `converge-sync.py` |
| `soong-aosp.xml` | `build/soong` do AOSP r50 (o fork do TWRP nao combina com `build/blueprint` r50) |

`~/twrp14/converge-sync.py` roda o sync em laco, coleta os projetos que falham
por tag inexistente e regenera o fallback — convergiu em 5 iteracoes.

## 19.3 O que ja funciona

- `repo sync` completo (~90 GB)
- release config `ap1a` reconhecido
- `build/bazel` e `pgo-profiles` presentes
- **`soong_ui` compila e executa** (Go 1.21.4 do r50)

## 19.4 Blocker atual

`lunch twrp_jm21-ap1a-eng` falha com "Don't have a product spec". Investigado:

- `out/.module_paths/AndroidProducts.mk.list` **contem**
  `device/fiio/jm21/AndroidProducts.mk` (o finder acha o arquivo);
- porem `get_build_var TARGET_PRODUCT`, `COMMON_LUNCH_CHOICES` e
  `TARGET_DEVICE` saem **todos vazios**, inclusive `TARGET_PRODUCT` (que e
  entrada) -> o `product_config.mk` nao esta registrando nenhum produto.

Proximo passo: rodar o kati sem suprimir stderr (`get_build_var` puro) e ver o
erro real; suspeitas: `_read-ap-file`/`node_fns.mk` do `build/make` 14.1
esperando formato diferente, ou `PRODUCT_MAKEFILES` precisando da forma
`<produto>:<caminho>`.

## 19.5 Impasse de combinacao do build system (fim desta rodada)

Testadas duas configuracoes, ambas bloqueadas:

| config | resultado |
|---|---|
| `build/make` TWRP (14.1) + `build/soong` TWRP (android-14) + blueprint/Go r17 | da erros **reais**, mas o `build/make` 14.1 depende de modulos que o soong android-14 deles nao tem: `soong-aidl-library`, `soong-testing-*_proto` |
| `build/make` TWRP (14.1) + `build/soong` **AOSP r50** + blueprint/Go r50 | `soong_ui --dumpvar-mode` sai com **rc=1 e silencio total** (nem `out/verbose.log.gz` e criado); `lunch` so diz "Don't have a product spec" |

Ou seja: o `build/make` do TWRP 14 exige um soong mais novo que o fork deles,
mas o soong do AOSP r50 nao conversa com o `build/make` 14.1 deles.

Observacao util descoberta no caminho: o erro "Don't have a product spec" pode
ser simplesmente **release errado** — o `build/release` do r50 so declara
`ap2a` (nao `ap1a`), e o `lunch` correto e `twrp_jm21-ap2a-eng`.

Proximos caminhos possiveis:
1. AOSP 14 r50 **completo** (sem overlay de build do TWRP) + so
   `bootable/recovery` + `vendor/twrp`: perde-se os hooks de make do TWRP, mas
   elimina a incompatibilidade.
2. Voltar ao `twrp-12.1` (conhecido bom) e aceitar que `/data` nao abre.
3. Pedir a receita na comunidade do TWRP (Zulip) para o branch 14.

### 19.6 Terceira tentativa: build/make + build/soong ambos AOSP r50

Mantendo do TWRP so `bootable/recovery` e `vendor/twrp`:

`build/make` AOSP r50 + `build/soong` AOSP r50 + blueprint/Go r50.

Resultado: `lunch twrp_jm21-ap2a-eng` continua **rc=1** com o produto vazio e
sem mensagem de erro. Ou seja: mesmo com o build system do AOSP inteiro e
consistente, o produto nao e registrado — o que desloca a suspeita para a
interacao do `vendor/twrp` (hook de `TW_` vars no `soong_config.mk`) com o
`build/make` do AOSP, que nao tem esse hook.

Conclusao da rodada: o branch `android-14`/`android-14.1` do TWRP nao e
montavel apenas com os repos publicos + um device tree externo, do jeito que o
`twrp-12.1` era. Vale pedir a receita no Zulip do TWRP antes de insistir.

---

# 20. USB do TWRP: o culpado é o MTP

Sintoma: ao entrar no recovery o aparelho **desaparecia do barramento USB**
(nem `adb`, nem `lsusb`), de forma intermitente — o que parecia "bug de energia"
do aparelho.

Descoberta (observação do billzinho na tela do TWRP > Mount): alternando
**"Desabilitar MTP"** o aparelho **aparece** no sistema; com **"Habilitar MTP"**
ele **some**.

Confirmado por comando: com o MTP desabilitado na UI,

```
$ adb get-state      -> recovery
$ adb devices        -> 39dc45d6   recovery
$ lsusb -d 18d1:     -> ID 18d1:d001   (PID de adb)
```

Ou seja: a função MTP do nosso build (`libtwrpmtp-ffs`) falha ao subir o gadget
e **leva o adb junto**. Não é o aparelho, e não é o `init.recovery.usb.rc` (que
é byte-idêntico ao do Hovatek).

Correção recomendada no `BoardConfig.mk`:

```make
TW_EXCLUDE_MTP := true
```

(Ou `TW_HAS_MTP := false`, dependendo do fork.) Depois disso o recovery passa a
enumerar de forma determinística, previsível.

Observação: o "No space left on device" que apareceu durante os testes era o
`/tmp` do host (tmpfs de 7,8 GB) cheio de extrações de ramdisk — não tem
relação com o aparelho.

### 20.1 Correção aplicada e verificada

`TW_EXCLUDE_MTP := true` no `BoardConfig.mk` (o fork usa essa flag: tira
`-DTW_HAS_MTP` e `libtwrpmtp-ffs` do link do `recovery`).

Depois de recompilar e flashar:

```
adb reboot recovery
[28s] RECOVERY ADB OK (sem mexer no MTP)
ro.twrp.version = 3.7.1_12-jm21-billzinho
lsusb -> 18d1:d001
```

O recovery agora enumera sozinho, sempre, em ~28 s. Não é mais preciso
desabilitar MTP na tela de Mount.

Imagem boa: `~/jm21-artifacts/twrp-jm21-build-own-funcional.img` (atualizada).
