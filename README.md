# bramble-orangefox

OrangeFox R12.0 (fox_12.1) for the Google Pixel 4a (5G), `bramble`, with `/data` decryption on
LineageOS 23.2 (Android 16). The device has no recovery partition, so OrangeFox is built into
`vendor_boot`.

Tested build, test results and known gaps: [test-notes.md](test-notes.md). Every release carries
its own `TEST-NOTES.md`.

## What works

- Decryption of FBE v2 with metadata encryption: QTI keymaster 4.0 and gatekeeper through
  `qseecomd`, keystore2, and the lock screen credential through Titan M (Weaver)
- ADB, MTP, battery indicator, slot selection (QTI boot control 1.2)
- Normal Android boot from the same `vendor_boot`

## Read this before flashing

`vendor_boot` is not only the recovery here. Android's first stage boots from it too, and it
carries the kernel modules of one LineageOS build (`lib/modules`, 221 modules). Consequences:

- Use an image built for the LineageOS build you run. `patch-check.ps1` compares the security
  patch and the module version with the ROM's `boot.img` or OTA zip.
- A LineageOS OTA replaces `vendor_boot` and removes OrangeFox. Do not flash an older OrangeFox
  image after an update: if the kernel changed, the modules no longer load and Android may not
  boot. Wait for a matching release or build one.
- Keep a copy of your stock `vendor_boot` (see below) to go back.

## Installing

1. Unlock the bootloader and keep the stock `vendor_boot` of your LineageOS build. Either extract
   it from the LineageOS zip (`payload.bin`, for example with payload-dumper-go), or copy it on
   the phone with `adb root` (userdebug builds) and
   `adb shell dd if=/dev/block/by-name/vendor_boot_a of=/sdcard/vendor_boot_a.img`
   (use your active slot).
2. Check the image: `patch-check.ps1 -BootImg <ROM boot.img> -RecoveryImg <OrangeFox .img>`.
3. `fastboot flash vendor_boot_a <OrangeFox .img>` for the active slot, or install the `.zip` from a
   running OrangeFox (it writes `vendor_boot_a` and `vendor_boot_b`).
4. The bootloader does not accept `fastboot reboot recovery`; choose Recovery mode in the
   bootloader menu with the volume and power keys.

If `adb reboot` from a recovery that did not start completely brings you back to the recovery, the
misc partition still holds the recovery command. Clear it from a shell in the recovery:
`dd if=/dev/zero of=/dev/block/by-name/misc bs=2048 count=1`.

## Building

1. Sync OrangeFox `fox_12.1` (see the OrangeFox wiki) into `<OrangeFox source tree>`.
2. Clone this repository to `<OrangeFox source tree>/device/google/bramble`.
3. Apply the two patches in [patches/](patches/README.md) (`bootable/recovery` and
   `hardware/qcom-caf/bootctrl`).
4. Optional: save the stock `vendor_boot` of your LineageOS build as
   `prebuilt/stock_vendor_boot.img`. OrangeFox then keeps its header and kernel command line and
   only replaces the ramdisk. Without it the image is built from this tree alone.
5. Build:

```bash
cd <OrangeFox source tree>
source build/envsetup.sh
export ALLOW_MISSING_DEPENDENCIES=true
lunch twrp_bramble-eng
for v in $(compgen -e | grep -E '^(OF_|FOX_)'); do unset "$v"; done
source device/google/bramble/vendorsetup.sh
touch bootable/recovery/orangefox.mk
mka adbd vendorbootimage
```

The output is `out/target/product/bramble/OrangeFox-*-bramble.img` and `.zip`.

The `unset`, `source` and `touch` lines matter when the source tree holds other OrangeFox devices:
`envsetup.sh` sources every `device/*/*/vendorsetup.sh` in alphabetical order and the last one
wins, and the `OF_`/`FOX_` values are compiled into the recovery through
`bootable/recovery/orangefox.mk`, which Kati only re-reads when a makefile changes.

`BOARD_AVB_ENABLE := true` in `BoardConfig.mk` is needed for the OrangeFox packaging step: in
fox_12.1 `build/make/core/Makefile` calls it only in the AVB branch of the `vendor_boot` rule.

