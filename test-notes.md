## Pre-release test notes

Tested by the maintainer before publishing. Update this file for every release.

| Item | Value |
|---|---|
| Device | Google Pixel 4a (5G), bramble |
| ROM | lineage-24.0-20261017-NIGHTLY-bramble (Android 17), on both slots |
| Security patch (system / vendor) | 2026-10-01 / 2023-11-05 |
| Kernel (from the ROM boot.img) | 4.19.325-cip136-st20-g2af5306961ae, clang 22.0.2 |
| Lock screen | pattern, Titan M (Weaver) |
| Image SHA-256 | fd794a25a48e18ec59c3f43bbe5a7076c0eba980a6f325366a2a45e2ace8a909 |

Tests with this image, flashed to `vendor_boot_b` (slot b active):

| Test | Result | Notes |
|---|---|---|
| Decrypt /data with the pattern | OK | |
| ADB | OK | |
| MTP | OK | not while a USB stick is attached: the phone has one USB-C port and it is then in host mode. After removing the stick, turn MTP off and on |
| USB-OTG storage | OK for FAT32, exFAT and NTFS | listed as USB-Storage on the Mount page; NTFS through `ntfs-3g`, exFAT through `exfat-fuse` |
| Boot backup to an NTFS stick and restore | OK | Android started after the restore |
| Android boot with this vendor_boot | OK | |
| `recovery-inspect.ps1` | OK | |
| `patch-check.ps1` against the ROM boot.img | OK | `RESULT: match` |

Not repeated with this image (tested with v2026.10.21 on the same ROM): zip install from OrangeFox,
slot switching, booting from slot a.

Not tested: Format Data, repeated wrong patterns (Titan M throttling), a Data backup with this image.
