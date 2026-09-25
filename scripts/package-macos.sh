#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT="$ROOT/Release/macOS"
APP="$OUTPUT/LISSTech Billboard.app"
HELPER="$OUTPUT/usr/local/bin/lisstech-billboard-rmm"
VERSION="${1:-1.0.0}"
PKGROOT="$OUTPUT/pkgroot"
UNSIGNED="$OUTPUT/LISSTech-Billboard-$VERSION-unsigned.pkg"
FINAL="$OUTPUT/LISSTech-Billboard-$VERSION.pkg"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "package-macos.sh must run on macOS." >&2
  exit 1
fi
if [[ ! -d "$APP" || ! -x "$HELPER" ]]; then
  echo "Build output is missing; run scripts/build-macos.sh first." >&2
  exit 1
fi

APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$APP/Contents/Info.plist")"
if [[ "$APP_VERSION" != "$VERSION" ]]; then
  echo "Built app version is $APP_VERSION, not $VERSION; rebuild with VERSION=$VERSION." >&2
  exit 1
fi

rm -rf "$PKGROOT" "$UNSIGNED" "$FINAL"
mkdir -p "$PKGROOT/Applications" "$PKGROOT/usr/local/bin"
ditto "$APP" "$PKGROOT/Applications/LISSTech Billboard.app"
install -m 0755 "$HELPER" "$PKGROOT/usr/local/bin/lisstech-billboard-rmm"

pkgbuild \
  --root "$PKGROOT" \
  --identifier com.lisstech.billboard.pkg \
  --version "$VERSION" \
  --install-location / \
  "$UNSIGNED"

if [[ -n "${MACOS_INSTALLER_IDENTITY:-}" ]]; then
  productsign --sign "$MACOS_INSTALLER_IDENTITY" "$UNSIGNED" "$FINAL"
  rm "$UNSIGNED"
else
  mv "$UNSIGNED" "$FINAL"
fi

pkgutil --check-signature "$FINAL" || {
  if [[ -n "${MACOS_INSTALLER_IDENTITY:-}" ]]; then
    exit 1
  fi
  echo "Installer is unsigned; set MACOS_INSTALLER_IDENTITY for distribution." >&2
}
printf 'Packaged %s\n' "$FINAL"
