#!/bin/bash
# Builds build/macamp.app: a release binary, Info.plist and icon.
#
#   scripts/build-app.sh              build for this Mac's processor, signed for local use
#   scripts/build-app.sh --universal  build for both Apple Silicon and Intel
#   scripts/build-app.sh --zip        also write build/macamp-<version>.zip, ready to share
#
# Set SIGN_IDENTITY to a "Developer ID Application: …" certificate name to sign for
# distribution. Without it the app is signed ad hoc, which is fine on the Mac that built it.
set -euo pipefail
cd "$(dirname "$0")/.."

universal=false
zip=false
for arg in "$@"; do
  case "$arg" in
    --universal) universal=true ;;
    --zip) zip=true ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

# Keep this folder's path out of the binary.
flags=(-c release -Xswiftc -file-prefix-map -Xswiftc "$PWD=.")
if $universal; then
  # Each processor is built separately and the two are joined, because building both at
  # once goes through a different build system that cannot embed the skins in the binary.
  swift build "${flags[@]}" --triple arm64-apple-macosx14.0
  swift build "${flags[@]}" --triple x86_64-apple-macosx14.0
  mkdir -p .build/universal
  bin=".build/universal/macamp"
  lipo -create -output "$bin" .build/arm64-apple-macosx/release/macamp .build/x86_64-apple-macosx/release/macamp
else
  swift build "${flags[@]}"
  bin=".build/release/macamp"
fi
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
"$app/Contents/MacOS/macamp" --render-skin scripts/icon-skin.json --scale 4 --out "$work/icon-1024.png" >/dev/null
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$work/icon-1024.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$work/icon-1024.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"

if [ -n "${SIGN_IDENTITY:-}" ]; then
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$app"
else
  codesign --force --sign - "$app" 2>/dev/null
fi
echo "Built $app ($(du -sh "$app" | cut -f1), $(lipo -archs "$app/Contents/MacOS/macamp"))"

if $zip; then
  version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' scripts/Info.plist)"
  archive="build/macamp-$version.zip"
  rm -f "$archive"
  ditto -c -k --keepParent "$app" "$archive"
  echo "Wrote $archive ($(du -sh "$archive" | cut -f1))"
fi
