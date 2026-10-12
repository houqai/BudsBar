#!/bin/zsh
# Builds BudsBar.app.
#   ./build.sh            build for this Mac into build/
#   ./build.sh --install  build, copy to ~/Applications and launch
#   ./build.sh --release  universal (Apple silicon + Intel) build, zipped into dist/
set -euo pipefail
cd "${0:A:h}"

MODE="${1:-}"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
APP=build/BudsBar.app

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

archs=($(uname -m))
[[ "$MODE" == "--release" ]] && archs=(arm64 x86_64)
for arch in $archs; do
  swiftc -O -swift-version 5 -parse-as-library -target "$arch-apple-macos13.0" \
    Sources/*.swift -o "build/BudsBar-$arch"
done
lipo -create build/BudsBar-* -output "$APP/Contents/MacOS/BudsBar"
rm -f build/BudsBar-*
codesign --force --sign - "$APP"

case "$MODE" in
  --install)
    mkdir -p ~/Applications
    pkill -x BudsBar 2>/dev/null || true
    rm -rf ~/Applications/BudsBar.app
    cp -R "$APP" ~/Applications/
    open ~/Applications/BudsBar.app
    echo "Installed to ~/Applications/BudsBar.app"
    ;;
  --release)
    mkdir -p dist
    ditto -c -k --keepParent "$APP" "dist/BudsBar-$VERSION.zip"
    echo "Built dist/BudsBar-$VERSION.zip"
    ;;
esac
