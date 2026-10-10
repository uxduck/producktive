#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/release-config.sh
plist="$DIST_DIR/Producktive.app/Contents/Info.plist"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")"
feed="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$plist")"
archive="$DIST_DIR/Producktive-$version-universal.zip"
updates="$DIST_DIR/updates"
mkdir -p "$updates"
# A single universal archive handles both architectures. No deltas initially.
# Include the build in the immutable URL so an intentional rebuild is distinct.
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")"
cp "$archive" "$updates/Producktive-$version-$build-universal.zip"
if [[ -n "${RELEASE_NOTES_FILE:-}" ]]; then
  cp "$RELEASE_NOTES_FILE" "$updates/Producktive-$version-$build-universal.md"
fi
arguments=(--account "$SPARKLE_KEY_ACCOUNT" --maximum-deltas 0 --versions "$build"
  --download-url-prefix "${feed%/appcast.xml}/" --release-notes-url-prefix "${feed%/appcast.xml}/")
if [[ -n "${SPARKLE_PRIVATE_KEY_FILE:-}" ]]; then
  arguments+=(--ed-key-file "$SPARKLE_PRIVATE_KEY_FILE")
fi
.build/artifacts/sparkle/Sparkle/bin/generate_appcast "${arguments[@]}" -o "$updates/appcast.xml" "$updates"
python3 scripts/validate-appcast.py "$plist" "$updates"
printf 'Generated %s/appcast.xml\n' "$updates"