### Updating for a new LineageOS build

Take `Image.lz4` and the DTB from the new `boot.img`, `dtbo.img`, and `first_stage_ramdisk` and
`lib/modules` from the new `vendor_boot.img`, then update `PLATFORM_SECURITY_PATCH` and
`VENDOR_SECURITY_PATCH` in `BoardConfig.mk`. A recovery with a lower patch level than the ROM
fails with keymaster error -38; a higher one may upgrade the metadata key so that the ROM can no
longer unlock `/data`.

## Other ROMs

A released image is built for one LineageOS build. It carries that build's kernel modules and
reports its security patch, so it is not a general Pixel 4a (5G) recovery:

- On a ROM with a different kernel the modules do not load, and because `vendor_boot` is also
  used for the Android boot, Android may not start either. `patch-check.ps1` prints the module
  version next to the ROM kernel; flash only when it reports a match.
- If the ROM's security patch differs, keymaster refuses the metadata key (lower patch) or
  upgrades it (higher patch).

Supporting another ROM means rebuilding this tree with that ROM's images, as described in
"Updating for a new LineageOS build". The decryption chain uses the QTI keymaster 4.0, gatekeeper
and Titan M files from the vendor image with fingerprint
`google/bramble/bramble:14/UP1A.231105.001.B2`. A ROM that ships the same vendor image and the
same encryption settings (FBE v2 with metadata encryption) needs only the kernel, modules, DTB,
dtbo and patch values replaced. A ROM with a different vendor image may need the files in
`recovery/root` replaced as well; `recovery-inspect.ps1` lists them.

If you build and test this tree on another ROM, please open an issue with the ROM name and
build, the `patch-check.ps1` output and `/tmp/recovery.log`.

## Tools

### patch-check.ps1

Checks whether a recovery image fits a ROM build before you flash it. For a `vendor_boot` image it
reads the Android version and security patch from the ramdisk's `prop.default` and compares the
kernel module version with the ROM kernel; for a `recovery.img` it reads the image header.
Works in Windows PowerShell 5.1 and PowerShell 7. A/B OTA packages (`payload.bin`) need
[payload-dumper-go](https://github.com/ssut/payload-dumper-go) or the `payload_dumper` bundled with
Multi Image Kitchen.

```
powershell -ExecutionPolicy Bypass -File patch-check.ps1 -BootImg <boot.img> -RecoveryImg <OrangeFox .img>
powershell -ExecutionPolicy Bypass -File patch-check.ps1 -Zip <ota.zip> -RecoveryImg <OrangeFox .img>
```

Example output:

```
Boot header    : Android 16.0.0, patch 2026-09 (header v3)
Boot kernel    : 4.19.325-cip136-st20-g2af5306961ae
Recovery props : Android 16.0.0, patch 2026-09-01 (vendor_boot v3)
Recovery kmods : 4.19.325-cip136-st20-g2af5306961ae
RESULT: match, no rebuild needed
```

### recovery-inspect.ps1

Lists what a bramble OrangeFox image contains: first stage files and modules, the QTI decryption
chain, the Titan M services with their Android 16 runtime, boot control, and USB. Accepts the
`.img` or the OrangeFox `.zip`.

```
powershell -ExecutionPolicy Bypass -File recovery-inspect.ps1 -Img <OrangeFox .img | .zip>
```

### release.sh

Publishes the latest build as a GitHub release: image, zip, both scripts, `TEST-NOTES.md` and
`SHA256SUMS`. It stops if `test-notes.md` is older than the image. `./release.sh r2` adds a suffix
for a second release on the same day; `FOX_TREE=<OrangeFox source tree> ./release.sh` if the build
is not three folders above the device tree.

## Credits and license

Built with the work of TeamWin, OrangeFox, LineageOS and the sources listed in [NOTICE](NOTICE).

- Files written for this repository: Apache License 2.0 ([LICENSE](LICENSE)).
- Changes to OrangeFox/TWRP: GPL-3.0-or-later, in [patches/](patches/).
- Prebuilt Google, Qualcomm and STMicroelectronics vendor files: not covered by either license.

If you reuse parts of this tree, keep the NOTICE file and credit the sources it lists.
