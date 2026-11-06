#!/bin/zsh
# Builds DNS Doctor.app and a drag-to-install DMG into ./dist
# Usage: scripts/build.sh [version]
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-1.0.0}"
APP_NAME="DNS Doctor"
DIST="dist"
APP="$DIST/$APP_NAME.app"
DMG="$DIST/DNS-Doctor-$VERSION.dmg"

rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> Compiling (universal: arm64 + x86_64)"
swift build -c release --triple arm64-apple-macosx13.0
swift build -c release --triple x86_64-apple-macosx13.0
BIN="$DIST/DNSDoctor"
lipo -create -output "$BIN" \
  .build/arm64-apple-macosx/release/DNSDoctor \
  .build/x86_64-apple-macosx/release/DNSDoctor
mv "$BIN" "$APP/Contents/MacOS/DNSDoctor"
sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"

echo "==> Generating icon"
ICONSET="$DIST/AppIcon.iconset"
swift scripts/make_icon.swift "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

echo "==> Signing (ad-hoc)"
codesign --force --deep --sign - "$APP"

echo "==> Creating DMG"
STAGE="$DIST/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
# Unversioned copy so releases/latest/download/DNS-Doctor.dmg always works
cp "$DMG" "$DIST/DNS-Doctor.dmg"

echo "==> Done"
echo "    $APP"
echo "    $DMG"
