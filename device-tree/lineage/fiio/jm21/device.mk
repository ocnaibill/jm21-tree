#
# device.mk — FiiO JM21
#
# Regra de ouro deste port: o que for **hardware** vem do vendor stock; o que
# for **experiencia DAP** vem dos patches (docs/55, 56) + prebuilts.
#

LOCAL_PATH := device/fiio/jm21

# ------------------------------------------------------- blobs do stock
# Extraidos de dumps/fw-1.1.1 e das particoes vendor/odm/vendor_dlkm do
# aparelho. Ver prebuilts/README.md.
$(call inherit-product-if-exists, vendor/fiio/jm21/jm21-vendor.mk)

# ------------------------------------------------------- configs do device
PRODUCT_COPY_FILES += \

# ------------------------------------------------------- permissao privilegiada
# Os 18 APKs da FIIO sao priv-app no stock (Settings/SystemUI tambem).
PRODUCT_PACKAGES += \
    adb_debug.prop \
    snapuserd.ramdisk \
    FiiOMusic \
    FiiOEq \
    FiiOTape \
    FiiOCast \
    FiiOIpod \
    FiiOMarket \
    FiiOUpdate \
    AboutFiio \
    ModeSelection \
    DeviceVendor \
    EnterSleep \
    FactoryTest \
    DebugTool \
    EcaiTestAPP \
    Roon \
    Scrcpy \
    WIFI

# SystemUI/Settings da FIIO entram como prebuilt (ver prebuilts/README.md).
# Manter desligado ate o re-assinamento estar resolvido:
# PRODUCT_PACKAGES += FiioSystemUI FiioSettings

# ------------------------------------------------------- propriedades
PRODUCT_PRODUCT_PROPERTIES += \
    persist.sys.fiio.config=FiiODPA \
    persist.sys.usb.config=adb \
    ro.vendor.build.security_patch=2026-04-05

# ------------------------------------------------------- overlay de recursos
# ATENCAO: RRO **nao adiciona** recursos, so sobrescreve. As 61 flags
# config_fiio_* precisam existir no framework-res da ROM — por isso elas entram
# como patch (patches/framework-res/config_fiio.xml), nao como overlay.
# DEVICE_PACKAGE_OVERLAYS := $(LOCAL_PATH)/overlay

# ------------------------------------------------------- sepolicy

# biblioteca do DAP (android.fiio.dap.utils): o DeviceVendor declara uses-library
PRODUCT_COPY_FILES += \
    device/fiio/jm21/prebuilts/files/system_ext/framework/FiioDapUtils.jar:$(TARGET_COPY_OUT_SYSTEM_EXT)/framework/FiioDapUtils.jar \
    device/fiio/jm21/prebuilts/files/system_ext/etc/permissions/fiiodaputilslib.xml:$(TARGET_COPY_OUT_SYSTEM_EXT)/etc/permissions/fiiodaputilslib.xml

PRODUCT_COPY_FILES += \

PRODUCT_COPY_FILES += \

# /force_debuggable faz o init carregar o adb_debug.prop (ro.adb.secure=0,
# ro.debuggable=1); sem ele nao ha adb no boot do sistema — o recovery usa
# outro caminho e por isso funcionava.
PRODUCT_COPY_FILES += \
    device/fiio/jm21/prebuilt/init_boot/force_debuggable:$(TARGET_COPY_OUT_RAMDISK)/force_debuggable

# workaround do qspmhal (ver o proprio .rc)
PRODUCT_COPY_FILES += \
    device/fiio/jm21/rootdir/system/etc/init/fiio_qspmhal.rc:$(TARGET_COPY_OUT_SYSTEM)/etc/init/fiio_qspmhal.rc
