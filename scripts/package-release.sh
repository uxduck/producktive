#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/build-app.sh
app="dist/Producktive.app"
# Developer ID releases require a secure timestamp.
if [[ -n "${SIGNING_IDENTITY:-}" && "$SIGNING_IDENTITY" != "-" ]]; then
  codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$app/Contents/Resources/bin/producktive-cli"
  codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$app"
fi
archive="dist/Producktive-0.1.0-universal.zip"
ditto -c -k --keepParent "$app" "$archive"
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$archive" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$app"
  xcrun stapler validate "$app"
  ditto -c -k --keepParent "$app" "$archive"
fi
(cd dist && shasum -a 256 "$(basename "$archive")") > "$archive.sha256"
printf 'Packaged %s\n' "$archive"
