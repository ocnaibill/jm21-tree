#
# lineage_jm21.mk — produto
#

$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/full_base_telephony.mk)
$(call inherit-product, device/fiio/jm21/device.mk)

PRODUCT_NAME := lineage_jm21
PRODUCT_DEVICE := jm21
PRODUCT_BRAND := FiiO
PRODUCT_MODEL := JM21
PRODUCT_MANUFACTURER := FiiO

# Propriedades do stock (dumps/fw-1.1.1, build.prop)
PRODUCT_SYSTEM_PROPERTIES += \
    ro.fiio.device=JM21

TARGET_SCREEN_HEIGHT := 1334
TARGET_SCREEN_WIDTH := 750

PRODUCT_BUILD_PROP_OVERRIDES += \
    PRIVATE_BUILD_DESC="qti/bengal_515/bengal_515:13/TKQ1.230110.001/eng.fiio.20260428.144644:user/dev-keys"

BUILD_FINGERPRINT := qti/bengal_515/bengal_515:13/TKQ1.230110.001/eng.fiio.20260428.144644:user/dev-keys
