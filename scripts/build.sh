#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Doro.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ROOT/build/module-cache"
xcrun swiftc "$ROOT"/source/*.swift -O -framework Cocoa \
  -module-cache-path "$ROOT/build/module-cache" -o "$APP/Contents/MacOS/Doro"
cp "$ROOT/resources/Info.plist" "$APP/Contents/Info.plist"
# Replace bundled resources together so every build uses one artwork revision.
if [ -d "$APP/Contents/Resources/Frames" ]; then
  rm -rf "$APP/Contents/Resources/Frames"
fi
cp -R "$ROOT/resources/Frames" "$APP/Contents/Resources/Frames"
for asset in greetings.json artwork.json; do
  if [ -f "$ROOT/resources/$asset" ]; then cp "$ROOT/resources/$asset" "$APP/Contents/Resources/$asset"; fi
done
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
"$APP/Contents/MacOS/Doro" --self-test
"$APP/Contents/MacOS/Doro" --interaction-self-test
printf 'Built: %s\n' "$APP"
