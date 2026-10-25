# Device tree TWRP — FiiO JM21 (bengal_515 / SM6225)

Pré-requisitos (não versionados — pegar dos dumps):
- `prebuilt/Image`  <- kernel do `dumps/fw-1.1.1/boot.img` (unpack_bootimg)
- `prebuilt/dtb`    <- dtb do `dumps/fw-1.1.1/vendor_boot.img`
- `recovery/root/lib/modules/`: `qcom_ipc_logging.ko`, `i2c-msm-geni.ko`
  (do vendor_boot) + `fiio_primary_modules.ko`, `ts_core.ko`,
  `goodix_gt9xx_ts.ko` (do vendor_dlkm).

Uso (no tree do TWRP `twrp-12.1`, em `~/twrp`):
```
cp -r device-tree/fiio ~/twrp/device/
cd ~/twrp && source build/envsetup.sh && lunch twrp_jm21-eng
mka recoveryimage -j8
```
Ver `docs/51-

twrp-build.md` para o estado e as pendências.
