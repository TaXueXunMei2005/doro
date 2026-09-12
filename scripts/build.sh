#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Doro.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ROOT/build/module-cache"
xcrun swiftc "$ROOT/source/main.swift" -O -framework Cocoa \
  -module-cache-path "$ROOT/build/module-cache" -o "$APP/Contents/MacOS/Doro"
cp "$ROOT/resources/Info.plist" "$APP/Contents/Info.plist"
# Replace resources so removed frames cannot survive a rebuild.
if [ -d "$APP/Contents/Resources/Frames" ]; then
  rm -rf "$APP/Contents/Resources/Frames"
fi
cp -R "$ROOT/resources/Frames" "$APP/Contents/Resources/Frames"
codesign --force --deep --sign - "$APP"
"$APP/Contents/MacOS/Doro" --self-test
printf 'Built: %s\n' "$APP"
