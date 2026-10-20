#!/usr/bin/env bash
set -euo pipefail
# TREE: <device tree folder>, the folder this script is in (device/google/bramble).
# FOX_TREE: <OrangeFox source tree>, three levels above it. Set FOX_TREE to override.
# Before running: update test-notes.md for this build, commit and push.
TREE=$(cd "$(dirname "$0")" && pwd)
FOX_TREE=${FOX_TREE:-$(cd "$TREE/../../.." && pwd)}
OUT=$FOX_TREE/out/target/product/bramble
IMG=$(ls -t "$OUT"/OrangeFox-*-bramble.img 2>/dev/null | head -1 || true)
ZIP=${IMG%.img}.zip
[ -n "$IMG" ] && [ -f "$ZIP" ] || { echo "No OrangeFox build found in $OUT. Set FOX_TREE=<OrangeFox source tree>." >&2; exit 1; }
[ -f "$TREE/test-notes.md" ] || { echo "test-notes.md is missing." >&2; exit 1; }
if [ "$TREE/test-notes.md" -ot "$IMG" ]; then
  echo "test-notes.md is older than $(basename "$IMG"). Update it for this build first." >&2; exit 1
fi
SHA=$(sha256sum "$IMG" | awk '{print $1}')
grep -q "$SHA" "$TREE/test-notes.md" || { echo "test-notes.md does not name the image SHA-256 ($SHA)." >&2; exit 1; }
(cd "$FOX_TREE/bootable/recovery" && git diff) | cmp -s - "$TREE/patches/bootable_recovery.diff" \
  || { echo "bootable/recovery differs from patches/bootable_recovery.diff; regenerate the patch first." >&2; exit 1; }
(cd "$FOX_TREE/hardware/qcom-caf/bootctrl" && git diff) | cmp -s - "$TREE/patches/hardware_qcom-caf_bootctrl.diff" \
  || { echo "hardware/qcom-caf/bootctrl differs from patches/hardware_qcom-caf_bootctrl.diff; regenerate the patch first." >&2; exit 1; }
REPO=Gursu-Bilisim/bramble-orangefox
PATCH=$(grep '^PLATFORM_SECURITY_PATCH' "$TREE/BoardConfig.mk" | awk '{print $3}')
PV=$(grep -E '^PLATFORM_VERSION[[:space:]]*:=' "$TREE/BoardConfig.mk" | awk '{print $3}')
case "$PV" in
  16) LOS=23.2 ;;
  17) LOS=24.0 ;;
  *) echo "Unknown PLATFORM_VERSION $PV; add its LineageOS version to release.sh." >&2; exit 1 ;;
esac
TAG="v$(date +%Y.%m.%d)${1:+-$1}"
NAME="OrangeFox-bramble-$TAG-los${LOS%%.*}-$PATCH"
W=$(mktemp -d)
cp "$IMG" "$W/$NAME.img"
cp "$ZIP" "$W/$NAME.zip"
cp "$TREE/patch-check.ps1" "$TREE/recovery-inspect.ps1" "$W/"
cp "$TREE/test-notes.md" "$W/TEST-NOTES.md"
(cd "$W" && sha256sum *.img *.zip *.ps1 TEST-NOTES.md > SHA256SUMS)
{
cat <<NOTES
OrangeFox R12.0_1 for Google Pixel 4a (5G), bramble. Installed to vendor_boot.

- ROM: LineageOS $LOS only, security patch $PATCH (build named in the test notes below)
- Decryption: FBE v2 + metadata encryption, Titan M (Weaver) for the lock screen

**vendor_boot is also used for the normal Android boot.** The image carries the kernel modules
of one LineageOS $LOS build. Do not flash it on another build, or after a LineageOS update, until
\`patch-check.ps1\` reports a match; a module mismatch can stop Android from booting.
A LineageOS OTA replaces vendor_boot, so OrangeFox has to be installed again afterwards.
Other ROMs need a rebuild of this tree with their own images; see "Other ROMs" in README.md.

- \`.img\`: \`fastboot flash vendor_boot_a <img>\` (use the active slot), then select
  Recovery mode in the bootloader menu
- \`.zip\`: install from a running OrangeFox; it writes vendor_boot_a and vendor_boot_b
- \`patch-check.ps1 -BootImg <ROM boot.img> -RecoveryImg <img>\` or \`-Zip <ota.zip>\`
- \`recovery-inspect.ps1 -Img <img or zip>\`

Source: device tree in this repository at tag $TAG; changes outside the device tree in
\`patches/\`. Credits: see NOTICE.

NOTES
cat "$TREE/test-notes.md"
} > "$W/notes.md"
gh release create "$TAG" "$W"/*.img "$W"/*.zip "$W"/*.ps1 "$W/TEST-NOTES.md" "$W/SHA256SUMS" \
  --repo "$REPO" --title "$TAG" --notes-file "$W/notes.md"
echo "Published: $TAG"
