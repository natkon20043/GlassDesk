#!/bin/zsh
# Builds a universal (Apple silicon + Intel) GlassDesk.app for distribution and zips it
# into dist/. The release is ad-hoc signed: it isn't notarized by Apple, so the first
# launch needs right-click → Open (see README).
set -euo pipefail
cd "${0:A:h}"

VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)}"

xcrun swift build -c release --arch arm64 --arch x86_64

APP="dist/GlassDesk.app"
rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
BIN="$(xcrun swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
cp "$BIN/GlassDesk" "$APP/Contents/MacOS/GlassDesk"
cp Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

ditto -c -k --keepParent "$APP" "dist/GlassDesk-$VERSION.zip"
lipo -info "$APP/Contents/MacOS/GlassDesk"
echo "Built dist/GlassDesk-$VERSION.zip"
