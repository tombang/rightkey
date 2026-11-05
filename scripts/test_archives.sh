#!/bin/zsh
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT_DIR/.build/tests"
clang -Wall -Wextra -Werror -c "$ROOT_DIR/RightKey/ArchiveSupport/ArchiveValidation.c" -o "$ROOT_DIR/.build/tests/ArchiveValidation.o"
swiftc "$ROOT_DIR/RightKey/Shared/ArchiveFormat.swift" \
  "$ROOT_DIR/RightKey/Shared/ArchiveOperations.swift" \
  "$ROOT_DIR/tests/ArchiveTests.swift" "$ROOT_DIR/.build/tests/ArchiveValidation.o" \
  -import-objc-header "$ROOT_DIR/RightKey/ArchiveSupport/ArchiveValidation.h" -larchive \
  -module-cache-path "$ROOT_DIR/.build/tests/module-cache" -o "$ROOT_DIR/.build/tests/ArchiveTests"
python3 "$ROOT_DIR/tests/archive_fixtures.py" "$ROOT_DIR/.build/tests/archive-fixtures"
"$ROOT_DIR/.build/tests/ArchiveTests" "${1:-$ROOT_DIR/RightKey/Resources}" "$ROOT_DIR/.build/tests/archive-fixtures" "$ROOT_DIR/tests/fixtures"
