#!/bin/bash
set -euo pipefail
app="${1:?Usage: sign-app.sh /path/to/Producktive.app}"
identity="${SIGNING_IDENTITY:--}"
timestamp=(--timestamp)
if [[ "$identity" == "-" ]]; then timestamp=(--timestamp=none); fi
sign() { codesign --force --options runtime "${timestamp[@]}" --sign "$identity" "$1"; }
# Sign from the inside out. Library validation requires the framework and app
# to have the same team; --deep signing does not handle this reliably.
framework="$app/Contents/Frameworks/Sparkle.framework"
version="$framework/Versions/B"
sign "$version/XPCServices/Downloader.xpc"
sign "$version/XPCServices/Installer.xpc"
sign "$version/Autoupdate"
sign "$version/Updater.app"
sign "$framework"
sign "$app/Contents/Resources/bin/producktive-cli"
sign "$app"
codesign --verify --deep --strict "$app"
