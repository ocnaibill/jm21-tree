# 55 — Patches do `framework.jar` como diff contra o AOSP 13

Fonte dos patches: decompilação (`jadx`) do `framework.jar` stock do JM21,
comparada com a árvore AOSP 13 em `~/twrp13/frameworks/base`.

São **5 classes** (ver docs/54). Abaixo, cada patch com âncora exata e código.
Todos foram conferidos nas duas pontas (stock decompilado x AOSP 13).

---

## 1. `android/media/MediaRouter.java` — o que destrava o playback

Arquivo AOSP: `frameworks/base/media/java/android/media/MediaRouter.java`

### 1.1 Constantes (junto das outras constantes da classe)

```java
private static final String FIIO_CURRENT_PLAY_DEVICE = "fiio.current.play.device";
private static final String MEDIA_ROUTER_CHANGE      = "fiio.media.router.change";
private static final String OUT_DEVICE_USB_CARD_ID   = "output.device.usb.card.id";
```

Imports necessários (se ainda não houver): `android.os.SystemProperties`.

### 1.2 Dentro de `updateAudioRoutes(AudioRoutesInfo newRoutes)`

Âncora no AOSP 13 (linha ~268):

```java
            if (audioRoutesChanged) {
                Log.v(TAG, "Audio routes updated: " + newRoutes + ", a2dp=" + isBluetoothA2dpOn());
```

Inserir **logo após o `Log.v`**:

```java
                String fiioRoute;
                if (isBluetoothA2dpOn()) {
                    fiioRoute = "A2DP";
                } else if (SystemProperties.get(OUT_DEVICE_USB_CARD_ID, "0").equals("1")) {
                    fiioRoute = "USB";
                } else {
                    fiioRoute = typeToString(newRoutes.mainType);
                }
                SystemProperties.set(FIIO_CURRENT_PLAY_DEVICE, fiioRoute);
                if (Process.myUid() == Process.SYSTEM_UID) {
                    Log.d(TAG, "Current is System process send media route change "
                            + fiioRoute);
                    mAppContext.sendBroadcast(new Intent(MEDIA_ROUTER_CHANGE));
                }
```

`[FATO]` **É este patch que faz o FiiOMusic tocar.** Sem ele a property fica vazia
e o app morre em `Integer.parseInt("unknown")` (docs/47 §9.4).

Dependência silenciosa: `output.device.usb.card.id` é setada pelo lado do
vendor/dispositivo quando um DAC USB é plugado. Também não está declarada em
`property_contexts` (cai em `default_prop`, setável por system/vendor — ver
docs/47 §7.4).

---

## 2. `android/media/AudioTrack.java` — id da sessão

Arquivo AOSP: `frameworks/base/media/java/android/media/AudioTrack.java`

Primeira linha de `play()`:

```java
    public void play() throws IllegalStateException {
        SystemProperties.set("fiio.cur.session.id", String.valueOf(mSessionId));
        ...
```

Imports: `android.os.SystemProperties`.

`[FATO]` O FiiOMusic lê `fiio.cur.session.id` (docs/47 §9.4). Sem o patch o valor
fica vazio; no teste da GSI o app nem chegou aqui (parou antes), mas um port
precisa das duas properties.

---

## 3. `com/android/internal/os/PowerProfile.java` — capacidade real da bateria

Arquivo AOSP: `frameworks/base/core/java/com/android/internal/os/PowerProfile.java`

### 3.1 Campo estático

```java
    private static double mBattCapacity = 0.0d;
```

### 3.2 Método novo

```java
    private void getKernelBattCapacity() {
        String value = sysfsRead("/sys/devices/platform/soc/soc:fiio_attr/cw_batt_capacity");
        if (value == null || value.isEmpty()) {
            return;
        }
        try {
            mBattCapacity = Double.valueOf(value);
        } catch (NumberFormatException e) {
            // mantém o valor anterior
        }
        Slog.w(TAG, "Fiio Batt Capacity:" + mBattCapacity);
    }
```

(`sysfsRead` já existe na classe no AOSP 13.)

### 3.3 Chamada em `initLocked`

```java
    private void initLocked(Context context, int resourceId) {
        if (sPowerItemMap.size() == 0 && sPowerArrayMap.size() == 0) {
            getKernelBattCapacity();          // <-- inserir
            readPowerValuesFromXml(context, resourceId);
        }
        ...
```

### 3.4 Uso ao ler o XML

No trecho que trata `POWER_BATTERY_CAPACITY`:

```java
                if (POWER_BATTERY_CAPACITY.equals(entryName)) {
                    if (mBattCapacity > 0.0d) {
                        sPowerItemMap.put(entryName, mBattCapacity);
                    }
                }
```

`[FATO]` É o que faz o sistema reportar a capacidade correta da célula (o JM21
usa o `fiio-charger-manager`, não o PMIC padrão).

---

## 4. `android/media/AudioSystem.java` — constante de parâmetro MQA

Arquivo AOSP: `frameworks/base/media/java/android/media/AudioSystem.java`

```java
    public static final int CODEC_PARAM_FIIO_MQA = 9;
```

`[?]` O significado dos valores 0..8 **não** está no framework — quem consome é a
HAL (`libfiioaqm.so`). O patch só expõe a constante para os apps FiiO.

---

## 5. `android/content/ContentProvider.java` — exceções para o player

Arquivo AOSP: `frameworks/base/core/java/android/content/ContentProvider.java`

### 5.1 `enforceReadPermissionInner` — libera leitura para o player

Inserir depois de obter `packageName` e antes da checagem de permissão:

```java
        boolean fiioAllowRead = false;
        if (packageName != null
                && (packageName.equals("com.android.music")
                    || packageName.equals("com.android.dreams.phototable")
                    || packageName.equals("com.fiio.music"))) {
            fiioAllowRead = true;
            Log.d(TAG, "allow system music read permission ##");
        }
```

e usar na condição:

```java
        if (!UserHandle.isSameApp(callingUid, mMyUid) && !fiioAllowRead) {
```

### 5.2 `enforceWritePermissionInner` — libera escrita para o FiiOMusic

Logo após obter `packageName`:

```java
        if (packageName.equals("com.fiio.music")
                || UserHandle.isSameApp(callingUid, mMyUid)) {
            return 0;
        }
```

Observação de segurança: é uma exceção **por nome de pacote**, sem checar
assinatura. Num port, vale endurecer (checar a assinatura do chamador) — mas
fiel ao stock é assim.

---

## 6. Ordem de aplicação sugerida

1. `MediaRouter` (destrava playback) — testável isoladamente;
2. `AudioTrack` (`fiio.cur.session.id`);
3. `ContentProvider` (leitura/escrita do player);
4. `PowerProfile` (bateria);
5. `AudioSystem` (constante).

Depois, os 11 do `services.jar` (docs/54 §2), que são listas de pacote,
concessão de permissão e três broadcasts.

## 7. Como validar cada um

| patch | teste objetivo |
|---|---|
| MediaRouter | `getprop fiio.current.play.device` deve virar `SPEAKER`/`USB`/`A2DP` durante playback |
| AudioTrack | `getprop fiio.cur.session.id` != vazio ao tocar |
| PowerProfile | `dumpsys batterystats` / capacity reportada = 21,24 GB? (não: capacidade em mAh) |
| ContentProvider | FiiOMusic lê a biblioteca sem erro de permissão |
| AudioSystem | app FiiO compila/lê a constante (sem crash de `NoSuchField`) |
