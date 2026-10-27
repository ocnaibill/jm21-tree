# 56 — Patches do `services.jar` como diff contra o AOSP 13

Complemento do docs/55 (framework). São **11 classes**, todas com patches de 1 a
~10 linhas. Fonte: `jadx` do `services.jar` stock x árvore AOSP 13 em `~/twrp13`.

Índice:

| # | classe | o que faz |
|---|---|---|
| 1 | `am/ActivityManagerService` | torna processos FiiO persistentes (`maxAdj = -900`) |
| 2 | `pm/PackageManagerService` | exceção em `checkPackageStartable` |
| 3 | `pm/ComputerEngine` | exceção na geração de `ApplicationInfo` |
| 4 | `am/OomAdjuster` | impede o freezer de congelar apps FiiO |
| 5 | `pm/permission/DefaultPermissionGrantPolicy` | concede permissões ao player |
| 6 | `am/ContentProviderHelper` | libera `checkContentProviderPermission` p/ apps FiiO |
| 7 | `audio/AudioService` | volume USB conforme `usb_vol_ctl` |
| 8 | `usb/UsbAlsaManager` | broadcast de entrada/saída de DAC USB |
| 9 | `power/PowerManagerService` | intents de carga/descarga externa |
| 10 | `policy/PhoneWindowManager` | tecla de power, home, KEY.EVENT |
| 11 | `statusbar/StatusBarManagerService` | exceção no BinderDied do update |

---

## 1–4. A mesma ideia: lista de pacotes FiiO

Lista base (igual em 3 classes, `PackageManagerService` tem também
`com.fiio.scrcpy`):

```java
private static final String[] FIIO_PACKAGE_NAMES = {
    "com.fiio.music", "com.android.aboutfiio", "com.fiio.control",
    "com.fiio.android", "com.fiio.devicevendor", "com.android.fiioupdate",
    "com.android.fiio.scrcpy", "com.fiio.market"
};
private static boolean isHighPackage(String pkg) {
    return Arrays.asList(FIIO_PACKAGE_NAMES).indexOf(pkg) != -1;
}
```

### 1. `ActivityManagerService`

Em `startProcessLocked(...)`/criação do `ProcessRecord` — âncora: o bloco que
trata `(info.flags & FLAG_PERSISTENT) != 0`:

```java
if ((app.flags & ApplicationInfo.FLAG_PERSISTENT) != 0) {
    app.setPersistent(true);
    ...
}
// FiiO:
if (isHighPackage(app.packageName)) {
    app.setPersistent(true);
    app.mState.setMaxAdj(-900);      // acima do persistente padrão (-800)
}
```

### 2. `PackageManagerService.checkPackageStartable`

```java
if (pkgName == null || !isHighPackage(pkgName)) {
    ... // checagens originais (instant app, usuário, cross-user, startability)
}
```

### 3. `ComputerEngine` (geração de `ApplicationInfo`)

Na condição que hoje exige `isPersistent()`, adicionar a alternativa:

```java
if (isHighPackage(pkg.getPackageName()) || (pkg.isPersistent() && ...)) {
```

### 4. `OomAdjuster.updateAppFreezeState` (ou equivalente)

```java
public static boolean cantFreezePackage(String pkg) {
    return Arrays.asList(FIIO_PACKAGE_NAMES).indexOf(pkg) != -1;
}
...
if (!mCachedAppOptimizer.useFreezer() || proc.mOptRecord.isFreezeExempt()
        || cantFreezePackage(proc.processName)) {
    return;
}
```

`[FATO]` Juntas, essas quatro fazem o que se vê no stock: os apps do DAP nunca
são mortos nem congelados, e o sistema não os bloqueia na inicialização.

---

## 5. `DefaultPermissionGrantPolicy` — permissões do player

Em `grantDefaultSystemHandlerPermissions` (bloco de localização/microfone):

```java
grantPermissionsToPackage(pm, "com.fiio.music", userId, false, true, ALWAYS_LOCATION_PERMISSIONS);
grantPermissionsToPackage(pm, "com.fiio.music", userId, false, true, set7);   // CONTACTS
grantPermissionsToPackage(pm, "com.fiio.music", userId, false, true, set11);  // STORAGE
grantPermissionsToPackage(pm, "com.fiio.music", userId, false, true, MICROPHONE_PERMISSIONS);
grantPermissionsToPackage(pm, "com.fiio.music", userId, false, true, set12);
grantPermissionsToPackage(pm, "com.fiio.market", userId, false, true, set11);
grantPermissionsToPackage(pm, "com.android.fiioupdate", userId, false, true, set11);
grantPermissionsToPackage(pm, "com.android.aboutfiio", userId, false, true, set11);
```

