#!/bin/zsh
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT_DIR/.build/tests"
swiftc "$ROOT_DIR/RightKey/Shared/DirectoryMarks.swift" \
  "$ROOT_DIR/RightKey/Shared/FileClipboard.swift" \
  "$ROOT_DIR/RightKey/Shared/FileOperations.swift" \
  "$ROOT_DIR/RightKey/Shared/ArchiveFormat.swift" \
  "$ROOT_DIR/RightKey/Shared/HostFileRequest.swift" \
  "$ROOT_DIR/RightKey/Shared/TerminalApplication.swift" \
  "$ROOT_DIR/tests/DirectoryMarkTests.swift" \
  -module-cache-path "$ROOT_DIR/.build/tests/module-cache" -o "$ROOT_DIR/.build/tests/DirectoryMarkTests"
if [[ "${1:-}" != "--build-only" ]]; then
  "$ROOT_DIR/.build/tests/DirectoryMarkTests"
fi
