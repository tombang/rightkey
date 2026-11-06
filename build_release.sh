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
test "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.temporary-exception.files.home-relative-path.read-only:0' "$ENTITLEMENTS")" = "/Library/Application Support/RightKey/DirectoryMarks.json"

APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
source "$ROOT_DIR/scripts/package_release.zsh"
ZIP_PATH="$(package_rightkey_release "$APP_PATH" "$DIST_DIR" "$APP_VERSION" "$ROOT_DIR/scripts/install_rightkey.command")"

echo "Created $ZIP_PATH"
echo "Created $ZIP_PATH.sha256"
