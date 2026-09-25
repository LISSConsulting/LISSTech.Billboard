#!/bin/bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "notarize-macos.sh must run on macOS." >&2
  exit 1
fi
if [[ $# -ne 1 || ! -f "$1" ]]; then
  echo "Usage: scripts/notarize-macos.sh <signed-installer.pkg>" >&2
  exit 1
fi

PACKAGE="$1"
if [[ -n "${MACOS_NOTARY_PROFILE:-}" ]]; then
  NOTARY_KEYCHAIN_ARGS=()
  if [[ -n "${MACOS_KEYCHAIN:-}" ]]; then
    NOTARY_KEYCHAIN_ARGS+=(--keychain "$MACOS_KEYCHAIN")
  fi
  xcrun notarytool submit "$PACKAGE" \
    --keychain-profile "$MACOS_NOTARY_PROFILE" \
    "${NOTARY_KEYCHAIN_ARGS[@]}" \
    --wait
else
  : "${APPLE_ID:?Set APPLE_ID or MACOS_NOTARY_PROFILE}"
  : "${APPLE_TEAM_ID:?Set APPLE_TEAM_ID or MACOS_NOTARY_PROFILE}"
  : "${APPLE_APP_PASSWORD:?Set APPLE_APP_PASSWORD or MACOS_NOTARY_PROFILE}"
  xcrun notarytool submit "$PACKAGE" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_PASSWORD" \
    --wait
fi

xcrun stapler staple "$PACKAGE"
xcrun stapler validate "$PACKAGE"
spctl --assess --type install --verbose=2 "$PACKAGE"
printf 'Notarized %s\n' "$PACKAGE"
