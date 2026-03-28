#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== Step 1: Extract proto descriptors from ProPresenter ==="
swift run --package-path "$REPO_ROOT/Tools/ProtoExtractor"

echo ""
echo "=== Step 2: Generate Swift types with protoc ==="
mkdir -p "$REPO_ROOT/Sela/Proto/Generated"
protoc \
  -I "$REPO_ROOT/Proto/v21" \
  -I /opt/homebrew/include \
  --swift_out="$REPO_ROOT/Sela/Proto/Generated" \
  "$REPO_ROOT/Proto/v21/"*.proto

echo ""
echo "Done! Generated $(ls "$REPO_ROOT/Sela/Proto/Generated/"*.swift | wc -l | tr -d ' ') Swift files."
