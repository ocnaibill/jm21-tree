# Device tree — FiiO JM21 (bengal_515) para LineageOS 20 (Android 13)

Esqueleto de trabalho. **Não é uma árvore buildável ainda** — é o andaime com as
decisões já tomadas e medidas, para não se perder o que foi descoberto.

Base de conhecimento (ler antes de mexer):

| doc | conteúdo |
|---|---|
| `docs/54` | inventário dos patches (5 framework + 11 services) e as 61 flags |
| `docs/55` | patches do `framework.jar` como diff contra AOSP 13 |
| `docs/56` | patches do `services.jar` como diff contra AOSP 13 |
| `docs/47` | o que a GSI provou (o contrato system↔vendor) |
| `docs/05` | mapa do fork oficial (onde vive cada coisa) |
| `docs/12` | energia/carga (fiio-charger-manager, JEITA) |

## Por que Android 13

O vendor é `board.api_level=33` / `vendor.api_level=33` / `vndk=33`, e o
`framework.jar`/`services.jar` da FiiO são **A13**. A14+ exigiria reimplementar
os patches em outra versão de framework. **A13 é o teto do port fiel.**

## Estratégia (decidida em docs/54 §5)

| componente | como entra |
|---|---|
| `framework.jar` (5 classes) | **patch** aplicado ao Lineage (docs/55) |
| `services.jar` (11 classes) | **patch** (docs/56) |
| 61 `config_fiio_*` | **merge** em `frameworks/base/core/res/res/values/config.xml` |
| `SystemUI.apk`, `Settings.apk`, 18 apps OEM | **prebuilt**, re-assinados com a chave da ROM |
| HALs, módulos de kernel, libs FiiO | **vendor/odm/vendor_dlkm** extraídos do stock |

Ponto não resolvido: **assinatura**. A chave de plataforma é da FIIO
(`CN=Android, OU=Android, L=Guangzhou, pengweizhong@fiio.net`). Os APKs
prebuilt precisam ser **re-assinados com a chave da ROM**, e a sepolicy/allowlist
de permissões privilegiadas ajustada em conjunto.

## Estrutura

```
fiio/jm21/
├── AndroidProducts.mk
├── BoardConfig.mk
├── device.mk
├── lineage_jm21.mk
├── lineage.dependencies
├── patches/
│   ├── framework-res/config_fiio.xml     <- merge em core/res/values/
│   └── README.md                         <- onde entram os diffs de docs/55 e 56
├── prebuilts/README.md                   <- quais APKs, de onde, como re-assinar
└── sepolicy/README.md                    <- property_contexts e regras FiiO
```

## Ordem de trabalho sugerida

1. **Sincronizar** o LineageOS 20 (`repo init -b lineage-20.0`) — ~100 GB.
2. **Extrair os blobs** do stock (`dumps/fw-1.1.1` + partições do aparelho) para
   `vendor/fiio/jm21/` com `extract-files`.
3. **Aplicar** patches de framework/services e o merge das 61 flags.
4. **Empacotar** os prebuilts (re-assinados).
5. **Buildar e comparar** com o stock pelos 6 critérios de aceitação:
   boot, áudio, DAC/FPGA (mixer), roda/teclas, SD, modo USB DAC.

## Critérios de aceitação (do docs/47 §7.4)

| subsistema | como verificar |
|---|---|
| boot | tela + `adb` |
| áudio | tocar FLAC pelo FiiOMusic |
| DAC/FPGA | `tinymix` lista `DAC Playback Volume`; filtro/balanço mudam |
| roda de volume | girar e ver o volume mudar |
| SD | montar e ler |
| modo USB DAC | plugar no PC e aparecer como DAC |

Se **áudio e DAC** passarem, o port está no caminho. Se a **roda** falhar, é o
`PhoneWindowManager` (docs/56 §10) ou um hook no app.

## Estado atual

- [x] inventário dos patches (16 classes)
- [x] as 61 flags extraídas com valores
- [x] patches de framework escritos (docs/55)
- [x] patches de services escritos (docs/56)
- [ ] árvore LineageOS 20 sincronizada
- [ ] blobs extraídos
- [ ] patches aplicados e buildando
- [ ] prebuilts re-assinados
