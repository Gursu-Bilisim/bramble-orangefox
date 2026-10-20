## Pre-release test notes

Tested by the maintainer before publishing. Update this file for every release.

| Item | Value |
|---|---|
| Device | Google Pixel 4a (5G), bramble |
| ROM | lineage-23.2-20261010-NIGHTLY-bramble |
| Security patch (system / vendor) | 2026-10-01 / 2023-11-05 |
| Kernel (from the ROM boot.img) | 4.19.325-cip136-st20-g2af5306961ae |
| Lock screen | pattern, Titan M (Weaver) |
| Image SHA-256 | b477c31339d32e6ffdc7769f5244bc088acab900f79966d72b6a540e732d8f86 |

Tests with this image, flashed to `vendor_boot_b`:

| Test | Result | Notes |
|---|---|---|
| Decrypt /data with the pattern | OK | after Android 20261010 had started once and upgraded the metadata key to 2026-10 |
| ADB | OK | |
| MTP | OK | |
| Battery indicator | OK | |
| Status bar, camera cutout, accent colour, pattern touches | OK | |
| Backup list | OK | Boot, Data, Super, Vendor Boot, DTBO (`twrp.flags`) |
| Zip install from OrangeFox | OK | |
| Android boot with this vendor_boot | OK | from slot b |
| `recovery-inspect.ps1` (`.img` and `.zip`) | OK | all checks, including Display |
| `patch-check.ps1` against the ROM boot.img and the OTA zip | OK | `RESULT: match`, no `DECRYPT` line, `ROM INSTALL: Android starts` |

Tests with the previous image (2026-10-18, security patch 2026-09-01) on the same device:

| Test | Result | Notes |
|---|---|---|
| LineageOS 20261003 to 20261010 installed from OrangeFox | OK | written to slot b; Android started with the package's own vendor_boot; OrangeFox did not write itself back and does not offer "Reflash OrangeFox after flashing a ROM" |
| Decrypt with a lower security patch than the ROM | refused, as expected | 2026-09-01 image on 20261010 after its first boot: keymaster begin -62, upgradeKey -38, "Unable to decrypt metadata encryption"; /data stayed encrypted, the key was not changed, Android unaffected |
| Data backup to USB-OTG | OK | 37666 MB to an exFAT SD card in a powered USB hub (Storage 1); a first attempt stopped when the hub lost power |

Not tested: repeated wrong patterns (Titan M throttling), restoring a backup, LineageOS 24.0.
