#!/usr/bin/env bash
# Builds the Zig backend (backend/client in this repo) into the Android
# libraries this app loads: android/app/src/main/jniLibs/<abi>/libbackend.so
#
# By default it compiles the backend source in THIS branch. To pick up newer
# backend work, first merge Emiliano's branch into yours:
#     git fetch origin && git merge origin/backend
# then run this script again.
#
# Why not the backend's own `zig build all`? Its Android targets aren't linked
# against Android's C library (libc.so), so phones refuse to load the result
# ("cannot locate symbol __tls_get_addr"). Here we pass the Android NDK's libc
# with `-lc --libc`. Once build.zig does the same, this script can go back to
# `zig build all`.
#
# Needs: Zig 0.16.0 (ZIG=path/to/zig to override), Android NDK.
# Usage (from frontend/phone):  bash tool/build_backend.sh
set -euo pipefail

ZIG="${ZIG:-$HOME/.zvm/0.16.0/zig.exe}"
[ -x "$ZIG" ] || ZIG="$(command -v zig)"
API=29   # Android 10+: first version whose libc has __tls_get_addr

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(git -C "$APP_DIR" rev-parse --show-toplevel)"
SRC="$REPO/backend/client"
SDK="${ANDROID_HOME:-${LOCALAPPDATA:-$HOME}/Android/Sdk}"
NDK="$(ls -d "$SDK"/ndk/* | sort -V | tail -1)"
SYSROOT="$(ls -d "$NDK"/toolchains/llvm/prebuilt/*/sysroot | head -1)"
command -v cygpath >/dev/null && SYSROOT="$(cygpath -m "$SYSROOT")"

[ -f "$SRC/src/api.zig" ] || { echo "No backend source at $SRC (merge origin/backend first)"; exit 1; }
COMMIT="$(git -C "$REPO" log -1 --format=%h -- backend/client/src)"
echo "Building backend/client (last source change: $COMMIT) with Zig $("$ZIG" version)"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

#        jniLibs folder   zig target              NDK lib folder
for row in "arm64-v8a       aarch64-linux-android   aarch64-linux-android" \
           "armeabi-v7a     arm-linux-androideabi   arm-linux-androideabi" \
           "x86_64          x86_64-linux-android    x86_64-linux-android"; do
  read -r ABI TARGET NDKLIB <<<"$row"
  LIBC_FILE="$TMP/libc-$ABI.txt"
  cat > "$LIBC_FILE" <<EOF
include_dir=$SYSROOT/usr/include
sys_include_dir=$SYSROOT/usr/include/$NDKLIB
crt_dir=$SYSROOT/usr/lib/$NDKLIB/$API
msvc_lib_dir=
kernel32_lib_dir=
gcc_dir=
EOF
  OUT="$APP_DIR/android/app/src/main/jniLibs/$ABI"
  mkdir -p "$OUT"
  # Build in a temp cache so nothing is written into backend/client.
  (cd "$SRC" && "$ZIG" build-lib src/api.zig -dynamic -OReleaseFast \
      -target "$TARGET" -lc --libc "$LIBC_FILE" --name backend \
      --cache-dir "$TMP/zig-cache" -femit-bin="$OUT/libbackend.so")
  rm -f "$OUT"/*.o "$OUT"/*.pdb
  echo "  $ABI: $(wc -c < "$OUT/libbackend.so") bytes"
done

sed -i "s/^\*\*Built from:\*\*.*/**Built from:** \`backend\/client\` in this branch (last source change \`$COMMIT\`) on $(date +%Y-%m-%d) with Zig $("$ZIG" version),/" \
  "$APP_DIR/android/app/src/main/jniLibs/README.md"
echo "Done. Rebuild the app to include the new libraries."
