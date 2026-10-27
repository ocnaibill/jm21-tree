# Patches

Os diffs completos estao em `docs/55` (framework) e `docs/56` (services). Aqui
estao os `.patch` **gerados de verdade**: aplicados numa arvore AOSP 13, com
`git diff` e revertidos em seguida.

```
framework/   0001-MediaRouter     0002-AudioTrack   0003-PowerProfile
             0004-AudioSystem      0005-ContentProvider
services/    01-ActivityManagerService   02-ContentProviderHelper
             03-OomAdjuster            04-AudioService
             05-ComputerEngine         06-PackageManagerService
             07-DefaultPermissionGrantPolicy
             08-PhoneWindowManager     09-PowerManagerService
             10-StatusBarManagerService 11-UsbAlsaManager
```

Total: **16 arquivos, 168 linhas inseridas** (64 no framework, 104 no services).

Aplicar:

```bash
./apply-patches.sh /caminho/da/arvore-lineage
```

## `framework-res/config_fiio.xml`

As **61 flags** `config_fiio_*` extraidas do `framework-res.apk` stock
(`docs/54` §7). O conteudo deste arquivo deve ser **mesclado** em:

```
frameworks/base/core/res/res/values/config.xml
```

Isso e obrigatorio porque **RRO nao adiciona recursos** — so sobrescreve os que
ja existem. Sem declarar as flags no framework-res, `RRO` e `getBoolean()` pelos
apps falham.

## framework (5 classes) — docs/55

| arquivo AOSP | patch |
|---|---|
| `media/java/android/media/MediaRouter.java` | 3 constantes + bloco no `updateAudioRoutes` |
| `media/java/android/media/AudioTrack.java` | `play()` seta `fiio.cur.session.id` |
| `core/java/com/android/internal/os/PowerProfile.java` | `getKernelBattCapacity()` |
| `media/java/android/media/AudioSystem.java` | `CODEC_PARAM_FIIO_MQA = 9` |
| `core/java/android/content/ContentProvider.java` | excecoes de leitura/escrita |

## services (11 classes) — docs/56

Lista completa em `docs/56`. As quatro primeiras compartilham a mesma lista
`FIIO_PACKAGE_NAMES`.

## Procedimento

```bash
# a partir da raiz da arvore LineageOS 20
cd frameworks/base
git checkout -b fiio-jm21
# aplicar os .patch (quando existirem), ou editar seguindo docs/55
git format-patch -1 > ../../device/fiio/jm21/patches/0001-....patch
```

Sugestao: um commit por classe, para poder testar/cancelar isoladamente — o
`MediaRouter` e o que destrava o playback e deve ser o primeiro.
