#!/bin/zsh
set -eu
set -o pipefail
cd "$(dirname "$0")/.."
: "${TCL_NOTARY_PROFILE:?Set TCL_NOTARY_PROFILE to your saved notarytool profile.}"
TCL_SIGNER="${TCL_RELEASE_CODESIGN_IDENTITY:-}"
if [[ -z "$TCL_SIGNER" && -f .release-codesign-identity ]]; then
  TCL_SIGNER="$(cat .release-codesign-identity)"
fi
if [[ -z "$TCL_SIGNER" || "$TCL_SIGNER" == "-" ]]; then
  echo "Set TCL_RELEASE_CODESIGN_IDENTITY to a Developer ID Application certificate."
  exit 1
fi
TCL_APP="$PWD/dist/release/TCLimate.app"
TCL_VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$TCL_APP/Contents/Info.plist")"
TCL_RELEASE_DIR="$PWD/dist/releases/v$TCL_VERSION"
TCL_DMG="TCLimate-v$TCL_VERSION-universal.dmg"
mkdir -p "$TCL_RELEASE_DIR"
codesign --verify --deep --strict "$TCL_APP"
xcrun stapler validate "$TCL_APP"
spctl --assess --type execute --verbose=2 "$TCL_APP"
# Release tooling only; dmgbuild and uv are not app runtime dependencies.
uvx --from dmgbuild==1.6.7 dmgbuild -s Scripts/dmg-settings.py \
  -D "app=$TCL_APP" -D "notices=$PWD/THIRD_PARTY_NOTICES.md" "TCLimate" "$TCL_RELEASE_DIR/$TCL_DMG"
# Check the copied app: Finder metadata must not invalidate its signature.
TCL_DMG_MOUNT="$(mktemp -d "$PWD/dist/dmg-verify.XXXXXX")"
function tcl_dmg_cleanup() {
  hdiutil detach "$TCL_DMG_MOUNT" >/dev/null 2>&1 || true
  rmdir "$TCL_DMG_MOUNT" 2>/dev/null || true
}
trap tcl_dmg_cleanup EXIT
hdiutil attach -readonly -nobrowse -quiet -mountpoint "$TCL_DMG_MOUNT" "$TCL_RELEASE_DIR/$TCL_DMG"
test "$(readlink "$TCL_DMG_MOUNT/Applications")" = /Applications
codesign --verify --deep --strict "$TCL_DMG_MOUNT/TCLimate.app"
xcrun stapler validate "$TCL_DMG_MOUNT/TCLimate.app"
hdiutil detach "$TCL_DMG_MOUNT" >/dev/null
rmdir "$TCL_DMG_MOUNT"
trap - EXIT
codesign --force --timestamp --sign "$TCL_SIGNER" "$TCL_RELEASE_DIR/$TCL_DMG"
codesign --verify --strict "$TCL_RELEASE_DIR/$TCL_DMG"
xcrun notarytool submit "$TCL_RELEASE_DIR/$TCL_DMG" \
  --keychain-profile "$TCL_NOTARY_PROFILE" --wait --timeout 20m \
  --output-format json > "$TCL_RELEASE_DIR/dmg-notarization.json"
python3 - "$TCL_RELEASE_DIR/dmg-notarization.json" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
if result.get('status') != 'Accepted':
    raise SystemExit('DMG notarization was not accepted. Inspect the submission log before publishing.')
print('Apple DMG notarization accepted:', result['id'])
PY
xcrun stapler staple "$TCL_RELEASE_DIR/$TCL_DMG"
xcrun stapler validate "$TCL_RELEASE_DIR/$TCL_DMG"
codesign --verify --strict "$TCL_RELEASE_DIR/$TCL_DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$TCL_RELEASE_DIR/$TCL_DMG"
# Include the existing ZIP checksum without replacing the ZIP itself.
(cd "$TCL_RELEASE_DIR" && shasum -a 256 "$TCL_DMG" "TCLimate-v$TCL_VERSION-universal.zip" > SHA256SUMS)
echo "Notarized disk image: $TCL_RELEASE_DIR/$TCL_DMG"
