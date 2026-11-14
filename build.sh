#!/bin/bash
# Builds build/CleanDisk.app. Pass --run to launch it afterwards.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP=build/CleanDisk.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/CleanDisk "$APP/Contents/MacOS/CleanDisk"
cp Support/Info.plist "$APP/Contents/Info.plist"

# App icon (generated once, cached in build/)
if [ ! -f build/AppIcon.icns ]; then
    swift scripts/make_icon.swift build/icon_1024.png
    ICONSET=build/AppIcon.iconset
    rm -rf "$ICONSET" && mkdir -p "$ICONSET"
    for s in 16 32 128 256 512; do
        sips -z $s $s build/icon_1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
        sips -z $((s * 2)) $((s * 2)) build/icon_1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$APP" 2>/dev/null
echo "Built $APP"

if [ "${1:-}" = "--run" ]; then open "$APP"; fi
