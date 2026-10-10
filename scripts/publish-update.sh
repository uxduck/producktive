#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/release-config.sh
export SPARKLE_KEY_ACCOUNT
dry_run=0
case "${1:-}" in
  --dry-run) dry_run=1 ;;
  '') ;;
  *) printf 'Usage: scripts/publish-update.sh [--dry-run]\n' >&2; exit 1 ;;
esac
app="$DIST_DIR/Producktive.app"
updates="$DIST_DIR/updates"
plist="$app/Contents/Info.plist"
feed="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$plist")"
if [[ "$feed" != "${UPDATE_BASE_URL%/}/appcast.xml" ]]; then
  printf 'Built feed URL differs from UPDATE_BASE_URL; rebuild first.\n' >&2
  exit 1
fi
files="$(python3 scripts/validate-appcast.py "$plist" "$updates" --files)"
verification_directory="$(mktemp -d -t producktive-publish)"
trap 'rm -rf "$verification_directory"' EXIT
if [[ "$dry_run" == 0 ]]; then
  # Fail before uploading anything if the app is not a notarised release.
  codesign --verify --deep --strict "$app"
  xcrun stapler validate "$app"
  spctl --assess --type execute --verbose=2 "$app"
  command -v rclone >/dev/null
  # Reject accidentally publishing an older or duplicate build.
  existing="$verification_directory/existing.xml"
  status="$(curl --silent --show-error --output "$existing" --write-out '%{http_code}' "$feed")"
  case "$status" in
    404) ;;
    200)
      python3 - "$plist" "$existing" <<'PY'
import plistlib, sys, xml.etree.ElementTree as ET
with open(sys.argv[1], 'rb') as stream:
    current = int(plistlib.load(stream)['CFBundleVersion'])
ns = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
old = ET.parse(sys.argv[2]).findall('./channel/item')
if any(int(item.findtext(ns + 'version') or item.find('enclosure').attrib[ns + 'version']) >= current for item in old):
    sys.exit('Increment BUILD_NUMBER before publishing; this build is already published or older.')
PY
      ;;
    *) printf 'Could not read current feed (HTTP %s); publishing stopped.\n' "$status" >&2; exit 1 ;;
  esac
fi
upload() {
  local file="$1" cache="$2"
  printf '%s → %s/%s (Cache-Control: %s)\n' "$file" "$R2_UPDATE_REMOTE" "$(basename "$file")" "$cache"
  if [[ "$dry_run" == 0 ]]; then
    local flags=(--ignore-times)
    if [[ "$cache" != "no-cache, max-age=0, must-revalidate" ]]; then flags=(--immutable --checksum); fi
    rclone copyto --s3-no-check-bucket "${flags[@]}" \
      --header-upload "Cache-Control: $cache" "$file" "$R2_UPDATE_REMOTE/$(basename "$file")"
    # Check the public endpoint before the feed can reference a missing payload.
    local downloaded="$verification_directory/$(basename "$file")"
    curl --fail --silent --show-error --location --retry 3 --retry-delay 2 \
      --header 'Cache-Control: no-cache' "${UPDATE_BASE_URL%/}/$(basename "$file")" --output "$downloaded"
    cmp "$file" "$downloaded"
  fi
}
# Publish all signed payloads before advancing the feed. Never delete old files.
while IFS= read -r name; do
  if [[ "$name" != "appcast.xml" ]]; then
    upload "$updates/$name" 'public, max-age=31536000, immutable'
  fi
done <<< "$files"
upload "$updates/appcast.xml" 'no-cache, max-age=0, must-revalidate'
