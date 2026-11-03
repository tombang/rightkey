#!/bin/zsh
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d /tmp/rightkey-template-check.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc "$ROOT_DIR/RightKey/Shared/FileTemplates.swift" "$ROOT_DIR/tests/TemplateTests.swift" \
  -module-cache-path "$TEST_DIR/module-cache" -o "$TEST_DIR/TemplateTests"
"$TEST_DIR/TemplateTests"
