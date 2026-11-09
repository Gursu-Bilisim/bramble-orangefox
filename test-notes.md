## Pre-release test notes

Tested by the maintainer before publishing. Update this file for every release.

| Item | Value |
|---|---|
| Device | Google Pixel 4a (5G), bramble |
| ROM | lineage-24.0-20261024-NIGHTLY-bramble (Android 17), slot a |
| Security patch (system / vendor) | 2026-10-01 / 2023-11-05 |
| Kernel (from the ROM boot.img) | 4.19.325-cip136-st20-g2af5306961ae, clang 22.0.2 |
| Lock screen | pattern, Titan M (Weaver) |
| Image SHA-256 | 60a974c2ccef8bca15efef0c748dbc255b0ff35b0e057aea5cf53a4b2aba1cc8 |

Changes from v2026.10.22: the shared `system/vold` patch (no recursive `restorecon` over the
credential-encrypted storage after decryption; gatekeeper `mdfpp` instance looked up first), the
shared recovery patch with the persist mount check and the `minuitwrp` changes from gts7xlwifi,
and the 2026.11.09 tools. The ramdisk's `recovery` binary contains the new vold (`mdfpp`).

Tests with this image, flashed to `vendor_boot_a` (slot a active):

| Test | Result | Notes |
|---|---|---|
| Decrypt /data with the pattern | OK | |
| ADB | OK | |
| `/data/misc_ce/0/checkin` label after decrypting in OrangeFox | OK | `u:object_r:checkin_data_file:s0:c512,c768`, the same as in Android before flashing |
| Android boot with this vendor_boot | OK | |
| `checkin` label and user storage in Android afterwards | OK | `s0:c512,c768`, `sys.user.0.ce_available` `true`; the directory's time stayed 2026-11-01 07:45, so it was not recreated; logcat has no `Relabelling` or `deleting for recreation` line, and `vold_prepare_subdirs` ran without error |
| `recovery-inspect.ps1` 2026.11.09 | OK | all lines |
| `patch-check.ps1` against the ROM boot.img | OK | `RESULT: match` |

With the earlier images, each OrangeFox session that decrypted `/data` relabelled `checkin` to
`s0`, and LineageOS 24 deleted and recreated the directory on the next boot (see
[patches/README.md](patches/README.md)). The directory's time, 2026-11-01 07:45, is from such an
earlier recreation.

Not repeated with this image (tested with v2026.10.21 and v2026.10.22 on LineageOS 24.0): MTP,
USB-OTG storage, backup and restore, zip install from OrangeFox, slot switching.

Not tested: Format Data, repeated wrong patterns (Titan M throttling).
