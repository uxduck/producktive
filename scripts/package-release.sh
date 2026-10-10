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
archive="dist/Producktive-0.2.1-universal.zip"
ditto -c -k --keepParent "$app" "$archive"
notary_arguments=()
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  notary_arguments=(--keychain-profile "$NOTARY_PROFILE")
elif [[ -n "${APPLE_API_KEY_PATH:-}${APPLE_API_KEY:-}${APPLE_API_ISSUER:-}" ]]; then
  : "${APPLE_API_KEY_PATH:?Set all three Apple API variables}"
  : "${APPLE_API_KEY:?Set all three Apple API variables}"
  : "${APPLE_API_ISSUER:?Set all three Apple API variables}"
  notary_arguments=(--key "$APPLE_API_KEY_PATH" --key-id "$APPLE_API_KEY" --issuer "$APPLE_API_ISSUER")
fi
if [[ ${#notary_arguments[@]} -gt 0 ]]; then
  : "${SIGNING_IDENTITY:?Notarization requires a Developer ID signing identity}"
  if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    printf 'Notarization requires a Developer ID signing identity.\n' >&2
    exit 1
  fi
  result_file="$(mktemp -t producktive-notarization)"
  trap 'rm -f "$result_file"' EXIT
  xcrun notarytool submit "$archive" "${notary_arguments[@]}" --wait --output-format json > "$result_file"
  cat "$result_file"
  python3 -c 'import json,sys; result=json.load(open(sys.argv[1])); sys.exit(0 if result.get("status")=="Accepted" else "Notarization was not accepted")' "$result_file"
  xcrun stapler staple "$app"
  xcrun stapler validate "$app"
  spctl --assess --type execute --verbose=2 "$PWD/$app"
  ditto -c -k --keepParent "$app" "$archive"
fi
(cd dist && shasum -a 256 "$(basename "$archive")") > "$archive.sha256"
printf 'Packaged %s\n' "$archive"
