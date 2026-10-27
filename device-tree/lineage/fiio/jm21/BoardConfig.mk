#
# BoardConfig — FiiO JM21 (bengal_515) / LineageOS 20 (Android 13)
#
# Valores de particao medidos no aparelho (ver docs/47 §8) e herdados do
# device tree do TWRP (device-tree/fiio/jm21/BoardConfig.mk).
#

DEVICE_PATH := device/fiio/jm21

# ---------------------------------------------------------------- arquitetura
TARGET_ARCH := arm64
TARGET_ARCH_VARIANT := armv8-a
TARGET_CPU_ABI := arm64-v8a
TARGET_CPU_VARIANT := generic
TARGET_CPU_VARIANT_RUNTIME := cortex-a73
TARGET_2ND_ARCH := arm
TARGET_2ND_ARCH_VARIANT := armv8-a
TARGET_2ND_CPU_ABI := armeabi-v7a
TARGET_2ND_CPU_ABI2 := armeabi
TARGET_2ND_CPU_VARIANT := generic
TARGET_2ND_CPU_VARIANT_RUNTIME := cortex-a53
TARGET_USES_64_BIT_BINDER := true
TARGET_SUPPORTS_64_BIT_APPS := true

TARGET_BOARD_PLATFORM := bengal
TARGET_BOARD_PLATFORM_GPU := qcom-adreno610
TARGET_BOOTLOADER_BOARD_NAME := bengal_515
TARGET_USES_VULKAN := true

# --------------------------------------------------------------------- kernel
# Sem fonte GPL (issues #10/#17): o kernel entra como PREBUILT, extraido do
# boot.img stock. Os modulos de vendor (vendor_dlkm) sao os do firmware.
BOARD_KERNEL_CMDLINE := console=ttyMSM0,115200n8 androidboot.hardware=qcom \
    androidboot.console=ttyMSM0
BOARD_KERNEL_BASE := 0x00000000
BOARD_KERNEL_PAGESIZE := 4096
BOARD_KERNEL_IMAGE_NAME := Image
TARGET_PREBUILT_KERNEL := $(DEVICE_PATH)/prebuilt/Image
BOARD_PREBUILT_DTBIMAGE_DIR := $(DEVICE_PATH)/prebuilt
BOARD_INCLUDE_DTB_IN_BOOTIMG := true
BOARD_KERNEL_SEPARATED_DTBO := true
BOARD_BOOT_HEADER_VERSION := 4
BOARD_MKBOOTIMG_ARGS := --header_version $(BOARD_BOOT_HEADER_VERSION) --pagesize 4096

# ---------------------------------------------------------------- particoes
BOARD_BOOTIMAGE_PARTITION_SIZE := 100663296
BOARD_INIT_BOOT_IMAGE_PARTITION_SIZE := 8388608
BOARD_VENDOR_BOOTIMAGE_PARTITION_SIZE := 100663296
BOARD_RECOVERYIMAGE_PARTITION_SIZE := 100663296
BOARD_DTBOIMG_PARTITION_SIZE := 25165824

# super: 5371461632 bytes medidos no aparelho (5.122,6 MiB)
BOARD_SUPER_PARTITION_SIZE := 5371461632
BOARD_SUPER_PARTITION_GROUPS := qti_dynamic_partitions
BOARD_QTI_DYNAMIC_PARTITIONS_PARTITION_LIST := \
    system system_ext product vendor odm
BOARD_QTI_DYNAMIC_PARTITIONS_SIZE := 5367267328

BOARD_USES_METADATA_PARTITION := true
BOARD_ROOT_EXTRA_FOLDERS := firmware persist

# ------------------------------------------------------------------ A/B
AB_OTA_UPDATER := true
AB_OTA_PARTITIONS += \
    boot dtbo init_boot vendor_boot \
    system system_ext product vendor odm vendor_dlkm system_dlkm
BOARD_USES_RECOVERY_AS_BOOT := false
TARGET_NO_RECOVERY := false
BOARD_VIRTUAL_AB_OTA := true

# --------------------------------------------------------------- filesystem
TARGET_USES_MKE2FS := true

# tipos de filesystem por particao (todas ext4 no stock)
BOARD_SYSTEMIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_SYSTEM_EXTIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_PRODUCTIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_ODMIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_VENDOR_DLKMIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_SYSTEM_DLKMIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_USERDATAIMAGE_FILE_SYSTEM_TYPE := ext4
TARGET_USERIMAGES_USE_EXT4 := true
TARGET_USERIMAGES_USE_F2FS := true
TARGET_COPY_OUT_VENDOR := vendor
TARGET_COPY_OUT_ODM := odm
TARGET_COPY_OUT_SYSTEM_EXT := system_ext
TARGET_COPY_OUT_PRODUCT := product
TARGET_COPY_OUT_VENDOR_DLKM := vendor_dlkm
TARGET_COPY_OUT_SYSTEM_DLKM := system_dlkm

# --------------------------------------------------------------- sepolic y
BOARD_VENDOR_SEPOLICY_DIRS += $(DEVICE_PATH)/sepolicy/vendor
SYSTEM_EXT_PRIVATE_SEPOLICY_DIRS += $(DEVICE_PATH)/sepolicy/private

# ------------------------------------------------------------------ recovery
TARGET_RECOVERY_FSTAB := $(DEVICE_PATH)/recovery.fstab
TARGET_RECOVERY_PIXEL_FORMAT := RGBX_8888

# ------------------------------------------------------------------- avb
# A verificacao fica DESLIGADA (flags=3 no vbmeta) enquanto o sistema nao for
# assinado com a chave da FIIO. Aplicar no flash, ver docs/47 §9.1.
BOARD_AVB_ENABLE := false
