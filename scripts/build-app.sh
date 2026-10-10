#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${CONFIGURATION:-release}"
swift build -c "$configuration" --arch arm64 --arch x86_64
binary_dir="$(swift build -c "$configuration" --arch arm64 --arch x86_64 --show-bin-path)"
app="dist/Producktive.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/bin" "$app/Contents/Resources/skills" "$app/Contents/Resources/examples"
# Dependency licenses may have been copied read-only by a previous build.
chmod -R u+w "$app"
cp "$binary_dir/Producktive" "$app/Contents/MacOS/Producktive"
cp "$binary_dir/producktive-cli" "$app/Contents/Resources/bin/producktive-cli"
cp -R skills/producktive "$app/Contents/Resources/skills/"
cp examples/* "$app/Contents/Resources/examples/"
cp LICENSE "$app/Contents/Resources/LICENSE"
cp .build/checkouts/Yams/LICENSE "$app/Contents/Resources/Yams-LICENSE"
# Generate every macOS icon size from the selected call-duck artwork.
icon_work_dir="$(mktemp -d "${TMPDIR:-/tmp}/producktive-icons.XXXXXX")"
trap 'rm -rf "$icon_work_dir"' EXIT
iconset="$icon_work_dir/AppIcon.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" images/AppIcon.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
  retina_size=$((size * 2))
  sips -z "$retina_size" "$retina_size" images/AppIcon.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.uxduck.producktive</string>
<key>CFBundleName</key><string>Producktive</string>
<key>CFBundleDisplayName</key><string>Producktive</string>
<key>CFBundleExecutable</key><string>Producktive</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2.0</string>
<key>CFBundleVersion</key><string>3</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>Copyright © 2026 DuckType Limited</string>
</dict></plist>
PLIST
chmod -R a+rX "$app"
identity="${SIGNING_IDENTITY:--}"
codesign --force --options runtime --timestamp=none --sign "$identity" "$app/Contents/Resources/bin/producktive-cli"
codesign --force --options runtime --timestamp=none --sign "$identity" "$app"
codesign --verify --deep --strict "$app"
printf 'Built %s\n' "$app"
