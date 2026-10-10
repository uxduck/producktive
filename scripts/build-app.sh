#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/release-config.sh
configuration="${CONFIGURATION:-release}"
swift build -c "$configuration" --arch arm64 --arch x86_64
binary_dir="$(swift build -c "$configuration" --arch arm64 --arch x86_64 --show-bin-path)"
app="$DIST_DIR/Producktive.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/bin" "$app/Contents/Resources/skills" "$app/Contents/Resources/examples"
# Dependency licenses may have been copied read-only by a previous build.
chmod -R u+w "$app"
mkdir -p "$app/Contents/Frameworks"
framework=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
# ditto preserves Sparkle's framework symlinks and helper executables.
rm -rf "$app/Contents/Frameworks/Sparkle.framework"
ditto "$framework" "$app/Contents/Frameworks/Sparkle.framework"
cp "$binary_dir/Producktive" "$app/Contents/MacOS/Producktive"
cp "$binary_dir/producktive-cli" "$app/Contents/Resources/bin/producktive-cli"
cp -R skills/producktive "$app/Contents/Resources/skills/"
cp examples/* "$app/Contents/Resources/examples/"
cp LICENSE "$app/Contents/Resources/LICENSE"
cp .build/checkouts/Yams/LICENSE "$app/Contents/Resources/Yams-LICENSE"
cp .build/artifacts/sparkle/Sparkle/LICENSE "$app/Contents/Resources/Sparkle-LICENSE"
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
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><false/>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>Copyright © 2026 DuckType Limited</string>
</dict></plist>
PLIST
# Local ad hoc builds and CI stay offline. Developer ID builds enable updates.
if [[ -n "${SIGNING_IDENTITY:-}" && "$SIGNING_IDENTITY" != "-" ]]; then
  export ENABLE_UPDATES="${ENABLE_UPDATES:-1}"
else
  export ENABLE_UPDATES="${ENABLE_UPDATES:-0}"
fi
python3 - "$app/Contents/Info.plist" <<'PY'
import base64, os, plistlib, re, sys
from urllib.parse import urlparse
path = sys.argv[1]
with open(path, 'rb') as stream:
    info = plistlib.load(stream)
version, build = os.environ['RELEASE_VERSION'], os.environ['BUILD_NUMBER']
if not re.fullmatch(r'\d+\.\d+\.\d+', version) or not re.fullmatch(r'[1-9]\d*', build):
    sys.exit('RELEASE_VERSION must be x.y.z and BUILD_NUMBER a positive integer')
info.update(CFBundleShortVersionString=version, CFBundleVersion=build)
if os.environ['ENABLE_UPDATES'] == '1':
    base = os.environ['UPDATE_BASE_URL'].rstrip('/')
    url = urlparse(base)
    if url.scheme != 'https' or not url.netloc or url.query or url.fragment:
        sys.exit('UPDATE_BASE_URL must be an HTTPS URL without a query or fragment')
    key = os.environ['SPARKLE_PUBLIC_ED_KEY']
    if len(base64.b64decode(key, validate=True)) != 32:
        sys.exit('SPARKLE_PUBLIC_ED_KEY must encode a 32-byte Ed25519 public key')
    info.update(SUFeedURL=base + '/appcast.xml', SUPublicEDKey=key,
                SUEnableAutomaticChecks=True, SUAutomaticallyUpdate=True,
                SUScheduledCheckInterval=86400, SUEnableSystemProfiling=False,
                SUVerifyUpdateBeforeExtraction=True, SURequireSignedFeed=True)
with open(path, 'wb') as stream:
    plistlib.dump(info, stream)
PY
chmod -R a+rX "$app"
scripts/sign-app.sh "$app"
printf 'Built %s\n' "$app"