`[?]` `set7` / `set11` / `set12` são os `Set<String>` locais já existentes no
método (contatos / armazenamento / etc.). Ao aplicar o patch, usar os mesmos
objetos do AOSP 13.

---

## 6. `ContentProviderHelper.checkContentProviderPermission`

Logo no início do método:

```java
if (mService.getAppName(uid).contains("fiio")) {
    return null;    // sem checagem de permissão para apps FiiO
}
```

Observação: é checagem por **substring do nome do app**, não por pacote. Num
port, vale restringir à lista explícita.

---

## 7. `AudioService` — volume USB

Em `VolumeStreamState.setStreamVolumeIndex` (bloco do `STREAM_MUSIC`):

```java
if (Settings.System.getInt(mContentResolver, "usb_vol_ctl", 1) == 0
        && SystemProperties.get("fiio.current.play.device", "HEADPHONES").equals("USB")) {
    index = AudioService.MAX_STREAM_VOLUME[mStreamType];
}
```

**Semântica:** com `usb_vol_ctl = 0` (controle de volume do DAC USB desligado),
o volume do stream vai a **máximo** — quem controla é o DAC externo. Depende do
patch nº 1 do framework (`fiio.current.play.device`).

---

## 8. `UsbAlsaManager` — broadcast de DAC USB

Na inserção (após `"usb audio device insert"`) e na remoção (quando o dispositivo
removido é o selecionado):

```java
if (Process.myUid() == Process.SYSTEM_UID) {
    Intent intent = new Intent("fiio.intent.action.USB_AUDIO_DEVICE_CHANGE");
    intent.putExtra("EXTRA_ACTION", 1);   // 0 = remoção
    mContext.sendBroadcast(intent);
}
```

---

## 9. `PowerManagerService` — carga/descarga externa

No `BroadcastReceiver` de bateria:

```java
if (action.equals("fiio.intent.action.ACTION_EXTERNAL_CHARGING")
        || action.equals("fiio.intent.action.ACTION_EXTERNAL_DISCHARGING")) {
    mPowerInChanged = true;
}
```

E registrar as duas ações no `IntentFilter` (junto de `ACTION_BATTERY_CHANGED`).

`[FATO]` É o gancho pelo qual o `fiio-charger-manager` (vendor) informa o sistema
sobre a carga — e explica o `health=Overheat`/JEITA visto em campo (docs/12).

---

## 10. `PhoneWindowManager` — teclas e home

Três métodos novos:

```java
public boolean getShowPowerKeyView() {
    return SystemProperties.getBoolean("fiio.test.show_power_key_view", false);
}

public final boolean isDisableHomeKey() {
    boolean disabled = SystemProperties.getBoolean("sys.fiio.home_disabled", false);
    Log.i(TAG, "isDisableHomeKey:  " + disabled);
    return disabled;
}

public final void sendKeyEventToModeSelection(int keyCode, int keyAction) {
    Intent intent = new Intent("fiio.intent.action.KEY.EVENT");
    intent.putExtra("keyCode", keyCode);
    intent.putExtra("keyAction", keyAction);
    mContext.sendBroadcastAsUser(intent, UserHandle.ALL);
}
```

Chamados nos pontos de intercepção de tecla (power / home) do AOSP.

`[HIP]` É o candidato mais provável de ligação com a **roda/teclas físicas** do
JM21 — mas a roda em si pode ser tratada no app (`com.fiio.*`), não aqui.

---

## 11. `StatusBarManagerService` — update não derruba a status bar

No `binderDied()` do `TokenMonitor`/`CommandQueue`:

```java
if (pkg.equals("com.android.fiioupdate")) {
    return;     // não desabilita a status bar quando o app de update morre
}
```

---

## 12. Validação

| patch | teste |
|---|---|
| 1–4 | `dumpsys activity processes` mostra apps FiiO com `maxAdj=-900` e não congelados |
| 5 | `pm list permissions` / `dumpsys package com.fiio.music` mostra permissões concedidas |
| 6 | FiiOMusic lê a biblioteca sem `SecurityException` em provider |
| 7 | com `usb_vol_ctl=0` e DAC USB, mexer no volume do sistema não muda o volume do DAC |
| 8 | plugar DAC → broadcast `fiio.intent.action.USB_AUDIO_DEVICE_CHANGE` (ver no logcat do FiiOMusic) |
| 9 | `dumpsys power` reage ao charger-manager |
| 10 | tecla power abre o diálogo FiiO; `sys.fiio.home_disabled=1` desabilita home |
| 11 | matar `com.android.fiioupdate` não derruba a status bar |

## 13. Onde isso encaixa

Com docs/55 (5 classes de framework) + este (11 de services), o **lado
`system` reimplementável está mapeado por completo**. O que resta como prebuilt
são os 6 APKs (SystemUI, Settings e os apps OEM) e os overlays — ver docs/54 §5.
