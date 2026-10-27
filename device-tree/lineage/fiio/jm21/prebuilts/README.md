# Prebuilts

## O que entra

| APK | origem | observação |
|---|---|---|
| `SystemUI.apk` | `system_ext/priv-app/SystemUI` do stock | 51 classes com `fiio`; inclui `com.android.systemui.fiio.*` |
| `Settings.apk` | `system_ext/priv-app/Settings` (95 MB) | 104 classes com `fiio`, 92 em `com.android.settings.fiio.*` |
| 18 apps OEM | `system/app/*` | `FiiOMusic`, `FiiOEq`, `FiiOTape`, `FiiOCast`, `FiiOIpod`, `FiiOMarket`, `FiiOUpdate`, `AboutFiio`, `ModeSelection`, `DeviceVendor`, `EnterSleep`, `FactoryTest`, `DebugTool`, `EcaiTestAPP`, `Roon`, `Scrcpy`, `WIFI`, ... |

Extração:

```bash
debugfs -R "dump /priv-app/Settings/Settings.apk /tmp/Settings.apk" \
    dumps/fw-1.1.1/system_ext.img
```

## O problema da assinatura (não resolvido)

A chave de plataforma é da FIIO:

```
subject: C=CN, ST=Guangdong, L=Guangzhou, OU=Android, CN=Android,
         emailAddress=pengweizhong@fiio.net
SHA-256: B3:CA:AA:E4:C3:64:FB:E0:D9:15:F9:74:3A:31:B5:3D:76:C0:0D:B9:8B:A2:0B:FE:60:1B:57:CB:3E:5C:B9:19
```

Não temos a chave privada. Opções:

1. **Re-assinar tudo com a chave da ROM** (`apksigner`). Mecânico, mas tem de ser
   feito em conjunto com a ROM (mesma chave para todos), para os apps
   continuarem se reconhecendo. Nem `Settings` nem `FiiOMusic` usam
   `sharedUserId` (verificado) — o que ajuda.
2. Manter os APKs como estão e buildar a ROM com a chave da FIIO: impossível sem
   a chave privada.
3. Reimplementar Settings/SystemUI a partir do decompilado: pesado (51 + 104
   classes).

**Recomendação:** opção 1, começando pelo `Settings` (mais visível, quebra
isolada) e deixando o `SystemUI` por último (se der errado, a UI inteira cai).

## Permissões privilegiadas

No stock os apps são `priv-app`. Ao empacotar como prebuilt:

- `Android.mk`/`Android.bp` com `LOCAL_PRIVILEGED_MODULE := true`;
- `privapp-permissions-<pkg>.xml` com o que cada app pede;
- conferir assinatura compatível com as permissões de nível `signature`.

Ponto de atenção medido: o `ContentProviderHelper` da FIIO libera permissão por
**substring do nome do app** (`contains("fiio")`), não por pacote. Num port vale
restringir à lista explícita (ver docs/56 §6).
