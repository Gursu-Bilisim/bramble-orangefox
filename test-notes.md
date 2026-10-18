## Pre-release test notes

Tested by the maintainer before publishing. Update this file for every release.

| Item | Value |
|---|---|
| Device | Google Pixel 4a (5G), bramble |
| ROM | lineage-23.2-20261003-NIGHTLY-bramble (userdebug) |
| Security patch (system / vendor) | 2026-09-01 / 2023-11-05 |
| Kernel (from the ROM boot.img) | 4.19.325-cip136-st20-g2af5306961ae |
| Lock screen | pattern, Titan M (Weaver) |

| Test | Result | Notes |
|---|---|---|
| Decrypt /data with the pattern | OK | Accepted on the first attempt |
| ADB | OK | |
| MTP | OK | recovery.log still shows `E:[MTP] Failed to start usb driver!`; transfers work |
| Battery indicator | OK | read from `/sys/class/power_supply/battery` |
| Status bar and camera cutout | OK | clock right of the punch hole |
| Boot control | OK | `bootctl get-number-slots` 2; slot b selected and back to a from the reboot menu without rebooting |
| Zip install from OrangeFox | OK | writes `vendor_boot_a` and `vendor_boot_b`; after the reboot OrangeFox starts and decrypts /data |
| Android boot with this vendor_boot | OK | |
| `recovery-inspect.ps1` | OK | all Decryption and Titan M checks |
| `patch-check.ps1` against the ROM boot.img | OK | patch level and kernel modules match |

Not tested: booting from slot b (marked unbootable on the test device), a LineageOS OTA with this
image installed, repeated wrong patterns (Titan M throttling), backup and restore.
