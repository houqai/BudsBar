#!/bin/zsh
# Regenerates Resources/AppIcon.icns from the artwork in Sources/Preview.swift.
set -euo pipefail
cd "${0:A:h}/.."

./build.sh
tmp=$(mktemp -d)
build/BudsBar.app/Contents/MacOS/BudsBar --render-icon "$tmp/icon.png"
mkdir "$tmp/AppIcon.iconset"
for size in 16 32 128 256 512; do
  sips -z $size $size "$tmp/icon.png" --out "$tmp/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) "$tmp/icon.png" --out "$tmp/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$tmp/AppIcon.iconset" -o Resources/AppIcon.icns
echo "Wrote Resources/AppIcon.icns"
