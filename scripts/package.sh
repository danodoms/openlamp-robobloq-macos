#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

swift build -c release --product OpenLamp
BIN=$(swift build -c release --show-bin-path)
APP="build/OpenLamp.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/OpenLamp" "$APP/Contents/MacOS/OpenLamp"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$APP"
echo "Built and ad-hoc signed $APP"

if [[ "${1:-}" == "--install" ]]; then
    rm -rf /Applications/OpenLamp.app
    ditto "$APP" /Applications/OpenLamp.app
    echo "Installed /Applications/OpenLamp.app"
    open /Applications/OpenLamp.app
fi
