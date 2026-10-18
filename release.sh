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
REPO=Gursu-Bilisim/bramble-orangefox
PATCH=$(grep '^PLATFORM_SECURITY_PATCH' "$TREE/BoardConfig.mk" | awk '{print $3}')
TAG="v$(date +%Y.%m.%d)${1:+-$1}"
NAME="OrangeFox-bramble-$TAG-los23-$PATCH"
W=$(mktemp -d)
cp "$IMG" "$W/$NAME.img"
cp "$ZIP" "$W/$NAME.zip"
cp "$TREE/patch-check.ps1" "$TREE/recovery-inspect.ps1" "$W/"
cp "$TREE/test-notes.md" "$W/TEST-NOTES.md"
(cd "$W" && sha256sum *.img *.zip *.ps1 TEST-NOTES.md > SHA256SUMS)
{
cat <<NOTES
OrangeFox R12.0_1 for Google Pixel 4a (5G), bramble. Installed to vendor_boot.

- ROM: LineageOS 23.2, security patch $PATCH
- Decryption: FBE v2 + metadata encryption, Titan M (Weaver) for the lock screen

**vendor_boot is also used for the normal Android boot.** The image carries the kernel modules
of one LineageOS build. Do not flash it after a LineageOS update until \`patch-check.ps1\`
reports a match for the new build; a module mismatch can stop Android from booting.
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
