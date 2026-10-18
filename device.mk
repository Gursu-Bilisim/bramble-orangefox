LOCAL_PATH := device/google/bramble

# Virtual A/B (snapuserd is in the boot ramdisk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/virtual_ab_ota.mk)

PRODUCT_USE_DYNAMIC_PARTITIONS := true
PRODUCT_SHIPPING_API_LEVEL := 30

AB_OTA_UPDATER := true
AB_OTA_PARTITIONS += \
    boot \
    dtbo \
    product \
    system \
    system_ext \
    vbmeta \
    vbmeta_system \
    vendor \
    vendor_boot

# Vendor ramdisk: first_stage_ramdisk and lib/modules from LineageOS 23.2, unchanged.
# The normal Android boot uses these files as well.
BRAMBLE_VENDOR_RAMDISK := $(LOCAL_PATH)/prebuilt/vendor_ramdisk
PRODUCT_COPY_FILES += \
    $(foreach f,$(shell cd $(BRAMBLE_VENDOR_RAMDISK) && find . -type f | sed 's|^\./||'), \
        $(BRAMBLE_VENDOR_RAMDISK)/$(f):$(TARGET_COPY_OUT_VENDOR_RAMDISK)/$(f))

# Boot control HAL (HIDL 1.2, QTI): bootctrl/ and gpt-utils/
PRODUCT_SOONG_NAMESPACES += $(LOCAL_PATH)
PRODUCT_PACKAGES += \
    android.hardware.boot@1.2-impl-qti.recovery
