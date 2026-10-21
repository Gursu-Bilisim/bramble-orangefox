# Changes outside the device tree

The releases of this repository are built from OrangeFox Recovery `fox_12.1` with two patches
applied outside `device/google/bramble`. Base revisions are listed in `BASE_REVISION`.

## bootable_recovery.diff

Applies to OrangeFox `bootable/recovery`, commit `cbcc4f713dbef98d76d6d2cfd019b1ebfd9418e9`.
TWRP and OrangeFox are licensed under the GNU General Public License, version 3 or later, and so
are these changes (see `COPYING`). The same source tree also builds
[Gursu-Bilisim/tucana-orangefox](https://github.com/Gursu-Bilisim/tucana-orangefox) and
[Gursu-Bilisim/jackpotlte-orangefox](https://github.com/Gursu-Bilisim/jackpotlte-orangefox), so the
patch contains the changes made for those devices as well.

- `partitionmanager.cpp`: when the ROM's fstab is copied to `/etc/additional.fstab`,
  `/dev/block/bootdevice/by-name/` paths are rewritten to `/dev/block/by-name/`, so that `/data`
  is resolved to its block device and FBE is detected.
- `partitionmanager.cpp`: before metadata decryption, `persist` is mounted read-only at
  `/mnt/vendor/persist` and `modem` read-only at `/vendor/firmware_mnt`, so that the QTI
  keymaster and its listeners find their files. The modem partition name gets the slot suffix
  on A/B devices, and nothing is mounted when `/vendor/firmware_mnt/image` already exists
  (bramble mounts it from `init.recovery.bramble.rc`).
- `gui/patternpassword.cpp`, `gui/objects.hpp`: `GUIPatternPassword::IsInRegion`. A dot accepts
  touches within three dot radii of its centre, which reaches past the pattern's placement box
  for the corner dots. A touch that started there was outside the box, so the page ignored the
  whole gesture. The pattern now also claims touches that hit a dot.
- `minuitwrp/resources.cpp`, `minuitwrp/include/minuitwrp/minui.h`, `gui/nanosvg.cpp`,
  `gui/resources.cpp`: on devices built with `TARGET_RECOVERY_PIXEL_FORMAT := ABGR_8888`
  (`res_swap_red_blue()` returns 1), SVG output, tints and shapes swap red and blue, so the
  orange accent no longer shows as blue (made for jackpotlte). bramble uses `RGBX_8888`, where
  the function returns 0 and nothing changes; the `recovery` binary still needs the new
  `libminuitwrp.so`.
- `orangefox.mk`, `data.cpp`, `gui/pages.cpp`: new build variable `OF_SCREEN_BOTTOM_INSET`
  (pixels, default 0). The theme variables `screen_original_h` and `screen_h` become
  `OF_SCREEN_H` minus the inset, so the lock-screen swipe, the navigation buttons and the bottom
  menu move up by that amount, while the theme is still scaled to the full `OF_SCREEN_H` (new
  constant `screen_full_h`). bramble does not set it, so nothing changes here (made for tucana,
  whose screen curves at the bottom edge).
- Theme (`pages/templates/templates.xml`, `resources/vars.xml`): the "show password" eye icon on
  the decrypt page only reacted to touches on its 64x46 px image. An invisible 144x144 px button
  centred on the icon (`pass_show_touch_x`, `pass_show_touch_y`) now does the same (made for
  tucana).
- Theme (`gui/theme/portrait_hdpi/themes/navbar.xml`): gesture navigation is off by default and
  the screen height no longer adds 96 px for a hidden navigation bar (made for tucana).

## hardware_qcom-caf_bootctrl.diff

Applies to LineageOS `android_hardware_qcom_bootctrl`, branch `lineage-19.1-caf`, commit
`9ed7376299a15399624ebff4fcf8b8a162cd6c34`, checked out at `hardware/qcom-caf/bootctrl`
(BSD 3-Clause, The Linux Foundation).

- `BOOT_IMG_PTN_NAME` is changed from `"boot"` to `"boot_"`. The HAL counts slots by listing
  `/dev/block/bootdevice/by-name` entries that start with this name. The recovery creates a
  `boot -> boot_a` link there, so the HAL reported 3 slots and accepted slot number 2, while its
  suffix table only holds `_a` and `_b`. The name is used only in that count.

## Applying

```bash
cd <OrangeFox source tree>/bootable/recovery
git checkout cbcc4f713dbef98d76d6d2cfd019b1ebfd9418e9
git apply <this repository>/patches/bootable_recovery.diff

git clone -b lineage-19.1-caf https://github.com/LineageOS/android_hardware_qcom_bootctrl \
  <OrangeFox source tree>/hardware/qcom-caf/bootctrl
cd <OrangeFox source tree>/hardware/qcom-caf/bootctrl
git checkout 9ed7376299a15399624ebff4fcf8b8a162cd6c34
git apply <this repository>/patches/hardware_qcom-caf_bootctrl.diff
```

`navbar.xml` uses CRLF line endings upstream; the diff keeps them, so apply it without
converting line endings.
