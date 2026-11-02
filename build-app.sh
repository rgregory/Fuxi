#!/bin/bash
# Builds Fuxi.app into ./build and signs it ad hoc for local use.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/Fuxi.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/Fuxi" "$APP/Contents/MacOS/Fuxi"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"

echo "Built $PWD/$APP"
echo "Run:   open \"$APP\""
echo "Install: cp -R \"$APP\" /Applications/"
