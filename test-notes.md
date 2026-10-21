## Pre-release test notes

Tested by the maintainer before publishing. Update this file for every release.

| Item | Value |
|---|---|
| Device | Google Pixel 4a (5G), bramble |
| ROM | lineage-24.0-20261017-NIGHTLY-bramble (Android 17), on both slots |
| Security patch (system / vendor) | 2026-10-01 / 2023-11-05 |
| Kernel (from the ROM boot.img) | 4.19.325-cip136-st20-g2af5306961ae, clang 22.0.2 |
| Lock screen | pattern, Titan M (Weaver) |
| Image SHA-256 | 0c4b685f0166c2baddb0b25d3d243d015efc791886850ed9a146d89bbd669045 |

Tests with this image:

| Test | Result | Notes |
|---|---|---|
| Decrypt /data with the pattern | OK | on slot a and slot b, after LineageOS 24.0 had started |
| ADB | OK | |
| MTP | OK | also after decrypt |
| Battery indicator | OK | |
| Status bar, camera cutout, accent colour, pattern touches | OK | |
| Backup list | OK | Boot, Data, Super, Vendor Boot, DTBO |
| USB-OTG storage | OK for exFAT and FAT32 | an exFAT SD card and a FAT32 USB stick in a powered USB hub are mounted as Storage 1; an NTFS stick is not mounted (no `ntfs-3g` in this build); the connection dropped at times on the test device, whose USB port is worn |
| Zip install from OrangeFox | OK | writes `vendor_boot_a` and `vendor_boot_b`; after the reboot OrangeFox started and decrypted /data |
| Android boot with this vendor_boot | OK | from slot a and from slot b |
| Boot control | OK | slot A selected in the reboot menu, Android started from slot a; back to slot b the same way |
| `recovery-inspect.ps1` | OK | Android 17; Titan M services on the Android 16 runtime |
| `patch-check.ps1` against the ROM boot.img and the OTA zip | OK | `RESULT: match` (clang 22.0.2 on both sides), no `DECRYPT` line, `ROM INSTALL: Android starts` |

Update from LineageOS 23.2-20261010 to 24.0-20261017 on the test device:

| Step | Result | Notes |
|---|---|---|
| Install to slot a | OK | from OrangeFox (v2026.10.20 image) on slot b; Android 24.0 started, data kept |
| microG before the first boot | OK | from slot a's Lineage recovery 24.0 (installer reported SDK 37); the Google account stayed |
| microG from OrangeFox before the first boot | not usable | this image on slot a showed the slot's previous system (SDK 36); the update was still a compressed snapshot and OrangeFox does not run `snapuserd` |
| Install to slot b | OK | from this image on slot a, microG from slot b's Lineage recovery; account kept |

Not tested: repeated wrong patterns (Titan M throttling), restoring a backup, a Data backup with
this image (tested with the v2026.10.18 image: 37666 MB to an exFAT SD card).
