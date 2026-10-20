# Exports the OrangeFox settings only while twrp_bramble is selected, so that other devices
# in the same source tree are not affected. Set TARGET_PRODUCT before sourcing this file
# (see README.md, Building).
if [ "$TARGET_PRODUCT" = "twrp_bramble" ]; then
	# Device name
	export FOX_BUILD_DEVICE="bramble"
	export FOX_MAINTAINER_PATCH_VERSION="1"
	export OF_MAINTAINER="kgursu"

	# A/B, recovery inside vendor_boot
	export FOX_AB_DEVICE=1
	export FOX_VIRTUAL_AB_DEVICE=1
	export FOX_VENDOR_BOOT_RECOVERY=1
	export FOX_RECOVERY_SYSTEM_PARTITION="/dev/block/mapper/system"
	export FOX_RECOVERY_VENDOR_PARTITION="/dev/block/mapper/vendor"

	# Screen 1080x2340; status bar from the LineageOS bramble overlay
	# (status_bar_height_portrait 136px, punch hole centred at 77,78 with radius 39,
	# rounded_corner_content_padding 50px)
	export OF_SCREEN_H=2340
	export OF_SCREEN_W=1080
	export OF_STATUS_H=136
	export OF_STATUS_INDENT_LEFT=140
	export OF_STATUS_INDENT_RIGHT=50
	export OF_CLOCK_POS=1

	# Tools and build behaviour
	export FOX_ENABLE_APP_MANAGER=1
	export OF_ENABLE_LPTOOLS=1
	export FOX_VANILLA_BUILD=1
	export FOX_REPLACE_TOOLBOX_GETPROP=1
	export OF_USE_GREEN_LED=0
	export OF_DEFAULT_KEYMASTER_VERSION=4.0

	# Optional: the vendor_boot image of the LineageOS build you run, saved as
	# prebuilt/stock_vendor_boot.img (not in git). When present, OrangeFox takes the image
	# header and kernel command line from it and replaces only the ramdisk.
	_bramble_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
	if [ -f "$_bramble_dir/prebuilt/stock_vendor_boot.img" ]; then
	  export FOX_REFERENCE_VENDOR_BOOT_IMAGE="$_bramble_dir/prebuilt/stock_vendor_boot.img"
	fi
	unset _bramble_dir
fi
