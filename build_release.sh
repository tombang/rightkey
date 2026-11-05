#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
DERIVED_DATA="$ROOT_DIR/.build/DerivedData"
DIST_DIR="$ROOT_DIR/dist"

(cd "$ROOT_DIR" && shasum -a 256 -c RightKey/Resources/ThirdParty/SHA256SUMS)

rm -rf "$DERIVED_DATA"
mkdir -p "$DIST_DIR"

xcodebuild \
  -project "$ROOT_DIR/RightKey.xcodeproj" \
  -scheme RightKey \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  build

APP_PATH="$DERIVED_DATA/Build/Products/Release/RightKey.app"
test -d "$APP_PATH"
for binary in "$APP_PATH/Contents/MacOS/RightKey" \
  "$APP_PATH/Contents/PlugIns/RightKeyFinderSync.appex/Contents/MacOS/RightKeyFinderSync" \
  "$APP_PATH/Contents/Resources/7zz" "$APP_PATH/Contents/Resources/zstd"; do
  lipo "$binary" -verify_arch arm64 x86_64
  codesign --verify --strict "$binary"
done
codesign --verify --deep --strict "$APP_PATH"

ENTITLEMENTS="$DIST_DIR/extension-entitlements.plist"
codesign -d --entitlements - --xml "$APP_PATH/Contents/PlugIns/RightKeyFinderSync.appex" > "$ENTITLEMENTS" 2>/dev/null
test "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$ENTITLEMENTS")" = true

APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
ZIP_PATH="$DIST_DIR/RightKey-$APP_VERSION.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
(
  cd "$DIST_DIR"
  shasum -a 256 "$(basename "$ZIP_PATH")" > "$(basename "$ZIP_PATH").sha256"
)

echo "Created $ZIP_PATH"
echo "Created $ZIP_PATH.sha256"
