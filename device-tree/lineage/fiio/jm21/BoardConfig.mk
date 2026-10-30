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
    androidboot.console=ttyMSM0 androidboot.selinux=permissive
# bootconfig do vendor_boot — SEM isto o kernel ignora o trailer do ABL e
# perdemos ro.boot.bootdevice (monta /data), ro.boot.usbcontroller (sobe o
# gadget USB/ADB) e ro.boot.verifiedbootstate. Valores extraidos do stock.
BOARD_BOOTCONFIG := \
    androidboot.hardware=qcom \
    androidboot.memcg=1 \
    androidboot.load_modules_parallel=true \
    androidboot.usbcontroller=4e00000.dwc3 \
    androidboot.qhardware=SC200VWF

BOARD_KERNEL_BASE := 0x00000000
BOARD_KERNEL_PAGESIZE := 4096
BOARD_KERNEL_IMAGE_NAME := Image
TARGET_PREBUILT_KERNEL := $(DEVICE_PATH)/prebuilt/Image
BOARD_PREBUILT_DTBIMAGE_DIR := $(DEVICE_PATH)/prebuilt
BOARD_INCLUDE_DTB_IN_BOOTIMG := true
# vendor_boot: ramdisk minimo (o grosso dos modulos vive no vendor_dlkm)
BOARD_VENDOR_RAMDISK_KERNEL_MODULES := $(wildcard $(DEVICE_PATH)/prebuilt/vendor_ramdisk/lib/modules/*.ko)
BOARD_VENDOR_RAMDISK_KERNEL_MODULES_LOAD := $(patsubst $(DEVICE_PATH)/prebuilt/vendor_ramdisk/lib/modules/%,%,$(wildcard $(DEVICE_PATH)/prebuilt/vendor_ramdisk/lib/modules/*.ko))
BOARD_VENDOR_RAMDISK_RECOVERY_KERNEL_MODULES_LOAD := $(BOARD_VENDOR_RAMDISK_KERNEL_MODULES_LOAD)
BOARD_KERNEL_SEPARATED_DTBO := true
BOARD_PREBUILT_DTBOIMAGE := $(DEVICE_PATH)/prebuilt/dtbo.img
BOARD_BOOT_HEADER_VERSION := 4
BOARD_MKBOOTIMG_ARGS := --header_version $(BOARD_BOOT_HEADER_VERSION) --pagesize 4096

# ---------------------------------------------------------------- particoes
BOARD_BOOTIMAGE_PARTITION_SIZE := 100663296
BOARD_INIT_BOOT_IMAGE_PARTITION_SIZE := 8388608
# vendor_boot: nao geramos (o stock vai no flash; os modulos estao no vendor_dlkm)
BOARD_VENDOR_BOOTIMAGE_PARTITION_SIZE := 100663296
BOARD_RECOVERYIMAGE_PARTITION_SIZE := 100663296
BOARD_DTBOIMG_PARTITION_SIZE := 25165824

# super: 5371461632 bytes medidos no aparelho (5.122,6 MiB)
BOARD_SUPER_PARTITION_SIZE := 5371461632
BOARD_SUPER_PARTITION_GROUPS := qti_dynamic_partitions
BOARD_QTI_DYNAMIC_PARTITIONS_PARTITION_LIST := \
    system system_ext product vendor odm
BOARD_QTI_DYNAMIC_PARTITIONS_SIZE := 5367267328


# tamanhos das particoes dinamicas (medidos no lpdump do aparelho, docs/47 8.1)
BOARD_ODMIMAGE_PARTITION_SIZE := 2097152
BOARD_PRODUCTIMAGE_PARTITION_SIZE := 536870912
BOARD_SYSTEMIMAGE_PARTITION_SIZE := 2237026304
BOARD_SYSTEM_DLKMIMAGE_PARTITION_SIZE := 4194304
BOARD_SYSTEM_EXTIMAGE_PARTITION_SIZE := 529584128
BOARD_VENDORIMAGE_PARTITION_SIZE := 734003200
BOARD_VENDOR_DLKMIMAGE_PARTITION_SIZE := 838860800

BOARD_USES_METADATA_PARTITION := true
# mountpoints de /firmware e /persist: criados pelo init/fstab, nao no root image
# BOARD_ROOT_EXTRA_FOLDERS := firmware persist

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

# ------------------------------------------------------------------ recovery
TARGET_RECOVERY_FSTAB := $(DEVICE_PATH)/recovery.fstab
TARGET_RECOVERY_PIXEL_FORMAT := RGBX_8888

# ------------------------------------------------------------------- avb
# A verificacao fica DESLIGADA (flags=3 no vbmeta) enquanto o sistema nao for
# assinado com a chave da FIIO. Aplicar no flash, ver docs/47 §9.1.
# o stock tem AVB (footer no init_boot + vbmeta com descritores); sem isso o
# bootloader recusa boot/init_boot nao assinados
BOARD_AVB_ENABLE := true
BOARD_AVB_ALGORITHM := SHA256_RSA2048
BOARD_AVB_KEY_PATH := external/avb/test/data/testkey_rsa2048.pem
BOARD_AVB_ROLLBACK_INDEX := 0

# VINTF: nao pode ir por PRODUCT_COPY_FILES (checagem do build)
DEVICE_MANIFEST_FILE += vendor/fiio/jm21/proprietary/vendor/etc/vintf/manifest.xml
DEVICE_MATRIX_FILE += vendor/fiio/jm21/proprietary/vendor/etc/vintf/compatibility_matrix.xml

# fragmentos VINTF: o soong mescla em /vendor/etc/vintf/manifest.xml
DEVICE_MANIFEST_FILE += vendor/fiio/jm21/proprietary/vendor/etc/vintf/manifest/android.hardware.atrace@1.0-service.xml
DEVICE_MANIFEST_FILE += vendor/fiio/jm21/proprietary/vendor/etc/vintf/manifest/android.hardware.boot@1.2.xml
DEVICE_MANIFEST_FILE += vendor/fiio/jm21/proprietary/vendor/etc/vintf/manifest/android.hardware.cas@1.2-service.xml
DEVICE_MANIFEST_FILE += vendor/fiio/jm21/proprietary/vendor/etc/vintf/manifest/android.hardware.drm-service.clearkey.xml
DEVICE_MANIFEST_FILE += vendor/fiio/jm21/proprietary/vendor/etc/vintf/manifest/android.hardware.graphics.mapper-impl-qti-display.xml
DEVICE_MANIFEST_FILE += vendor/fiio/jm21/proprietary/vendor/etc/vintf/manifest/android.hardware.health-service.qti.xml
DEVICE_MANIFEST_FILE += vendor/fiio/jm21/proprietary/vendor/etc/vintf/manifest/android.hardware.radio.config.xml
DEVICE_MANIFEST_FILE += vendor/fiio/jm21/proprietary/vendor/etc/vintf/manifest/android.hardware.radio.messaging.xml
DEVICE_MANIFEST_FILE += vendor/fiio/jm21/proprietary/vendor/etc/vintf/manifest/android.hardware.radio.modem.xml
DEVICE_MANIFEST_FILE += vendor/fiio/jm21/proprietary/vendor/etc/vintf/manifest/android.hardware.radio.network.xml
DEVICE_MANIFEST_FILE += vendor/fiio/jm21/proprietary/vendor/etc/vintf/manifest/android.hardware.radio.sim.xml
DEVICE_MANIFEST_FILE += vendor/fiio/jm21/proprietary/vendor/etc/vintf/manifest/android.hardware.radio.voice.xml
DEVICE_MANIFEST_FILE += vendor/fiio/jm21/proprietary/vendor/etc/vintf/manifest/android.hardware.security.keymint-service-qti.xml
DEVICE_MANIFEST_FILE += vendor/fiio/jm21/proprietary/vendor/etc/vintf/manifest/android.hardware.thermal@2.0-service.qti.xml
DEVICE_MANIFEST_FILE += vendor/fiio/jm21/proprietary/vendor/etc/vintf/manifest/android.hardware.usb.gadget@1.1-service.xml
DEVICE_MANIFEST_FILE += vendor/fiio/jm21/proprietary/vendor/etc/vintf/manifest/android.hardware.usb@1.2-service.xml
DEVICE_MANIFEST_FILE += vendor/fiio/jm21/proprietary/vendor/etc/vintf/manifest/android.hardware.wifi.hostapd.xml
DEVICE_MANIFEST_FILE += vendor/fiio/jm21/proprietary/vendor/etc/vintf/manifest/android.hardware.wifi.supplicant.xml
DEVICE_MANIFEST_FILE += vendor/fiio/jm21/proprietary/vendor/etc/vintf/manifest/android.hardware.wifi@1.0-service.xml
DEVICE_MANIFEST_FILE += vendor/fiio/jm21/proprietary/vendor/etc/vintf/manifest/c2_manifest_vendor.xml
DEVICE_MANIFEST_FILE += vendor/fiio/jm21/proprietary/vendor/etc/vintf/manifest/c2_manifest_vendor_audio.xml
DEVICE_MANIFEST_FILE += vendor/fiio/jm21/proprietary/vendor/etc/vintf/manifest/deviceinfo-saidl.xml
DEVICE_MANIFEST_FILE += vendor/fiio/jm21/proprietary/vendor/etc/vintf/manifest/manifest_identity_credential.xml
DEVICE_MANIFEST_FILE += vendor/fiio/jm21/proprietary/vendor/etc/vintf/manifest/manifest_non_qmaa.xml
DEVICE_MANIFEST_FILE += vendor/fiio/jm21/proprietary/vendor/etc/vintf/manifest/manifest_non_qmaa_extn.xml
DEVICE_MANIFEST_FILE += vendor/fiio/jm21/proprietary/vendor/etc/vintf/manifest/memtrack_qti.xml
DEVICE_MANIFEST_FILE += vendor/fiio/jm21/proprietary/vendor/etc/vintf/manifest/power.xml
DEVICE_MANIFEST_FILE += vendor/fiio/jm21/proprietary/vendor/etc/vintf/manifest/qfp-daemon.xml
DEVICE_MANIFEST_FILE += vendor/fiio/jm21/proprietary/vendor/etc/vintf/manifest/qms-saidl.xml
DEVICE_MANIFEST_FILE += vendor/fiio/jm21/proprietary/vendor/etc/vintf/manifest/vendor.qti.diag.hal.service.xml
DEVICE_MANIFEST_FILE += vendor/fiio/jm21/proprietary/vendor/etc/vintf/manifest/vendor.qti.hardware.display.allocator-service.xml
DEVICE_MANIFEST_FILE += vendor/fiio/jm21/proprietary/vendor/etc/vintf/manifest/vendor.qti.hardware.display.composer-service.xml
DEVICE_MANIFEST_FILE += vendor/fiio/jm21/proprietary/vendor/etc/vintf/manifest/vendor.qti.hardware.lights.service.xml
DEVICE_MANIFEST_FILE += vendor/fiio/jm21/proprietary/vendor/etc/vintf/manifest/vendor.qti.hardware.limits-service.xml
DEVICE_MANIFEST_FILE += vendor/fiio/jm21/proprietary/vendor/etc/vintf/manifest/vendor.qti.hardware.perf.xml
DEVICE_MANIFEST_FILE += vendor/fiio/jm21/proprietary/vendor/etc/vintf/manifest/vendor.qti.hardware.radio.am.xml
DEVICE_MANIFEST_FILE += vendor/fiio/jm21/proprietary/vendor/etc/vintf/manifest/vendor.qti.hardware.radio.ims.xml
DEVICE_MANIFEST_FILE += vendor/fiio/jm21/proprietary/vendor/etc/vintf/manifest/vendor.qti.hardware.radio.qtiradioconfig.xml
DEVICE_MANIFEST_FILE += vendor/fiio/jm21/proprietary/vendor/etc/vintf/manifest/vendor.qti.hardware.servicetracker@1.2-service.xml
DEVICE_MANIFEST_FILE += vendor/fiio/jm21/proprietary/vendor/etc/vintf/manifest/vendor.qti.hardware.vibrator.service.xml
DEVICE_MANIFEST_FILE += vendor/fiio/jm21/proprietary/vendor/etc/vintf/manifest/vendor.qti.memory.pasrmanager@1.0-service.xml

# configuracao de board do Lineage
include vendor/lineage/config/BoardConfigLineage.mk

# Copiamos .so e binarios QCOM do stock: o build precisa permitir ELF em PRODUCT_COPY_FILES
BUILD_BROKEN_ELF_PREBUILT_PRODUCT_COPY_FILES := true

# O DeviceVendor (FiiO) declara uses-library android.fiio.dap.utils;
# o jar/xml vao por PRODUCT_COPY_FILES, entao relaxamos a checagem de manifest.
RELAX_USES_LIBRARY_CHECK := true

# AIDs extras do vendor (vendor_qrtr, vendor_qdss, ...)
TARGET_FS_CONFIG_GEN += $(DEVICE_PATH)/configs/config.fs

# init_boot precisa do header v4 (sem isto sai v0 e o bootloader recusa)
BOARD_MKBOOTIMG_INIT_ARGS := --header_version $(BOARD_BOOT_HEADER_VERSION)

# o stock usa ramdisk em lz4 (o nosso saia gzip)
BOARD_RAMDISK_USE_LZ4 := true

# O fstab do firmware exige um vbmeta_system para system/system_ext/product
# (avb=vbmeta_system). Sem isto o build nao gera o arquivo e /system nao monta.
BOARD_AVB_VBMETA_SYSTEM := system system_ext product
BOARD_AVB_VBMETA_SYSTEM_KEY_PATH := external/avb/test/data/testkey_rsa2048.pem
BOARD_AVB_VBMETA_SYSTEM_ALGORITHM := SHA256_RSA2048
BOARD_AVB_VBMETA_SYSTEM_ROLLBACK_INDEX := 0
BOARD_AVB_VBMETA_SYSTEM_ROLLBACK_INDEX_LOCATION := 1
