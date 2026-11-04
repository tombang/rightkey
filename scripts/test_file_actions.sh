#!/bin/zsh
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT_DIR/.build/tests"
swiftc "$ROOT_DIR/RightKey/Shared/FileClipboard.swift" \
  "$ROOT_DIR/RightKey/Shared/FileOperations.swift" \
  "$ROOT_DIR/RightKey/Shared/FileTemplates.swift" \
  "$ROOT_DIR/RightKey/Shared/HostFileRequest.swift" \
  "$ROOT_DIR/RightKey/Shared/TerminalApplication.swift" \
  "$ROOT_DIR/RightKey/Shared/PathJump.swift" \
  "$ROOT_DIR/tests/TerminalTests.swift" \
  "$ROOT_DIR/tests/PathJumpTests.swift" \
  "$ROOT_DIR/tests/FileActionTests.swift" \
  -module-cache-path "$ROOT_DIR/.build/tests/module-cache" -o "$ROOT_DIR/.build/tests/FileActionTests"
if [[ "${1:-}" != "--build-only" ]]; then
  "$ROOT_DIR/.build/tests/FileActionTests"
fi
