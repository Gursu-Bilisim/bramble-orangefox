$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/aosp_base.mk)
$(call inherit-product, device/google/bramble/device.mk)

PRODUCT_NAME := twrp_bramble
PRODUCT_DEVICE := bramble
PRODUCT_BRAND := google
PRODUCT_MODEL := Pixel 4a (5G)
PRODUCT_MANUFACTURER := Google

PRODUCT_PACKAGES += \
    qcom_decrypt \
    qcom_decrypt_fbe
