# Shared by build_release.sh and the installer test. Not an executable entrypoint.
package_rightkey_release() {
  local app_path="$1" dist_dir="$2" version="$3" installer="$4"
  [[ -d "$app_path" ]]
  [[ -f "$installer" ]]
  [[ "$version" == <->.<->.<-> ]]
  local stage zip_path check
  stage="$(mktemp -d "${TMPDIR:-/tmp}/rightkey-release.XXXXXX")"
  check="$(mktemp -d "${TMPDIR:-/tmp}/rightkey-release-check.XXXXXX")"
  zip_path="$dist_dir/RightKey-$version.zip"
  mkdir -p "$stage/RightKey-$version" "$dist_dir"
  ditto "$app_path" "$stage/RightKey-$version/RightKey.app"
  cp "$installer" "$stage/RightKey-$version/安装 RightKey.command"
  chmod 755 "$stage/RightKey-$version/安装 RightKey.command"
  rm -f "$zip_path"
  ditto -c -k --sequesterRsrc --keepParent "$stage/RightKey-$version" "$zip_path"
  (
    cd "$dist_dir"
    shasum -a 256 "RightKey-$version.zip" > "RightKey-$version.zip.sha256"
  )
  ditto -x -k "$zip_path" "$check"
  [[ -d "$check/RightKey-$version/RightKey.app" ]]
  [[ -x "$check/RightKey-$version/安装 RightKey.command" ]]
  rm -rf "$stage" "$check"
  printf '%s\n' "$zip_path"
}
