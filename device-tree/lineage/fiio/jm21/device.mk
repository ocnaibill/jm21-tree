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
    ro.vendor.build.security_patch=2026-04-05

# ------------------------------------------------------- overlay de recursos
# ATENCAO: RRO **nao adiciona** recursos, so sobrescreve. As 61 flags
# config_fiio_* precisam existir no framework-res da ROM — por isso elas entram
# como patch (patches/framework-res/config_fiio.xml), nao como overlay.
# DEVICE_PACKAGE_OVERLAYS := $(LOCAL_PATH)/overlay

# ------------------------------------------------------- sepolicy
