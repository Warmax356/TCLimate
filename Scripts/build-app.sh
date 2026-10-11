#!/bin/zsh
set -eu
set -o pipefail
cd "$(dirname "$0")/.."
TCL_MODE="${1:-local}"
case "$TCL_MODE" in
  local)
    TCL_SIGNER="${TCL_CODESIGN_IDENTITY:-}"
    TCL_IDENTITY_FILE=".codesign-identity"
    TCL_APP="$PWD/dist/TCLimate.app"
    ;;
  release)
    TCL_SIGNER="${TCL_RELEASE_CODESIGN_IDENTITY:-}"
    TCL_IDENTITY_FILE=".release-codesign-identity"
    TCL_APP="$PWD/dist/release/TCLimate.app"
    ;;
  *) echo "Usage: $0 [local|release]"; exit 1 ;;
esac
if [[ -z "$TCL_SIGNER" && -f "$TCL_IDENTITY_FILE" ]]; then
  TCL_SIGNER="$(cat "$TCL_IDENTITY_FILE")"
fi
if [[ -z "$TCL_SIGNER" || "$TCL_SIGNER" == "-" ]]; then
  echo "Set the signing identity or save it in $TCL_IDENTITY_FILE."
  echo "Release builds require a Developer ID Application certificate."
  exit 1
fi
mkdir -p "$TCL_APP/Contents/MacOS" "$TCL_APP/Contents/Resources"
if [[ "$TCL_MODE" == "release" ]]; then
  for TCL_ARCH in arm64 x86_64; do
    swift build -c release --product TCLimate --triple "$TCL_ARCH-apple-macosx14.0" --scratch-path ".build/distribution-$TCL_ARCH"
  done
  TCL_ARM_BIN="$(swift build -c release --triple arm64-apple-macosx14.0 --scratch-path .build/distribution-arm64 --show-bin-path)"
  TCL_INTEL_BIN="$(swift build -c release --triple x86_64-apple-macosx14.0 --scratch-path .build/distribution-x86_64 --show-bin-path)"
  xcrun lipo -create "$TCL_ARM_BIN/TCLimate" "$TCL_INTEL_BIN/TCLimate" -output "$TCL_APP/Contents/MacOS/TCLimate"
  TCL_ARCHS="$(xcrun lipo -archs "$TCL_APP/Contents/MacOS/TCLimate")"
  if [[ "$TCL_ARCHS" != *arm64* || "$TCL_ARCHS" != *x86_64* ]]; then
    echo "Release executable must contain both arm64 and x86_64."
    exit 1
  fi
else
  swift build -c release --product TCLimate
  TCL_BIN_DIR="$(swift build -c release --show-bin-path)"
  cp "$TCL_BIN_DIR/TCLimate" "$TCL_APP/Contents/MacOS/TCLimate"
fi
cp Scripts/Info.plist "$TCL_APP/Contents/Info.plist"
cp THIRD_PARTY_NOTICES.md LICENSE "$TCL_APP/Contents/Resources/"
swift Scripts/make-icon.swift "$PWD/dist/AppIcon.iconset"
iconutil -c icns "$PWD/dist/AppIcon.iconset" -o "$TCL_APP/Contents/Resources/AppIcon.icns"
if [[ "$TCL_MODE" == "release" ]]; then
  codesign --force --options runtime --timestamp --sign "$TCL_SIGNER" --identifier io.loopbreak.TCLimate "$TCL_APP"
  TCL_SIGNATURE="$(codesign -d --verbose=4 "$TCL_APP" 2>&1)"
  if [[ "$TCL_SIGNATURE" != *"Authority=Developer ID Application:"* ]]; then
    echo "Release signing requires a Developer ID Application certificate."
    exit 1
  fi
else
  codesign --force --sign "$TCL_SIGNER" --identifier io.loopbreak.TCLimate "$TCL_APP"
fi
codesign --verify --deep --strict "$TCL_APP"
echo "Built $TCL_APP"
