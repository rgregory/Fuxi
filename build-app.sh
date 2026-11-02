#!/bin/bash
# Builds Fuxi.app into ./build and signs it ad hoc for local use.
# Theme names package extra copies with that theme as their default:
#   ./build-app.sh steampunk os9 tron
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Fuxi"

package() { # theme, app name, bundle id suffix
    local theme="$1" name="$2" suffix="$3"
    local app="build/$name.app"
    rm -rf "$app"
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
    cp "$BIN" "$app/Contents/MacOS/Fuxi"
    cp Support/Info.plist "$app/Contents/Info.plist"
    cp Support/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
    if [ -n "$theme" ]; then
        local plist="$app/Contents/Info.plist"
        plutil -replace CFBundleIdentifier -string "com.rgregory.fuxi.$suffix" "$plist"
        plutil -replace CFBundleName -string "$name" "$plist"
        plutil -replace CFBundleDisplayName -string "$name" "$plist"
        plutil -insert FuxiTheme -string "$theme" "$plist"
    fi
    codesign --force --sign - "$app"
    echo "Built $PWD/$app"
}

package "" "Fuxi" ""
for t in "$@"; do
    case "$t" in
        steampunk)   package steampunk   "Fuxi Steampunk" steampunk ;;
        os9)         package os9         "Fuxi OS 9"      os9 ;;
        tron)        package tron        "Fuxi Tron"      tron ;;
        *) echo "Unknown theme: $t (use steampunk, os9 or tron)" >&2; exit 1 ;;
    esac
done

echo "Run:     open build/*.app"
echo "Install: cp -R build/Fuxi.app /Applications/"
