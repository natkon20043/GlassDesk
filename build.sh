#!/bin/zsh
# Builds GlassDesk, installs it to ~/Applications and (re)launches it.
set -euo pipefail
cd "${0:A:h}"

xcrun swift build -c release

APP="$HOME/Applications/GlassDesk.app"
STAGE="$PWD/.build/GlassDesk.app"
rm -rf "$STAGE"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
cp .build/release/GlassDesk "$STAGE/Contents/MacOS/GlassDesk"
cp Resources/Info.plist "$STAGE/Contents/Info.plist"
# Sign with the Apple Development identity when there is one, so macOS privacy grants
# (Calendar access) survive rebuilds; fall back to ad-hoc signing otherwise.
IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')
codesign --force --sign "${IDENTITY:--}" "$STAGE" >/dev/null

pkill -x GlassDesk 2>/dev/null && sleep 1 || true
mkdir -p "$HOME/Applications"
rm -rf "$APP"
ditto "$STAGE" "$APP"
open "$APP"
echo "GlassDesk installed at $APP and launched."
