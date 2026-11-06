#!/bin/zsh
# Double-click installer: replace an existing RightKey and open the new one.
# Templates and directory marks under ~/Library/Application Support/RightKey are kept.
set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_APP="$SOURCE_DIR/RightKey.app"
DEST_ROOT="${RIGHTKEY_INSTALL_ROOT:-/Applications}"
SEARCH_HOME="${RIGHTKEY_INSTALL_HOME:-$HOME}"
ASSUME_YES="${RIGHTKEY_INSTALL_ASSUME_YES:-0}"
SKIP_SYSTEM="${RIGHTKEY_INSTALL_SKIP_SYSTEM:-0}"
BUNDLE_ID="com.rightkey.app"

dialog() {
  local message="$1" default_button="$2"
  if [[ "$ASSUME_YES" == 1 ]]; then
    printf '%s\n' "$default_button"
    return 0
  fi
  /usr/bin/osascript - "$message" "$default_button" <<'APPLESCRIPT'
on run argv
  set messageText to item 1 of argv
  set defaultButton to item 2 of argv
  try
    return button returned of (display dialog messageText buttons {"取消", defaultButton} default button defaultButton with title "安装 RightKey")
  on error
    return "取消"
  end try
end run
APPLESCRIPT
}

info() {
  printf '%s\n' "$1"
  [[ "$ASSUME_YES" == 1 ]] && return 0
  /usr/bin/osascript - "$1" <<'APPLESCRIPT' >/dev/null
on run argv
  display dialog (item 1 of argv) buttons {"好"} default button "好" with title "安装 RightKey"
end run
APPLESCRIPT
}

fail() {
  info "$1" >&2
  exit 1
}

canonical() {
  /usr/bin/python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$1"
}

bundle_id() {
  /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$1/Contents/Info.plist" 2>/dev/null || true
}

bundle_value() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist" 2>/dev/null || true
}

