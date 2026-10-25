# Patches fora do device tree (no AOSP 12.1 + fork do TWRP)

O repo guarda só o device tree. Estas três mudanças vivem na árvore
(`~/twrp-full`) e são necessárias para a build funcionar. Sem elas o
`recovery` não linka ou não monta o `/vendor`.

## 1. `external/magisk-prebuilt/resetprop/Android.bp`

`TW_OVERRIDE_SYSTEM_PROPS` liga `TW_INCLUDE_LIBRESETPROP`, o binário `recovery`
passa a ter `DT_NEEDED libresetprop.so`, mas a lib só era instalada em
`system/lib64`. Sem isso: `CANNOT LINK EXECUTABLE "/system/bin/recovery"` e
crash-loop do serviço.

```diff
 cc_library {
     name: "libresetprop",
     compile_multilib: "first",
+    recovery: true,
     recovery_available: true,
```

## 2. `bootable/recovery/prebuilt/Android.mk`

`libminuitwrp` também não entrava no ramdisk sozinha. `recovery: true` no
`minuitwrp/Android.bp` **quebra** o `libguitwrp` (módulo estático usado nas
duas variantes: `error: dependency "libminuitwrp" of "libguitwrp" missing
variant`). A rota que funciona é incluí-la na lista do `relink.sh`.

```diff
 RECOVERY_LIBRARY_SOURCE_FILES += $(TARGET_OUT_SHARED_LIBRARIES)/liblogwrap.so
 RECOVERY_LIBRARY_SOURCE_FILES += $(TARGET_OUT_SHARED_LIBRARIES)/libext2_misc.so
+# libminuitwrp nao tem variante de recovery instalada; sem isto o binario
+# /system/bin/recovery nao linka dentro do ramdisk.
+RECOVERY_LIBRARY_SOURCE_FILES += $(TARGET_OUT_SHARED_LIBRARIES)/libminuitwrp.so
```

## 3. `bootable/recovery/partitionmanager.cpp` (só com crypto ligado)

`Decrypt_Data()` roda **antes** de `Setup_Super_Partition()`, então o `/vendor`
nunca está montado quando o keymaster precisa do `/vendor/firmware`.

```diff
 	#ifdef TW_INCLUDE_CRYPTO
+		/* JM21: o keymaster precisa de /vendor/firmware (apps do TEE) e das
+		   suas libs; sem o vendor montado a HAL nao registra e o decrypt trava. */
+		{
+			TWPartition* Vendor_Part = Find_Partition_By_Path("/vendor");
+			if (Vendor_Part && !Vendor_Part->Is_Mounted())
+				Vendor_Part->Mount(false);
+		}
 		DataManager::SetValue(TW_IS_ENCRYPTED, 1);
 		Decrypt_Data();
 	#endif
```

## Empacotamento (`~/twrp-full/build-recovery.sh`)

- descompacta o ramdisk do `recovery.img` (sai gzip) e recomprime em **LZ4
  legacy** (`lz4 -l -12 --no-frame-crc`);
- empacota com `/usr/bin/mkbootimg`, **não** o do AOSP (o `lunch` põe
  `out/host/linux-x86/bin` no PATH e ele injeta 4096 bytes de assinatura AVB
  zerada, que a imagem do Hovatek não tem);
- nunca inclui kernel: o ABL do JM21 usa o kernel do `boot_a`.

## Build sem derrubar a sessão do GNOME

`systemd-oomd` mata o app quando o build estoura a memória da sessão. Rodar
num escopo próprio faz o oomd matar o build:

```sh
systemd-run --user --unit=twrp-build --collect \
  -p MemoryMax=10G -p MemorySwapMax=10G -p Nice=19 \
  -- bash -c '~/twrp-full/build-recovery.sh > /tmp/build.log 2>&1'
```

Abaixo de 7G o soong bootstrap estoura o teto.
