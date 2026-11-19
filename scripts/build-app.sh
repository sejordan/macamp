#!/bin/bash
# Builds build/macamp.app: a release binary, Info.plist and icon, signed ad hoc for local use.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
bin=".build/release/macamp"
app="build/macamp.app"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/macamp"
strip -x "$app/Contents/MacOS/macamp"
cp scripts/Info.plist "$app/Contents/Info.plist"

# The icon is drawn by macamp itself, from a skin file.
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
iconset="$work/AppIcon.iconset"
mkdir -p "$iconset"
"$bin" --render-skin scripts/icon-skin.json --scale 4 --out "$work/icon-1024.png" >/dev/null
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$work/icon-1024.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$work/icon-1024.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$app" 2>/dev/null
echo "Built $app ($(du -sh "$app" | cut -f1))"
