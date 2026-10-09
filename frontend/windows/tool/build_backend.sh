#!/usr/bin/env bash
# Rebuilds windows/backend.dll from backend/NetworksButBetter (the same Zig
# backend the phone app uses). Needs Zig 0.16: set ZIG, or install it to
# ~/.zvm/0.16.0, or have `zig` on PATH. Run from Git Bash:
#   frontend/windows/tool/build_backend.sh
set -euo pipefail

ZIG="${ZIG:-$HOME/.zvm/0.16.0/zig.exe}"
[ -x "$ZIG" ] || ZIG="$(command -v zig)"
APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(git -C "$APP_DIR" rev-parse --show-toplevel)"
SRC="$REPO/backend/NetworksButBetter/backend/src"

echo "Building $SRC with Zig $("$ZIG" version)"
(cd "$SRC" && "$ZIG" build all -Doptimize=ReleaseSafe)
cp "$SRC/zig-out/windows/backend.dll" "$APP_DIR/windows/backend.dll"
echo "Updated $APP_DIR/windows/backend.dll"
