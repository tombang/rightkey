#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INSTALLER="$ROOT_DIR/scripts/install_rightkey.command"
source "$ROOT_DIR/scripts/package_release.zsh"
[[ -x "$INSTALLER" ]]

WORK="$(mktemp -d "${TMPDIR:-/tmp}/rightkey-installer-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

make_app() {
  local app_path="$1" version="$2" build="$3" bundle_id="${4:-com.rightkey.app}"
  mkdir -p "$app_path/Contents"
  /usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string '"$bundle_id" "$app_path/Contents/Info.plist" >/dev/null
  /usr/libexec/PlistBuddy -c 'Add :CFBundleShortVersionString string '"$version" "$app_path/Contents/Info.plist" >/dev/null
  /usr/libexec/PlistBuddy -c 'Add :CFBundleVersion string '"$build" "$app_path/Contents/Info.plist" >/dev/null
}

run_install() {
  local source_dir="$1" dest_root="$2" home_dir="$3"
  RIGHTKEY_INSTALL_ASSUME_YES=1 \
  RIGHTKEY_INSTALL_SKIP_SYSTEM=1 \
  RIGHTKEY_INSTALL_ROOT="$dest_root" \
  RIGHTKEY_INSTALL_HOME="$home_dir" \
    /bin/zsh "$source_dir/安装 RightKey.command"
}

SOURCE="$WORK/source"
DEST="$WORK/Applications"
HOME_DIR="$WORK/home"
mkdir -p "$SOURCE" "$DEST" "$HOME_DIR/Library/Application Support/RightKey" "$HOME_DIR/Applications"
printf 'keep-me\n' > "$HOME_DIR/Library/Application Support/RightKey/Templates.json"
cp "$INSTALLER" "$SOURCE/安装 RightKey.command"
chmod 755 "$SOURCE/安装 RightKey.command"
make_app "$SOURCE/RightKey.app" "1.5.0" "8"
make_app "$DEST/RightKey.app" "9.0.0" "99"
make_app "$HOME_DIR/Applications/RightKey.app" "9.0.0" "99"
make_app "$DEST/NotRightKey.app" "9.0.0" "99" "com.example.other"
xattr -w com.apple.quarantine "0081;00000000;Test;00000000-0000-0000-0000-000000000000" "$SOURCE/RightKey.app/Contents/Info.plist"

run_install "$SOURCE" "$DEST" "$HOME_DIR"

installed_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$DEST/RightKey.app/Contents/Info.plist")"
[[ "$installed_build" == 8 ]]
[[ ! -d "$HOME_DIR/Applications/RightKey.app" ]]
[[ -d "$SOURCE/RightKey.app" ]]
[[ -d "$DEST/NotRightKey.app" ]]
[[ "$(cat "$HOME_DIR/Library/Application Support/RightKey/Templates.json")" == "keep-me" ]]
[[ -z "$(xattr -p com.apple.quarantine "$DEST/RightKey.app/Contents/Info.plist" 2>/dev/null || true)" ]]

blocked="$WORK/blocked"
mkdir -p "$blocked/Applications"
make_app "$blocked/Applications/RightKey.app" "1.0.0" "1" "com.example.blocker"
if RIGHTKEY_INSTALL_ASSUME_YES=1 RIGHTKEY_INSTALL_SKIP_SYSTEM=1 \
  RIGHTKEY_INSTALL_ROOT="$blocked/Applications" RIGHTKEY_INSTALL_HOME="$WORK/empty-home" \
  /bin/zsh "$SOURCE/安装 RightKey.command"; then
  echo "installer replaced an unrelated app" >&2
  exit 1
fi
[[ -d "$blocked/Applications/RightKey.app" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$blocked/Applications/RightKey.app/Contents/Info.plist")" == "com.example.blocker" ]]

package_dir="$WORK/dist"
make_app "$WORK/package-app/RightKey.app" "1.5.0" "8"
zip_path="$(package_rightkey_release "$WORK/package-app/RightKey.app" "$package_dir" "1.5.0" "$INSTALLER")"
extracted="$WORK/extracted"
mkdir -p "$extracted"
ditto -x -k "$zip_path" "$extracted"
[[ -d "$extracted/RightKey-1.5.0/RightKey.app" ]]
[[ -x "$extracted/RightKey-1.5.0/安装 RightKey.command" ]]
(cd "$package_dir" && shasum -a 256 -c "RightKey-1.5.0.zip.sha256" >/dev/null)

echo "installer tests passed"
