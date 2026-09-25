#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE="$ROOT/src/LISSTech.Billboard.Mac"
OUTPUT="$ROOT/Release/macOS"
APP="$OUTPUT/LISSTech Billboard.app"
APP_BINARY="LISSTechBillboardMac"
HELPER_BINARY="lisstech-billboard-rmm"

require_macos() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "build-macos.sh must run on macOS." >&2
    exit 1
  fi
}

build_architecture() {
  local architecture="$1"
  swift build \
    --package-path "$PACKAGE" \
    --configuration release \
    --arch "$architecture" \
    --product "$APP_BINARY"
  swift build \
    --package-path "$PACKAGE" \
    --configuration release \
    --arch "$architecture" \
    --product "$HELPER_BINARY"
}

binary_path() {
  swift build \
    --package-path "$PACKAGE" \
    --configuration release \
    --arch "$1" \
    --show-bin-path
}

require_macos
rm -rf "$OUTPUT"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$OUTPUT/usr/local/bin"

build_architecture arm64
build_architecture x86_64
ARM64_BIN="$(binary_path arm64)"
X86_64_BIN="$(binary_path x86_64)"

lipo -create \
  "$ARM64_BIN/$APP_BINARY" \
  "$X86_64_BIN/$APP_BINARY" \
  -output "$APP/Contents/MacOS/$APP_BINARY"
lipo -create \
  "$ARM64_BIN/$HELPER_BINARY" \
  "$X86_64_BIN/$HELPER_BINARY" \
  -output "$OUTPUT/usr/local/bin/$HELPER_BINARY"

cp "$PACKAGE/Resources/Info.plist" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION:-1.0.0}" \
  "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER:-1}" \
  "$APP/Contents/Info.plist"
chmod 0755 "$APP/Contents/MacOS/$APP_BINARY" "$OUTPUT/usr/local/bin/$HELPER_BINARY"

if [[ -n "${MACOS_APP_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp \
    --sign "$MACOS_APP_IDENTITY" "$OUTPUT/usr/local/bin/$HELPER_BINARY"
  codesign --force --options runtime --timestamp \
    --sign "$MACOS_APP_IDENTITY" "$APP"
else
  codesign --force --sign - "$OUTPUT/usr/local/bin/$HELPER_BINARY"
  codesign --force --sign - "$APP"
fi

codesign --verify --strict --verbose=2 "$APP"
codesign --verify --strict --verbose=2 "$OUTPUT/usr/local/bin/$HELPER_BINARY"
lipo -archs "$APP/Contents/MacOS/$APP_BINARY"
lipo -archs "$OUTPUT/usr/local/bin/$HELPER_BINARY"
printf 'Built %s\n' "$OUTPUT"
