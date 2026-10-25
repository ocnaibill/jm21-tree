$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit_only.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/base.mk)

PRODUCT_NAME := twrp_jm21
PRODUCT_DEVICE := jm21
PRODUCT_BRAND := FiiO
PRODUCT_MODEL := FiiO JM21
PRODUCT_MANUFACTURER := FiiO
PRODUCT_SYSTEM_NAME := jm21
PRODUCT_SYSTEM_DEVICE := jm21

# libminuitwrp e dependencia do binario 'recovery' mas nao entra no ramdisk
# sozinha (sem variante recovery instalada) -> declarar explicitamente.
TARGET_RECOVERY_DEVICE_MODULES += libminuitwrp
