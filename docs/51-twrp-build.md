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