is_allowed_target() {
  local target="$1"
  [[ "$SKIP_SYSTEM" == 1 ]] || return 0
  local real dest_root search_home
  real="$(canonical "$target")"
  dest_root="$(canonical "$DEST_ROOT")"
  search_home="$(canonical "$SEARCH_HOME")"
  [[ "$real" == "$dest_root" || "$real" == "$dest_root"/* || "$real" == "$search_home" || "$real" == "$search_home"/* ]]
}

typeset -a OLD_APPS
typeset -A SEEN

add_old() {
  local app="$1" id real source_real source_dir_real
  [[ -d "$app" && "$app" == *.app ]] || return 0
  id="$(bundle_id "$app")"
  [[ "$id" == "$BUNDLE_ID" ]] || return 0
  is_allowed_target "$app" || return 0
  real="$(canonical "$app")"
  source_real="$(canonical "$SOURCE_APP")"
  source_dir_real="$(canonical "$SOURCE_DIR")"
  [[ "$real" == "$source_real" || "$real" == "$source_dir_real"/* ]] && return 0
  [[ "$real" == */.build/* || "$real" == */DerivedData/* ]] && return 0
  [[ -n "${SEEN[$real]:-}" ]] && return 0
  SEEN[$real]=1
  OLD_APPS+=("$app")
}

run_as_admin() {
  /usr/bin/python3 -c '
import subprocess, sys
command = sys.argv[1]
quoted = "\"" + command.replace("\\", "\\\\").replace("\"", "\\\"") + "\""
script = "do shell script " + quoted + " with administrator privileges"
raise SystemExit(subprocess.call(["/usr/bin/osascript", "-e", script]))
' "$1"
}

[[ -d "$SOURCE_APP" ]] || fail "没有找到旁边的 RightKey.app。请先解压完整压缩包，再双击「安装 RightKey」。"
[[ "$(bundle_id "$SOURCE_APP")" == "$BUNDLE_ID" ]] || fail "旁边的应用不是 RightKey，安装已停止。"

DEST_APP="$DEST_ROOT/RightKey.app"
if [[ -d "$DEST_APP" ]]; then
  dest_id="$(bundle_id "$DEST_APP")"
  if [[ -n "$dest_id" && "$dest_id" != "$BUNDLE_ID" ]]; then
    fail "目标文件夹里已有同名项目，但它不是 RightKey。安装已停止，没有删除任何文件。"
  fi
fi

add_old "$DEST_APP"
add_old "$SEARCH_HOME/Applications/RightKey.app"
add_old "$SEARCH_HOME/Desktop/RightKey.app"
add_old "$SEARCH_HOME/Downloads/RightKey.app"
add_old "$SEARCH_HOME/.Trash/RightKey.app"
if [[ "$SKIP_SYSTEM" != 1 ]]; then
  while IFS= read -r -d '' found; do
    add_old "$found"
  done < <(/usr/bin/mdfind -0 "kMDItemCFBundleIdentifier == '$BUNDLE_ID'" 2>/dev/null || true)
fi

NEW_VERSION="$(bundle_value "$SOURCE_APP" CFBundleShortVersionString)"
MESSAGE="将移除这台 Mac 上已安装的旧版 RightKey，并安装 ${NEW_VERSION:-新版本}。自定义模板和目录标记会保留。访达会自动重新打开一次。不需要输入命令。"
if (( ${#OLD_APPS} == 0 )); then
  MESSAGE="将安装 RightKey ${NEW_VERSION:-新版本}。自定义模板和目录标记会保留。访达会自动重新打开一次。不需要输入命令。"
fi
choice="$(dialog "$MESSAGE" "安装")"
[[ "$choice" == "安装" ]] || exit 0

if [[ "$SKIP_SYSTEM" != 1 ]]; then
  /usr/bin/osascript -e 'quit app "RightKey"' >/dev/null 2>&1 || true
  killall RightKey RightKeyFinderSync >/dev/null 2>&1 || true
  sleep 1
fi

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
for app in "${OLD_APPS[@]:-}"; do
  [[ -n "$app" && -d "$app" ]] || continue
  is_allowed_target "$app" || fail "为避免删错文件，安装已停止。"
  printf '正在移除 %s\n' "$app"
  if [[ "$SKIP_SYSTEM" != 1 ]]; then
    "$LSREGISTER" -u "$app" >/dev/null 2>&1 || true
    pluginkit -r "$app/Contents/PlugIns/RightKeyFinderSync.appex" >/dev/null 2>&1 || true
  fi
  if ! rm -rf "$app"; then
    [[ "$SKIP_SYSTEM" == 1 ]] && fail "无法移除旧版本。"
    info "移除旧版本需要系统授权。请在密码窗口中确认，不需要输入命令。"
    if ! run_as_admin "rm -rf $(/usr/bin/python3 -c 'import shlex, sys; print(shlex.quote(sys.argv[1]))' "$app")"; then
      fail "没有获得系统授权，安装已停止。请重新双击「安装 RightKey」。"
    fi
  fi
done

mkdir -p "$DEST_ROOT" 2>/dev/null || true
if [[ ! -d "$DEST_ROOT" || ! -w "$DEST_ROOT" ]]; then
  [[ "$SKIP_SYSTEM" == 1 ]] && fail "无法写入安装位置。"
  DEST_ROOT="$SEARCH_HOME/Applications"
  DEST_APP="$DEST_ROOT/RightKey.app"
  mkdir -p "$DEST_ROOT"
fi

SOURCE_REAL="$(canonical "$SOURCE_APP")"
if [[ ! -d "$DEST_APP" ]] || [[ "$(canonical "$DEST_APP")" != "$SOURCE_REAL" ]]; then
  printf '正在安装到 %s\n' "$DEST_APP"
  rm -rf "$DEST_APP" 2>/dev/null || true
  if [[ ! -e "$DEST_APP" ]] && ditto "$SOURCE_APP" "$DEST_APP"; then
    :
  else
    [[ "$SKIP_SYSTEM" == 1 ]] && fail "无法写入新版本。"
    info "安装新版本需要系统授权。请在密码窗口中确认，不需要输入命令。"
    quoted_src="$(/usr/bin/python3 -c 'import shlex, sys; print(shlex.quote(sys.argv[1]))' "$SOURCE_APP")"
    quoted_dest="$(/usr/bin/python3 -c 'import shlex, sys; print(shlex.quote(sys.argv[1]))' "$DEST_APP")"
    if ! run_as_admin "rm -rf $quoted_dest && ditto $quoted_src $quoted_dest && xattr -dr com.apple.quarantine $quoted_dest"; then
      fail "没有获得系统授权，安装已停止。请重新双击「安装 RightKey」。"
    fi
  fi
fi

[[ -d "$DEST_APP" && "$(bundle_id "$DEST_APP")" == "$BUNDLE_ID" ]] || fail "新版本没有安装成功。"
xattr -dr com.apple.quarantine "$DEST_APP" 2>/dev/null || true

if [[ "$SKIP_SYSTEM" != 1 ]]; then
  pluginkit -a "$DEST_APP/Contents/PlugIns/RightKeyFinderSync.appex" >/dev/null 2>&1 || true
  pluginkit -e use -i "$BUNDLE_ID.findersync" >/dev/null 2>&1 || true
  killall Finder >/dev/null 2>&1 || true
  open "$DEST_APP"
fi

DONE="安装完成。接下来只需要用鼠标操作：若系统询问是否打开 RightKey，选择打开；在应用中启用访达扩展；需要访问桌面、文稿或下载时选择允许。可以关闭此窗口。"
if [[ "$DEST_ROOT" == "$SEARCH_HOME/Applications" ]]; then
  DONE="安装完成，新版本在个人「应用程序」文件夹。接下来只需要用鼠标确认系统提示，并在应用中启用访达扩展。可以关闭此窗口。"
fi
info "$DONE"
