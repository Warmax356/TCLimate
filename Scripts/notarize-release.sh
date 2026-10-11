#!/bin/zsh
set -eu
set -o pipefail
cd "$(dirname "$0")/.."
: "${TCL_NOTARY_PROFILE:?Set TCL_NOTARY_PROFILE to a saved notarytool Keychain profile.}"
TCL_APP="$PWD/dist/release/TCLimate.app"
TCL_VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Scripts/Info.plist)"
TCL_RELEASE_DIR="$PWD/dist/releases/v$TCL_VERSION"
TCL_ARCHIVE="TCLimate-v$TCL_VERSION-universal.zip"
mkdir -p "$TCL_RELEASE_DIR"
codesign --verify --deep --strict "$TCL_APP"
TCL_SIGNATURE="$(codesign -d --verbose=4 "$TCL_APP" 2>&1)"
  if [[ "$TCL_SIGNATURE" != *"Authority=Developer ID Application:"* ]]; then
  echo "Build with ./Scripts/build-app.sh release first."
  exit 1
fi
TCL_ARCHS="$(xcrun lipo -archs "$TCL_APP/Contents/MacOS/TCLimate")"
  if [[ "$TCL_ARCHS" != *arm64* || "$TCL_ARCHS" != *x86_64* ]]; then
    echo "Release executable must contain both arm64 and x86_64."
    exit 1
  fi
# Notary service scans this archive. Distribute a fresh ZIP only after stapling.
ditto -c -k --keepParent "$TCL_APP" "$TCL_RELEASE_DIR/submission.zip"
xcrun notarytool submit "$TCL_RELEASE_DIR/submission.zip" \
  --keychain-profile "$TCL_NOTARY_PROFILE" --wait --timeout 20m \
  --output-format json > "$TCL_RELEASE_DIR/notarization.json"
python3 - "$TCL_RELEASE_DIR/notarization.json" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
if result.get('status') != 'Accepted':
    raise SystemExit('Notarization was not accepted. Inspect the submission log before releasing.')
print('Apple notarization accepted:', result['id'])
PY
xcrun stapler staple "$TCL_APP"
xcrun stapler validate "$TCL_APP"
codesign --verify --deep --strict "$TCL_APP"
spctl --assess --type execute --verbose=2 "$TCL_APP"
ditto -c -k --keepParent "$TCL_APP" "$TCL_RELEASE_DIR/$TCL_ARCHIVE"
(cd "$TCL_RELEASE_DIR" && shasum -a 256 "$TCL_ARCHIVE" > SHA256SUMS)
echo "Notarized release: $TCL_RELEASE_DIR/$TCL_ARCHIVE"
